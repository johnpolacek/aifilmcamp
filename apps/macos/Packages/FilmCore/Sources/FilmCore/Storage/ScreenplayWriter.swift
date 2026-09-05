import Foundation
import FilmScript
import GRDB

/// What one screenplay write produced, for summaries and journal `affected` sets.
struct ScreenplayWriteResult: Sendable {
    var sceneIDsByOrdinal: [Int: UUID] = [:]
    var sequenceIDsByOrdinal: [Int: UUID] = [:]
    var entityIDs: [UUID] = []
    var aliasIDs: [UUID] = []
    var appearanceIDs: [UUID] = []
    var evidenceIDs: [UUID] = []
    var exclusionIDs: [UUID] = []
    var characterNames: [String] = []
    var locationNames: [String] = []

    var sceneCount: Int { sceneIDsByOrdinal.count }
    var sequenceCount: Int { sequenceIDsByOrdinal.count }
}

/// Writes a parsed screenplay into schema v2 (PHASE1_DESIGN §5.2, §5.3, §4.2 step 5).
///
/// The v1 → v2 migration's re-parse and Plan 003 Step 2's `importScreenplay` are the same
/// write: §4.2 step 5 says parser entities/aliases/appearances/evidence are created "as in
/// §5.3", so both call this one writer and the two bundles end up byte-comparable.
///
/// Every alias insert is conditional per §3.5, and existing entities are matched by
/// `name_normalized` **first** — a match keeps its id, name, `source`, and `review_state`
/// and only gains parser aliases, appearances, and evidence.
enum ScreenplayWriter {
    /// Writes sequences, scenes, exclusions, and the §5.3 parser entity graph.
    ///
    /// `scripts` and its asset row are the caller's job: the migration rebuilds that row
    /// in place, and import inserts it beside a staged file copy.
    static func write(
        document: ScreenplayDocument,
        projectID: UUID,
        scriptID: UUID,
        jobID: UUID?,
        now: Date,
        matchExistingAliases: Bool = false,
        in db: Database
    ) throws -> ScreenplayWriteResult {
        var result = ScreenplayWriteResult()
        let timestamp = UTCDate.string(from: now)

        // Sequences first: scenes.sequence_id references them.
        for sequence in document.sequences {
            let id = UUID()
            result.sequenceIDsByOrdinal[sequence.ordinal] = id
            try db.execute(
                sql: """
                    INSERT INTO sequences (
                        id, script_id, ordinal, depth, title, start_utf16, end_utf16,
                        source, confidence, review_state, reviewed_at, job_id,
                        created_source, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, 'parser', NULL, 'accepted', NULL, ?, 'parser', ?, ?)
                    """,
                arguments: [
                    id.uuidString, scriptID.uuidString, sequence.ordinal, sequence.depth,
                    sequence.title, sequence.range.start, sequence.range.end,
                    jobID?.uuidString, timestamp, timestamp,
                ]
            )
        }

        for scene in document.scenes {
            let sceneID = UUID()
            result.sceneIDsByOrdinal[scene.ordinal] = sceneID
            let sequenceID = scene.sequenceOrdinal.flatMap { result.sequenceIDsByOrdinal[$0] }
            try db.execute(
                sql: """
                    INSERT INTO scenes (
                        id, script_id, ordinal, sequence_id, heading, int_ext, location_text,
                        time_of_day, scene_number, start_utf16, end_utf16, synopsis, is_omitted
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '', ?)
                    """,
                arguments: [
                    sceneID.uuidString, scriptID.uuidString, scene.ordinal, sequenceID?.uuidString,
                    scene.heading, scene.intExt.rawValue, scene.locationText, scene.timeOfDay,
                    scene.sceneNumber, scene.range.start, scene.range.end, scene.isOmitted ? 1 : 0,
                ]
            )

            // Ranges the model must never see (§4.3).
            for element in scene.elements where element.kind == .note || element.kind == .boneyard {
                let id = UUID()
                result.exclusionIDs.append(id)
                try db.execute(
                    sql: """
                        INSERT INTO scene_exclusions (id, scene_id, kind, start_utf16, end_utf16)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        id.uuidString, sceneID.uuidString,
                        element.kind == .note ? SceneExclusionKind.note.rawValue
                                              : SceneExclusionKind.boneyard.rawValue,
                        element.range.start, element.range.end,
                    ]
                )
            }
        }

        var writer = EntityWriter(
            projectID: projectID,
            jobID: jobID,
            timestamp: timestamp,
            matchExistingAliases: matchExistingAliases,
            result: result
        )
        try writer.writeCharacters(document: document, in: db)
        try writer.writeLocations(document: document, in: db)
        return writer.result
    }
}

/// The §5.3 entity half of a screenplay write, kept together so the alias-conditional
/// insert and the `matched_alias_id` link are written in exactly one place.
private struct EntityWriter {
    let projectID: UUID
    let jobID: UUID?
    let timestamp: String
    let matchExistingAliases: Bool
    var result: ScreenplayWriteResult

    /// One `character` entity per distinct normalized cue, a `speaking` appearance in each
    /// scene the cue occurs in, and parser evidence spanning the cue line.
    mutating func writeCharacters(document: ScreenplayDocument, in db: Database) throws {
        // Normalized name → (display source, first raw form seen, occurrences by scene).
        var order: [String] = []
        var rawForms: [String: String] = [:]
        var cueNames: [String: String] = [:]
        var occurrences: [String: [(sceneOrdinal: Int, cue: ParsedCue)]] = [:]

        for scene in document.scenes {
            for cue in scene.cues {
                let normalized = EntityNormalization.normalize(cue.normalized)
                guard !normalized.isEmpty else { continue }
                if occurrences[normalized] == nil {
                    order.append(normalized)
                    rawForms[normalized] = cue.raw
                    cueNames[normalized] = cue.normalized
                    occurrences[normalized] = []
                }
                occurrences[normalized]?.append((scene.ordinal, cue))
            }
        }

        for normalized in order {
            let display = DisplayCase.titleCased(cueNames[normalized] ?? normalized)
            let entityID = try resolveEntity(kind: .character, display: display, normalized: normalized, in: db)
            if matchExistingAliases, try isRejected(entityID, in: db) { continue }
            let aliasID = try insertAliasIfAbsent(
                entityID: entityID,
                kind: .character,
                alias: rawForms[normalized] ?? display,
                normalized: normalized,
                aliasKind: .cue,
                in: db
            )
            if !result.characterNames.contains(display) { result.characterNames.append(display) }

            // One appearance per scene, evidence per cue occurrence.
            var appearanceBySceneOrdinal: [Int: UUID] = [:]
            for occurrence in occurrences[normalized] ?? [] {
                guard let sceneID = result.sceneIDsByOrdinal[occurrence.sceneOrdinal] else { continue }
                let appearanceID: UUID
                if let existing = appearanceBySceneOrdinal[occurrence.sceneOrdinal] {
                    appearanceID = existing
                } else {
                    appearanceID = try insertAppearance(
                        sceneID: sceneID,
                        entityID: entityID,
                        role: .speaking,
                        matchedAliasID: aliasID,
                        in: db
                    )
                    appearanceBySceneOrdinal[occurrence.sceneOrdinal] = appearanceID
                }
                try insertEvidence(
                    subjectKind: .appearance,
                    subjectID: appearanceID,
                    ownerEntityID: entityID,
                    sceneID: sceneID,
                    matchedAliasID: aliasID,
                    range: occurrence.cue.range,
                    quote: occurrence.cue.raw,
                    in: db
                )
            }
        }
    }

    /// One `location` entity per distinct normalized `locationText` (never the heading
    /// line), a `setting` appearance per scene, evidence spanning the heading.
    mutating func writeLocations(document: ScreenplayDocument, in db: Database) throws {
        var order: [String] = []
        var rawForms: [String: String] = [:]
        var scenesByNormalized: [String: [ParsedScene]] = [:]

        for scene in document.scenes {
            let normalized = EntityNormalization.normalize(scene.locationText)
            guard !normalized.isEmpty else { continue }
            if scenesByNormalized[normalized] == nil {
                order.append(normalized)
                rawForms[normalized] = scene.locationText
                scenesByNormalized[normalized] = []
            }
            scenesByNormalized[normalized]?.append(scene)
        }

        for normalized in order {
            let display = DisplayCase.titleCased(rawForms[normalized] ?? normalized)
            let entityID = try resolveEntity(kind: .location, display: display, normalized: normalized, in: db)
            if matchExistingAliases, try isRejected(entityID, in: db) { continue }
            let aliasID = try insertAliasIfAbsent(
                entityID: entityID,
                kind: .location,
                alias: rawForms[normalized] ?? display,
                normalized: normalized,
                aliasKind: .heading,
                in: db
            )
            if !result.locationNames.contains(display) { result.locationNames.append(display) }

            for scene in scenesByNormalized[normalized] ?? [] {
                guard let sceneID = result.sceneIDsByOrdinal[scene.ordinal] else { continue }
                let appearanceID = try insertAppearance(
                    sceneID: sceneID,
                    entityID: entityID,
                    role: .setting,
                    matchedAliasID: aliasID,
                    in: db
                )
                let headingRange = scene.elements.first(where: { $0.kind == .sceneHeading })?.range
                try insertEvidence(
                    subjectKind: .appearance,
                    subjectID: appearanceID,
                    ownerEntityID: entityID,
                    sceneID: sceneID,
                    matchedAliasID: aliasID,
                    range: headingRange,
                    quote: scene.heading,
                    in: db
                )
            }
        }
    }

    private func isRejected(_ id: UUID, in db: Database) throws -> Bool {
        try String.fetchOne(db, sql: "SELECT review_state FROM entities WHERE id = ?", arguments: [id.uuidString]) == "rejected"
    }

    // MARK: - Row writers

    /// Matches an existing entity by `name_normalized` first (§4.2 step 5): a match keeps
    /// its id, name, `source`, and `review_state`; a non-match is created
    /// `source = 'parser'`, `review_state = 'accepted'`.
    private mutating func resolveEntity(
        kind: EntityKind,
        display: String,
        normalized: String,
        in db: Database
    ) throws -> UUID {
        if let existing = try String.fetchOne(
            db,
            sql: "SELECT id FROM entities WHERE project_id = ? AND kind = ? AND name_normalized = ?",
            arguments: [projectID.uuidString, kind.rawValue, normalized]
        ) {
            return try UUID.required(existing)
        }
        if matchExistingAliases,
           let existing = try String.fetchOne(
            db,
            sql: "SELECT entity_id FROM entity_aliases WHERE project_id = ? AND kind = ? AND normalized = ?",
            arguments: [projectID.uuidString, kind.rawValue, normalized]
           ) {
            return try UUID.required(existing)
        }
        let id = UUID()
        try db.execute(
            sql: """
                INSERT INTO entities (
                    id, project_id, kind, name, name_normalized, description, parent_id, is_relevant,
                    source, confidence, review_state, reviewed_at, job_id,
                    created_source, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, '', NULL, 1, 'parser', NULL, 'accepted', NULL, ?, 'parser', ?, ?)
                """,
            arguments: [
                id.uuidString, projectID.uuidString, kind.rawValue, display, normalized,
                jobID?.uuidString, timestamp, timestamp,
            ]
        )
        result.entityIDs.append(id)
        return id
    }

    /// The conditional alias insert of §3.5: same `(project_id, kind, normalized)` on the
    /// same entity → skip and return the existing row; on another entity → `.aliasConflict`.
    private mutating func insertAliasIfAbsent(
        entityID: UUID,
        kind: EntityKind,
        alias: String,
        normalized: String,
        aliasKind: AliasKind,
        in db: Database
    ) throws -> UUID {
        if let row = try Row.fetchOne(
            db,
            sql: "SELECT id, entity_id FROM entity_aliases WHERE project_id = ? AND kind = ? AND normalized = ?",
            arguments: [projectID.uuidString, kind.rawValue, normalized]
        ) {
            let owner = try UUID.required(row["entity_id"])
            guard owner == entityID else { throw ProjectStoreError.aliasConflict(existingEntityID: owner) }
            return try UUID.required(row["id"])
        }
        if matchExistingAliases {
            try ProtectionPolicy.checkAliasAddition(
                toEntity: SubjectRef(kind: .entity, id: entityID), actor: .human, in: db
            )
        }
        let id = UUID()
        try db.execute(
            sql: """
                INSERT INTO entity_aliases (
                    id, entity_id, project_id, kind, alias, normalized, alias_kind,
                    source, confidence, review_state, reviewed_at, job_id,
                    created_source, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, 'parser', NULL, 'accepted', NULL, ?, 'parser', ?, ?)
                """,
            arguments: [
                id.uuidString, entityID.uuidString, projectID.uuidString, kind.rawValue,
                alias, normalized, aliasKind.rawValue, jobID?.uuidString, timestamp, timestamp,
            ]
        )
        result.aliasIDs.append(id)
        return id
    }

    private mutating func insertAppearance(
        sceneID: UUID,
        entityID: UUID,
        role: SceneEntityRole,
        matchedAliasID: UUID?,
        in db: Database
    ) throws -> UUID {
        if matchExistingAliases,
           let existing = try String.fetchOne(
            db,
            sql: "SELECT id FROM scene_entities WHERE scene_id = ? AND entity_id = ? AND role = ?",
            arguments: [sceneID.uuidString, entityID.uuidString, role.rawValue]
           ) {
            return try UUID.required(existing)
        }
        let id = UUID()
        try db.execute(
            sql: """
                INSERT INTO scene_entities (
                    id, scene_id, entity_id, role, matched_alias_id,
                    source, confidence, review_state, reviewed_at, job_id,
                    created_source, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, 'parser', NULL, 'accepted', NULL, ?, 'parser', ?, ?)
                """,
            arguments: [
                id.uuidString, sceneID.uuidString, entityID.uuidString, role.rawValue,
                matchedAliasID?.uuidString, jobID?.uuidString, timestamp, timestamp,
            ]
        )
        result.appearanceIDs.append(id)
        return id
    }

    private mutating func insertEvidence(
        subjectKind: SubjectKind,
        subjectID: UUID,
        ownerEntityID: UUID?,
        sceneID: UUID,
        matchedAliasID: UUID?,
        range: FilmScript.UTF16Range?,
        quote: String,
        in db: Database
    ) throws {
        let id = UUID()
        try db.execute(
            sql: """
                INSERT INTO evidence (
                    id, subject_kind, subject_id, owner_entity_id, scene_id, matched_alias_id,
                    start_utf16, end_utf16, anchored, quote, source, job_id, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'parser', ?, ?)
                """,
            arguments: [
                id.uuidString, subjectKind.rawValue, subjectID.uuidString, ownerEntityID?.uuidString,
                sceneID.uuidString, matchedAliasID?.uuidString, range?.start, range?.end,
                range == nil ? 0 : 1, quote, jobID?.uuidString, timestamp,
            ]
        )
        result.evidenceIDs.append(id)
    }
}
