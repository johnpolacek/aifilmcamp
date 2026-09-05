import Foundation
import FilmScript
import GRDB

// One place where a v2 row becomes a domain value. Nothing outside `Storage/` sees a
// GRDB `Row`, which is what keeps `Domain/` and `ProjectTools.swift` GRDB-free (§3.1).

func decodeProject(_ row: Row) throws -> Project {
    Project(
        id: try UUID.required(row["id"]),
        name: row["name"],
        bundleSchemaVersion: row["bundle_schema_version"],
        currentScriptID: try (row["current_script_id"] as String?).map(UUID.required),
        disclosureAcknowledgedAt: try (row["disclosure_acknowledged_at"] as String?).map(UTCDate.date),
        createdAt: try UTCDate.date(from: row["created_at"]),
        updatedAt: try UTCDate.date(from: row["updated_at"])
    )
}

func decodeScript(_ row: Row) throws -> Script {
    guard let format = ScreenplayFormat(rawValue: row["format"]) else {
        throw ProjectStoreError.invalidBundle
    }
    let titlePage = (try? JSONDecoder().decode(TitlePage.self, from: Data((row["title_page_json"] as String).utf8)))
        ?? TitlePage(entries: [], lines: [])
    return Script(
        id: try UUID.required(row["id"]),
        projectID: try UUID.required(row["project_id"]),
        displayName: row["display_name"],
        sourceAssetID: try UUID.required(row["source_asset_id"]),
        format: format,
        originalAssetID: try UUID.required(row["original_asset_id"]),
        sourceText: row["source_text"],
        sha256: row["sha256"],
        titlePage: titlePage,
        parserVersion: row["parser_version"],
        parseWarnings: decodeWarnings(row["parse_warnings_json"]),
        createdAt: try UTCDate.date(from: row["created_at"])
    )
}

func decodeWarnings(_ json: String) -> [ParseWarning] {
    (try? JSONDecoder().decode([ParseWarning].self, from: Data(json.utf8))) ?? []
}

func decodeJob(_ row: Row) throws -> Job {
    guard let state = Job.State(rawValue: row["state"]) else { throw ProjectStoreError.invalidBundle }
    return Job(
        id: try UUID.required(row["id"]),
        projectID: try UUID.required(row["project_id"]),
        task: row["task"],
        engine: row["engine"],
        engineVersion: row["engine_version"],
        requestedModel: row["requested_model"],
        effectiveModel: row["effective_model"],
        schemaVersion: row["schema_version"],
        inputSHA256: row["input_sha256"],
        state: state,
        progressStage: row["progress_stage"],
        usage: try JobUsage(
            inputTokens: row["input_tokens"],
            cachedInputTokens: row["cached_input_tokens"],
            cacheWriteInputTokens: row["cache_write_input_tokens"],
            outputTokens: row["output_tokens"],
            reasoningOutputTokens: row["reasoning_output_tokens"]
        ),
        logRelativePath: try RelativeProjectPath(row["log_relative_path"] as String),
        resultRelativePath: try RelativeProjectPath(row["result_relative_path"] as String),
        startedAt: try (row["started_at"] as String?).map(UTCDate.date),
        endedAt: try (row["ended_at"] as String?).map(UTCDate.date),
        failureCode: row["failure_code"],
        failureMessage: row["failure_message"],
        parentJobID: try (row["parent_job_id"] as String?).map(UUID.required),
        chunkIndex: row["chunk_index"],
        chunkCount: row["chunk_count"],
        attemptIndex: row["attempt_index"],
        supersedesJobID: try (row["supersedes_job_id"] as String?).map(UUID.required),
        scriptID: try (row["script_id"] as String?).map(UUID.required),
        scriptSHA256: row["script_sha256"],
        applyReportJSON: row["apply_report"]
    )
}

// MARK: - Fact rows

/// §4.3's `PROV` block, decoded once for every fact table.
func decodeProvenance(_ row: Row) throws -> Provenance {
    guard let source = FactSource(rawValue: row["source"]),
          let createdSource = FactSource(rawValue: row["created_source"]),
          let reviewState = ReviewState(rawValue: row["review_state"])
    else { throw ProjectStoreError.invalidBundle }
    return Provenance(
        source: source,
        createdSource: createdSource,
        confidence: row["confidence"],
        reviewState: reviewState,
        reviewedAt: try (row["reviewed_at"] as String?).map(UTCDate.date),
        jobID: try (row["job_id"] as String?).map(UUID.required),
        createdAt: try UTCDate.date(from: row["created_at"]),
        updatedAt: try UTCDate.date(from: row["updated_at"])
    )
}

func decodeScene(_ row: Row) throws -> Scene {
    guard let intExt = SceneIntExt(rawValue: row["int_ext"]) else {
        throw ProjectStoreError.invalidBundle
    }
    return Scene(
        id: try UUID.required(row["id"]),
        scriptID: try UUID.required(row["script_id"]),
        ordinal: row["ordinal"],
        sequenceID: try (row["sequence_id"] as String?).map(UUID.required),
        heading: row["heading"],
        intExt: intExt,
        locationText: row["location_text"],
        timeOfDay: row["time_of_day"],
        sceneNumber: row["scene_number"],
        range: UTF16Range(start: row["start_utf16"], end: row["end_utf16"]),
        isOmitted: (row["is_omitted"] as Int) != 0,
        synopsis: row["synopsis"],
        synopsisSource: (row["synopsis_source"] as String?).flatMap(FactSource.init(rawValue:)),
        synopsisCreatedSource: (row["synopsis_created_source"] as String?).flatMap(FactSource.init(rawValue:)),
        synopsisConfidence: row["synopsis_confidence"],
        synopsisReviewState: (row["synopsis_review_state"] as String?).flatMap(ReviewState.init(rawValue:)),
        synopsisReviewedAt: try (row["synopsis_reviewed_at"] as String?).map(UTCDate.date),
        synopsisJobID: try (row["synopsis_job_id"] as String?).map(UUID.required),
        synopsisUpdatedAt: try (row["synopsis_updated_at"] as String?).map(UTCDate.date)
    )
}

func decodeScriptSequence(_ row: Row) throws -> ScriptSequence {
    ScriptSequence(
        id: try UUID.required(row["id"]),
        scriptID: try UUID.required(row["script_id"]),
        ordinal: row["ordinal"],
        depth: row["depth"],
        title: row["title"],
        range: UTF16Range(start: row["start_utf16"], end: row["end_utf16"]),
        provenance: try decodeProvenance(row)
    )
}

func decodeSceneExclusion(_ row: Row) throws -> SceneExclusion {
    guard let kind = SceneExclusionKind(rawValue: row["kind"]) else {
        throw ProjectStoreError.invalidBundle
    }
    return SceneExclusion(
        id: try UUID.required(row["id"]),
        sceneID: try UUID.required(row["scene_id"]),
        kind: kind,
        range: UTF16Range(start: row["start_utf16"], end: row["end_utf16"])
    )
}

func decodeEntity(_ row: Row) throws -> Entity {
    guard let kind = EntityKind(rawValue: row["kind"]) else { throw ProjectStoreError.invalidBundle }
    return Entity(
        id: try UUID.required(row["id"]),
        projectID: try UUID.required(row["project_id"]),
        kind: kind,
        name: row["name"],
        nameNormalized: row["name_normalized"],
        description: row["description"],
        parentID: try (row["parent_id"] as String?).map(UUID.required),
        isRelevant: (row["is_relevant"] as Int) != 0,
        // v4's `manifest_inclusion` (§4.2 step 1). The column is `NOT NULL DEFAULT
        // 'automatic'`, so the fallback only covers a projection that omits it.
        manifestInclusion: ManifestInclusion(rawValue: (row["manifest_inclusion"] as String?) ?? "")
            ?? .automatic,
        provenance: try decodeProvenance(row)
    )
}

func decodeEntityAlias(_ row: Row) throws -> EntityAlias {
    guard let kind = EntityKind(rawValue: row["kind"]),
          let aliasKind = AliasKind(rawValue: row["alias_kind"])
    else { throw ProjectStoreError.invalidBundle }
    return EntityAlias(
        id: try UUID.required(row["id"]),
        entityID: try UUID.required(row["entity_id"]),
        projectID: try UUID.required(row["project_id"]),
        kind: kind,
        alias: row["alias"],
        normalized: row["normalized"],
        aliasKind: aliasKind,
        provenance: try decodeProvenance(row)
    )
}

func decodeSceneEntity(_ row: Row) throws -> SceneEntity {
    guard let role = SceneEntityRole(rawValue: row["role"]) else {
        throw ProjectStoreError.invalidBundle
    }
    return SceneEntity(
        id: try UUID.required(row["id"]),
        sceneID: try UUID.required(row["scene_id"]),
        entityID: try UUID.required(row["entity_id"]),
        role: role,
        matchedAliasID: try (row["matched_alias_id"] as String?).map(UUID.required),
        provenance: try decodeProvenance(row)
    )
}

func decodeEntityState(_ row: Row) throws -> EntityState {
    guard let category = StateCategory(rawValue: row["category"]) else {
        throw ProjectStoreError.invalidBundle
    }
    return EntityState(
        id: try UUID.required(row["id"]),
        entityID: try UUID.required(row["entity_id"]),
        category: category,
        description: row["description"],
        startSceneID: try UUID.required(row["start_scene_id"]),
        endSceneID: try (row["end_scene_id"] as String?).map(UUID.required),
        provenance: try decodeProvenance(row)
    )
}

func decodeContinuityEvent(_ row: Row) throws -> ContinuityEvent {
    ContinuityEvent(
        id: try UUID.required(row["id"]),
        sceneID: try UUID.required(row["scene_id"]),
        entityID: try (row["entity_id"] as String?).map(UUID.required),
        description: row["description"],
        resultingStateID: try (row["resulting_state_id"] as String?).map(UUID.required),
        provenance: try decodeProvenance(row)
    )
}

func decodeEntityRelationship(_ row: Row) throws -> EntityRelationship {
    guard let kind = RelationshipKind(rawValue: row["kind"]) else {
        throw ProjectStoreError.invalidBundle
    }
    return EntityRelationship(
        id: try UUID.required(row["id"]),
        fromEntityID: try UUID.required(row["from_entity_id"]),
        toEntityID: try UUID.required(row["to_entity_id"]),
        kind: kind,
        description: row["description"],
        provenance: try decodeProvenance(row)
    )
}

func decodeEvidence(_ row: Row) throws -> Evidence {
    guard let subjectKind = SubjectKind(rawValue: row["subject_kind"]),
          let source = FactSource(rawValue: row["source"])
    else { throw ProjectStoreError.invalidBundle }
    let start: Int? = row["start_utf16"]
    let end: Int? = row["end_utf16"]
    return Evidence(
        id: try UUID.required(row["id"]),
        subjectKind: subjectKind,
        subjectID: try UUID.required(row["subject_id"]),
        ownerEntityID: try (row["owner_entity_id"] as String?).map(UUID.required),
        sceneID: try UUID.required(row["scene_id"]),
        matchedAliasID: try (row["matched_alias_id"] as String?).map(UUID.required),
        range: start.flatMap { start in end.map { UTF16Range(start: start, end: $0) } },
        quote: row["quote"],
        source: source,
        jobID: try (row["job_id"] as String?).map(UUID.required),
        createdAt: try UTCDate.date(from: row["created_at"])
    )
}

func decodeLock(_ row: Row) throws -> Lock {
    guard let subjectKind = SubjectKind(rawValue: row["subject_kind"]) else {
        throw ProjectStoreError.invalidBundle
    }
    return Lock(
        subjectKind: subjectKind,
        subjectID: try UUID.required(row["subject_id"]),
        field: row["field"],
        lockedAt: try UTCDate.date(from: row["locked_at"])
    )
}

// MARK: - Phase 5a rows (PHASE5_DESIGN §4.3; Plan 018)

func decodeScenePromptSet(_ row: Row) throws -> ScenePromptSet {
    ScenePromptSet(
        id: try UUID.required(row["id"]),
        projectID: try UUID.required(row["project_id"]),
        sceneID: try UUID.required(row["scene_id"]),
        targetProfile: row["target_profile"],
        setNumber: row["set_number"],
        skillID: row["skill_id"],
        skillEntryPath: row["skill_entry_path"],
        skillEntrySHA256: row["skill_entry_sha256"],
        inputDigest: row["input_digest"],
        inputFormatVersion: row["input_format_version"],
        humanEdited: (row["human_edited"] as Int) != 0,
        provenance: try decodeProvenance(row)
    )
}

func decodeScenePromptCard(_ row: Row) throws -> ScenePromptCard {
    ScenePromptCard(
        id: try UUID.required(row["id"]),
        setID: try UUID.required(row["set_id"]),
        order: row["card_order"],
        title: row["title"],
        body: row["body"],
        guidance: row["guidance"],
        durationSeconds: row["duration_seconds"],
        aspectRatio: row["aspect_ratio"],
        resolution: row["resolution"]
    )
}

func decodeScenePromptCardReference(_ row: Row) throws -> ScenePromptCardReference {
    ScenePromptCardReference(
        id: try UUID.required(row["id"]),
        cardID: try UUID.required(row["card_id"]),
        position: row["position"],
        requirementID: try (row["requirement_id"] as String?).map(UUID.required),
        versionID: try (row["version_id"] as String?).map(UUID.required),
        class: try decodeCitationClass(row["class"]),
        role: row["role"],
        exclusion: row["exclusion"],
        fidelity: try decodeCitationFidelity(row["fidelity"]),
        sha256: row["sha256"],
        relativePath: row["relative_path"],
        pixelWidth: row["pixel_width"],
        pixelHeight: row["pixel_height"],
        displayName: row["display_name"],
        source: try decodeCitationSource(row["source"]),
        jobID: try (row["job_id"] as String?).map(UUID.required),
        createdAt: try UTCDate.date(from: row["created_at"])
    )
}

func decodeScenePrompt(_ row: Row) throws -> ScenePrompt {
    ScenePrompt(
        id: try UUID.required(row["id"]),
        projectID: try UUID.required(row["project_id"]),
        sceneID: try UUID.required(row["scene_id"]),
        targetProfile: row["target_profile"],
        promptNumber: row["prompt_number"],
        body: row["body"],
        guidance: row["guidance"],
        durationSeconds: row["duration_seconds"],
        aspectRatio: row["aspect_ratio"],
        resolution: row["resolution"],
        skillID: row["skill_id"],
        skillEntryPath: row["skill_entry_path"],
        skillEntrySHA256: row["skill_entry_sha256"],
        inputDigest: row["input_digest"],
        inputFormatVersion: row["input_format_version"],
        provenance: try decodeProvenance(row)
    )
}

func decodeScenePromptReference(_ row: Row) throws -> ScenePromptReference {
    ScenePromptReference(
        id: try UUID.required(row["id"]),
        promptID: try UUID.required(row["prompt_id"]),
        position: row["position"],
        requirementID: try (row["requirement_id"] as String?).map(UUID.required),
        versionID: try (row["version_id"] as String?).map(UUID.required),
        class: try decodeCitationClass(row["class"]),
        role: row["role"],
        exclusion: row["exclusion"],
        fidelity: try decodeCitationFidelity(row["fidelity"]),
        sha256: row["sha256"],
        displayName: row["display_name"],
        source: try decodeCitationSource(row["source"]),
        jobID: try (row["job_id"] as String?).map(UUID.required),
        createdAt: try UTCDate.date(from: row["created_at"])
    )
}

func decodeImportedSkill(_ row: Row) throws -> ImportedSkill {
    ImportedSkill(
        id: try UUID.required(row["id"]),
        projectID: try UUID.required(row["project_id"]),
        displayName: row["display_name"],
        relativeRoot: row["relative_root"],
        entryRelativePath: row["entry_relative_path"],
        routingRelativePath: row["routing_relative_path"],
        treeSHA256: row["tree_sha256"],
        createdAt: try UTCDate.date(from: row["created_at"])
    )
}

/// The citation enum spellings are shared with their asset siblings — one decoding of
/// each closed CHECK vocabulary.
private func decodeCitationClass(_ raw: String) throws -> ReferenceClass {
    guard let value = ReferenceClass(rawValue: raw) else {
        throw ProjectStoreError.invalidBundle
    }
    return value
}

private func decodeCitationFidelity(_ raw: String) throws -> ReferenceFidelity {
    guard let value = ReferenceFidelity(rawValue: raw) else {
        throw ProjectStoreError.invalidBundle
    }
    return value
}

private func decodeCitationSource(_ raw: String) throws -> FactSource {
    guard let value = FactSource(rawValue: raw) else {
        throw ProjectStoreError.invalidBundle
    }
    return value
}
