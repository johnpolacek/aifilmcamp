import Foundation
import GRDB

/// The per-project requirement template (PHASE2_DESIGN §3.2, §4.3, §7.2).
///
/// Template rows are **settings**, like `locks`: no PROV block, human-edited only, and
/// journaled through these operations. Editing the template decides which canonical
/// requirements §5.2's Build generates *from then on*; it never silently deletes or renames
/// an existing requirement row (§3.2, §5.3) — a requirement's `name` is its own, copied at
/// creation.
///
/// No transaction is opened here (§7.1).
enum TemplateOperations {

    /// The columns a template operation needs.
    struct TemplateRow {
        let id: UUID
        let projectID: UUID
        let entityKind: EntityKind
        let code: String
        let displayName: String
        let sortOrder: Int
        let isEnabled: Bool

        var ref: SubjectRef { SubjectRef(kind: .templateEntry, id: id) }
    }

    static func fetch(id: UUID, in db: Database) throws -> TemplateRow? {
        guard let row = try Row.fetchOne(
            db, sql: "SELECT * FROM asset_requirement_types WHERE id = ?",
            arguments: [id.uuidString]
        ) else { return nil }
        guard let kind = EntityKind(rawValue: row["entity_kind"]) else {
            throw ProjectStoreError.invalidBundle
        }
        return TemplateRow(
            id: try UUID.required(row["id"]),
            projectID: try UUID.required(row["project_id"]),
            entityKind: kind,
            code: row["code"],
            displayName: row["display_name"],
            sortOrder: row["sort_order"],
            isEnabled: (row["is_enabled"] as Int) != 0
        )
    }

    static func require(id: UUID, in db: Database) throws -> TemplateRow {
        guard let row = try fetch(id: id, in: db) else {
            throw ProjectStoreError.invalidTemplateEntry(
                reason: "That template entry is not in this project."
            )
        }
        return row
    }

    // MARK: - Scalar edits

    static func setEnabled(
        typeID: UUID,
        isEnabled: Bool,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        try update(
            typeID: typeID, actor: actor, mode: mode,
            assignments: "is_enabled = ?", values: [isEnabled ? 1 : 0],
            redo: { .setTemplateEntryEnabled(typeID: typeID, isEnabled: $0.isEnabled) },
            in: db
        )
    }

    /// §3.2: a rename **never touches existing requirement rows**. Display names stay
    /// normalized-unique per `(project, entity_kind)` so the requirement names Build
    /// generates from them cannot collide.
    static func rename(
        typeID: UUID,
        displayName: String,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        try update(
            typeID: typeID, actor: actor, mode: mode,
            assignments: "display_name = ?", values: [
                displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            ],
            validate: { row in
                let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    throw ProjectStoreError.invalidTemplateEntry(
                        reason: "A template entry needs a name."
                    )
                }
                try requireUniqueDisplayName(
                    trimmed, projectID: row.projectID, kind: row.entityKind,
                    excluding: typeID, in: db
                )
            },
            redo: { .renameTemplateEntry(typeID: typeID, displayName: $0.displayName) },
            in: db
        )
    }

    static func setOrder(
        typeID: UUID,
        sortOrder: Int,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        try update(
            typeID: typeID, actor: actor, mode: mode,
            assignments: "sort_order = ?", values: [sortOrder],
            redo: { .setTemplateEntryOrder(typeID: typeID, sortOrder: $0.sortOrder) },
            in: db
        )
    }

    /// The shape all three scalar template edits share: human-only, snapshot, assign,
    /// `updated_at`.
    private static func update(
        typeID: UUID,
        actor: MutationActor,
        mode: MutationMode,
        assignments: String,
        values: StatementArguments,
        validate: ((TemplateRow) throws -> Void)? = nil,
        redo: (TemplateRow) -> EditOperation,
        in db: Database
    ) throws -> MutationEffect {
        let ref = SubjectRef(kind: .templateEntry, id: typeID)
        if let entry = mode.invertedEntry {
            let current = try require(id: typeID, in: db)
            guard let snapshot = entry.snapshot(table: "asset_requirement_types", id: typeID) else {
                throw ProjectStoreError.inverseNoLongerApplicable(
                    reason: "That change no longer has a template entry to restore."
                )
            }
            let prior = try RowSnapshotStore.capture(
                table: "asset_requirement_types", id: typeID, in: db
            )
            try RowSnapshotStore.restore(snapshot, in: db)
            return MutationEffect(
                inverse: redo(current), affected: [ref], snapshots: prior.map { [$0] } ?? []
            )
        }
        let row = try require(id: typeID, in: db)
        try RequirementOperations.requireHuman(actor, subject: ref)
        try validate?(row)
        let snapshot = try RowSnapshotStore.capture(
            table: "asset_requirement_types", id: typeID, in: db
        )
        var arguments = values
        arguments += [UTCDate.string(from: Date()), typeID.uuidString]
        try db.execute(
            sql: "UPDATE asset_requirement_types SET \(assignments), updated_at = ? WHERE id = ?",
            arguments: arguments
        )
        return MutationEffect(
            inverse: redo(row), affected: [ref], snapshots: snapshot.map { [$0] } ?? []
        )
    }

    // MARK: - add / remove / restore

    /// §4.3's Swift validation, in full: `code` is `[a-z0-9_]+` and unique per
    /// `(project, entity_kind)`, and the display name is normalized-unique for that pair.
    static func add(
        id: UUID,
        kind: EntityKind,
        code: String,
        displayName: String,
        sortOrder: Int,
        actor: MutationActor,
        in db: Database
    ) throws -> MutationEffect {
        let ref = SubjectRef(kind: .templateEntry, id: id)
        try RequirementOperations.requireHuman(actor, subject: ref)
        let projectID = try EntityOperations.projectID(in: db)
        guard !code.isEmpty, code.allSatisfy({ $0.isLowercaseASCIILetter || $0.isASCIIDigit || $0 == "_" })
        else {
            throw ProjectStoreError.invalidTemplateEntry(
                reason: "A template entry's code uses lowercase letters, digits, and underscores only."
            )
        }
        if try Bool.fetchOne(
            db,
            sql: """
                SELECT EXISTS(
                    SELECT 1 FROM asset_requirement_types
                    WHERE project_id = ? AND entity_kind = ? AND code = ?
                )
                """,
            arguments: [projectID.uuidString, kind.rawValue, code]
        ) ?? false {
            throw ProjectStoreError.invalidTemplateEntry(
                reason: "That template entry already exists for this kind of item."
            )
        }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProjectStoreError.invalidTemplateEntry(reason: "A template entry needs a name.")
        }
        try requireUniqueDisplayName(
            trimmed, projectID: projectID, kind: kind, excluding: id, in: db
        )

        let timestamp = UTCDate.string(from: Date())
        try db.execute(
            sql: """
                INSERT INTO asset_requirement_types (
                    id, project_id, entity_kind, code, display_name, sort_order, is_enabled,
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)
                """,
            arguments: [
                id.uuidString, projectID.uuidString, kind.rawValue, code, trimmed, sortOrder,
                timestamp, timestamp,
            ]
        )
        return MutationEffect(inverse: .removeTemplateEntry(typeID: id), affected: [ref])
    }

    /// §7.2: refused while **any** requirement references the entry, tombstoned rows
    /// included — `ON DELETE RESTRICT` backs it, and a tombstone keeps its `type_id`.
    static func remove(
        typeID: UUID,
        actor: MutationActor,
        in db: Database
    ) throws -> MutationEffect {
        let ref = SubjectRef(kind: .templateEntry, id: typeID)
        _ = try require(id: typeID, in: db)
        try RequirementOperations.requireHuman(actor, subject: ref)
        if try Bool.fetchOne(
            db,
            sql: "SELECT EXISTS(SELECT 1 FROM asset_requirements WHERE type_id = ?)",
            arguments: [typeID.uuidString]
        ) ?? false {
            throw ProjectStoreError.templateEntryInUse(typeID: typeID)
        }
        guard let snapshot = try RowSnapshotStore.capture(
            table: "asset_requirement_types", id: typeID, in: db
        ) else {
            throw ProjectStoreError.invalidTemplateEntry(
                reason: "That template entry is not in this project."
            )
        }
        try RowSnapshotStore.delete(table: "asset_requirement_types", id: typeID, in: db)
        return MutationEffect(
            inverse: .restoreTemplateEntry(snapshot: [snapshot]),
            affected: [ref],
            snapshots: [snapshot]
        )
    }

    static func restore(snapshot: [RowSnapshot], in db: Database) throws -> MutationEffect {
        guard let id = RequirementOperations.rowID(of: "asset_requirement_types", in: snapshot) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That change no longer has a template entry to restore."
            )
        }
        try RowGraph.restore(snapshot, in: db)
        return MutationEffect(
            inverse: .removeTemplateEntry(typeID: id),
            affected: [SubjectRef(kind: .templateEntry, id: id)]
        )
    }

    // MARK: - Helpers and preconditions

    static func requireUniqueDisplayName(
        _ displayName: String,
        projectID: UUID,
        kind: EntityKind,
        excluding id: UUID,
        in db: Database
    ) throws {
        let normalized = EntityNormalization.normalize(displayName)
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT id, display_name FROM asset_requirement_types
                WHERE project_id = ? AND entity_kind = ? AND id <> ?
                """,
            arguments: [projectID.uuidString, kind.rawValue, id.uuidString]
        ) {
            guard EntityNormalization.normalize(row["display_name"]) == normalized else { continue }
            throw ProjectStoreError.invalidTemplateEntry(
                reason: "Another template entry for that kind of item is already called “\(displayName)”."
            )
        }
    }

    static func precheckRow(typeID: UUID, in db: Database) throws {
        guard try RowSnapshotStore.exists(table: "asset_requirement_types", id: typeID, in: db) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That template entry is no longer in this project."
            )
        }
    }

    static func precheckAdd(id: UUID, in db: Database) throws {
        guard try !RowSnapshotStore.exists(table: "asset_requirement_types", id: id, in: db) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "Something that change removed is already back."
            )
        }
    }
}

private extension Character {
    var isLowercaseASCIILetter: Bool { self >= "a" && self <= "z" }
    var isASCIIDigit: Bool { self >= "0" && self <= "9" }
}
