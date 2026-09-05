import Foundation
import GRDB

// Where a v4 manifest row becomes a domain value (PHASE2_DESIGN §4.3, §4.4). The Phase 1
// half lives in `RowDecoding.swift`; the split is by schema version, not by concern, so a
// v4 table's decoder is found next to the other v4 tables'.

func decodeAssetRequirementType(_ row: Row) throws -> AssetRequirementType {
    guard let entityKind = EntityKind(rawValue: row["entity_kind"]) else {
        throw ProjectStoreError.invalidBundle
    }
    return AssetRequirementType(
        id: try UUID.required(row["id"]),
        projectID: try UUID.required(row["project_id"]),
        entityKind: entityKind,
        code: row["code"],
        displayName: row["display_name"],
        sortOrder: row["sort_order"],
        isEnabled: (row["is_enabled"] as Int) != 0,
        createdAt: try UTCDate.date(from: row["created_at"]),
        updatedAt: try UTCDate.date(from: row["updated_at"])
    )
}

func decodeAssetRequirement(_ row: Row) throws -> AssetRequirement {
    guard let tier = AssetRequirementTier(rawValue: row["tier"]),
          let necessity = RequirementNecessity(rawValue: row["necessity"])
    else { throw ProjectStoreError.invalidBundle }
    return AssetRequirement(
        id: try UUID.required(row["id"]),
        projectID: try UUID.required(row["project_id"]),
        entityID: try UUID.required(row["entity_id"]),
        tier: tier,
        typeID: try (row["type_id"] as String?).map(UUID.required),
        name: row["name"],
        nameNormalized: row["name_normalized"],
        reason: row["reason"],
        necessity: necessity,
        provenance: try decodeProvenance(row),
        outfitSourceVersionID: row.hasColumn("outfit_source_version_id")
            ? try (row["outfit_source_version_id"] as String?).map(UUID.required) : nil
    )
}

func decodeAssetRequirementScene(_ row: Row) throws -> AssetRequirementScene {
    AssetRequirementScene(
        id: try UUID.required(row["id"]),
        requirementID: try UUID.required(row["requirement_id"]),
        sceneID: try UUID.required(row["scene_id"]),
        provenance: try decodeProvenance(row)
    )
}

func decodeAssetRequirementBasis(_ row: Row) throws -> AssetRequirementBasis {
    guard let subjectKind = SubjectKind(rawValue: row["subject_kind"]),
          AssetRequirementBasis.citableKinds.contains(subjectKind),
          let source = FactSource(rawValue: row["source"])
    else { throw ProjectStoreError.invalidBundle }
    return AssetRequirementBasis(
        id: try UUID.required(row["id"]),
        requirementID: try UUID.required(row["requirement_id"]),
        subjectKind: subjectKind,
        subjectID: try UUID.required(row["subject_id"]),
        source: source,
        jobID: try (row["job_id"] as String?).map(UUID.required),
        createdAt: try UTCDate.date(from: row["created_at"])
    )
}

func decodeAssetDependency(_ row: Row) throws -> AssetDependency {
    AssetDependency(
        id: try UUID.required(row["id"]),
        requirementID: try UUID.required(row["requirement_id"]),
        dependsOnRequirementID: try UUID.required(row["depends_on_requirement_id"]),
        provenance: try decodeProvenance(row)
    )
}

func decodeAsset(_ row: Row) throws -> Asset {
    guard let status = AssetStatus(rawValue: row["status"]) else {
        throw ProjectStoreError.invalidBundle
    }
    return Asset(
        id: try UUID.required(row["id"]),
        projectID: try UUID.required(row["project_id"]),
        requirementID: try UUID.required(row["requirement_id"]),
        status: status,
        isStale: (row["is_stale"] as Int) != 0,
        staleSince: try (row["stale_since"] as String?).map(UTCDate.date),
        staleReason: row["stale_reason"],
        rejectedExplicitly: (row["rejected_explicitly"] as Int) != 0,
        notes: row["notes"],
        provenance: try decodeProvenance(row)
    )
}

func decodeAssetVersion(_ row: Row) throws -> AssetVersion {
    guard let status = AssetVersionStatus(rawValue: row["status"]),
          let mediaKind = MediaKind(rawValue: row["media_kind"])
    else { throw ProjectStoreError.invalidBundle }
    return AssetVersion(
        id: try UUID.required(row["id"]),
        assetID: try UUID.required(row["asset_id"]),
        versionNumber: row["version_number"],
        status: status,
        relativePath: try RelativeProjectPath(row["relative_path"] as String),
        sha256: row["sha256"],
        byteCount: row["byte_count"],
        originalFileName: row["original_file_name"],
        mediaKind: mediaKind,
        pixelWidth: row["pixel_width"],
        pixelHeight: row["pixel_height"],
        notes: row["notes"],
        provenance: try decodeProvenance(row)
    )
}

func decodeAssetPrompt(_ row: Row) throws -> AssetPrompt {
    AssetPrompt(
        id: try UUID.required(row["id"]),
        projectID: try UUID.required(row["project_id"]),
        requirementID: try UUID.required(row["requirement_id"]),
        promptNumber: row["prompt_number"],
        body: row["body"],
        targetModel: row["target_model"],
        guidance: row["guidance"],
        skillID: row["skill_id"],
        skillEntryPath: row["skill_entry_path"],
        skillEntrySHA256: row["skill_entry_sha256"],
        inputDigest: row["input_digest"],
        inputFormatVersion: row["input_format_version"],
        provenance: try decodeProvenance(row)
    )
}

func decodeAssetPromptReference(_ row: Row) throws -> AssetPromptReference {
    guard let referenceClass = ReferenceClass(rawValue: row["class"]),
          let fidelity = ReferenceFidelity(rawValue: row["fidelity"])
    else { throw ProjectStoreError.invalidBundle }
    return AssetPromptReference(
        id: try UUID.required(row["id"]),
        promptID: try UUID.required(row["prompt_id"]),
        position: row["position"],
        requirementID: (row["requirement_id"] as String?).flatMap(UUID.init(uuidString:)),
        versionID: (row["version_id"] as String?).flatMap(UUID.init(uuidString:)),
        class: referenceClass,
        role: row["role"],
        exclusion: row["exclusion"],
        fidelity: fidelity,
        sha256: row["sha256"],
        displayName: row["display_name"],
        source: FactSource(rawValue: row["source"]) ?? .human,
        jobID: (row["job_id"] as String?).flatMap(UUID.init(uuidString:)),
        createdAt: try UTCDate.date(from: row["created_at"] as String)
    )
}
