import Darwin
import Foundation
import GRDB
import os

/// The public media doors of PHASE2_DESIGN §4.1 and §7.3, on `ProjectSession`.
///
/// Three shapes live here and nowhere else:
///
/// * **Staged import.** The `importScreenplay` discipline, exactly: the source is read
///   **once** outside the bundle and never touched; the file is sniffed and measured against
///   `MediaImportLimits` before a byte is staged; the bytes go in through
///   `BundleContainment`; and then **one** transaction performs the whole group — the
///   implicit accept of a proposed requirement, `createAsset` when the slot is empty, and
///   the version insert — as one undo step. Any throw removes the staged file and rethrows.
/// * **Rows first, files second.** `deleteVersion` and `deleteAsset` commit their row
///   removal and unlink afterwards. A failed unlink **logs and orphans**: it never dangles a
///   row, and it never fails the operation the filmmaker already committed to.
/// * **Clear Orphaned Media.** Listed by `orphanedMedia()`, deleted after the caller
///   confirms, serialized through this actor with every other write, touching no rows and
///   journaling nothing — the Clear Job Cache pattern, one door over.
public extension ProjectSession {

    // MARK: - Import (§4.1)

    /// Imports one image into a requirement's slot.
    ///
    /// The whole gate runs before anything is staged: magic-byte sniff, extension agreement,
    /// file size, and the **header-declared** pixel dimensions (§4.1's decompression-bomb
    /// rule). Then the destination is computed through `AssetPathing`, probed for an on-disk
    /// collision through the containment walk — a symlinked component or leaf refuses the
    /// import rather than being side-stepped into a `-2` name — and staged.
    @discardableResult
    func importAssetVersion(
        requirementID: UUID,
        from sourceURL: URL,
        actor: MutationActor = .human,
        promptID: UUID? = nil
    ) throws -> MediaImportSummary {
        try importAssetVersionControlled(
            requirementID: requirementID,
            from: sourceURL,
            actor: actor,
            promptID: promptID,
            approveImmediately: false
        )
    }

    /// The reference-sheet gesture: the imported bytes become the approved/current
    /// version in the same transaction and journal group as the import.
    @discardableResult
    func importAndApproveAssetVersion(
        requirementID: UUID,
        from sourceURL: URL,
        actor: MutationActor = .human,
        promptID: UUID? = nil
    ) throws -> MediaImportSummary {
        try importAssetVersionControlled(
            requirementID: requirementID,
            from: sourceURL,
            actor: actor,
            promptID: promptID,
            approveImmediately: true
        )
    }

    /// Imports a new scene-specific image reference and links it to the scene in one
    /// controlled mutation. The human supplies the semantic name because it becomes the
    /// reference's prompt role (for example, "Main Screen — RustCorp Helicopter Feed").
    ///
    /// The entity, variant requirement, scene link, asset, imported version, and approval
    /// are one journal entry and one undo step. The source is subject to the same media
    /// budget, magic-byte inspection, containment, and staged-file cleanup as every other
    /// image import.
    @discardableResult
    func importSceneImageReference(
        sceneID: UUID,
        name: String,
        from sourceURL: URL,
        actor: MutationActor = .human
    ) throws -> SceneImageReferenceImportSummary {
        guard let database else { throw ProjectStoreError.sessionClosed }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else {
            throw ProjectStoreError.invalidName(reason: "A name cannot be empty.")
        }

        let fileName = sourceURL.lastPathComponent
        let declaredSize = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path))?[
            .size
        ] as? Int
        if let declaredSize {
            try MediaImportLimits.check(byteCount: declaredSize, fileName: fileName)
        }
        let data = try Data(contentsOf: sourceURL)
        let facts = try AssetPathing.inspectForImport(data, fileName: fileName)
        let sha256 = data.sha256Hex

        let entityID = UUID()
        let requirementID = UUID()
        let linkID = UUID()
        let assetID = UUID()
        let versionID = UUID()
        let normalizedName = EntityNormalization.normalize(trimmedName)
        let plan = ImportPlan(
            entityKind: .object,
            entityNameNormalized: normalizedName,
            requirementNameNormalized: normalizedName,
            reviewState: .accepted,
            isActive: true,
            assetID: nil,
            nextVersionNumber: 1
        )
        let containment = mediaContainment
        let repository = ProjectRepository(database: database)
        let relativePath = try Self.stagedDestination(
            plan: plan,
            versionNumber: 1,
            fileExtension: (fileName as NSString).pathExtension.lowercased(),
            referenced: try repository.referencedMediaPaths(),
            in: containment
        )
        try containment.write(data, to: relativePath)

        do {
            let entry = try database.queue.write { db -> JournalEntry in
                let children: [EditOperation] = [
                    .createEntity(
                        id: entityID,
                        kind: .object,
                        name: trimmedName,
                        description: "Scene-specific visual reference."
                    ),
                    .createRequirement(
                        id: requirementID,
                        entityID: entityID,
                        tier: .variant,
                        typeID: nil,
                        name: trimmedName,
                        reason: "Uploaded for this scene's generation prompt."
                    ),
                    .addRequirementScene(
                        requirementID: requirementID,
                        sceneID: sceneID,
                        linkID: linkID,
                        restoring: []
                    ),
                    .createAsset(id: assetID, requirementID: requirementID, restoring: []),
                    .importAssetVersion(
                        versionID: versionID,
                        assetID: assetID,
                        versionNumber: 1,
                        relativePath: relativePath,
                        sha256: sha256,
                        byteCount: facts.byteCount,
                        originalFileName: fileName,
                        mediaKind: .image,
                        pixelWidth: facts.pixelWidth,
                        pixelHeight: facts.pixelHeight,
                        promptID: nil,
                        restoring: []
                    ),
                    .approveVersion(assetID: assetID, versionID: versionID),
                ]
                let entry = try EditPrimitives.performGroup(
                    children,
                    as: .batch(children),
                    actor: actor,
                    jobID: actor.jobID,
                    media: containment,
                    in: db
                )
                return entry
            }
            return SceneImageReferenceImportSummary(
                entityID: entityID,
                requirementID: requirementID,
                media: MediaImportSummary(
                    entry: entry,
                    assetID: assetID,
                    versionID: versionID,
                    versionNumber: 1,
                    relativePath: relativePath,
                    sha256: sha256,
                    byteCount: facts.byteCount,
                    format: facts.format,
                    pixelWidth: facts.pixelWidth,
                    pixelHeight: facts.pixelHeight
                )
            )
        } catch {
            _ = try? containment.removeIfPresent(at: relativePath)
            throw error
        }
    }

    /// Imports a complete generated candidate set as one controlled change.
    ///
    /// All 1–4 source files are inspected and staged before the database transaction opens.
    /// Each insert re-verifies its staged file inside that transaction; one failure rolls
    /// back every row and removes every staged file.
    @discardableResult
    func importGeneratedCandidates(
        requirementID: UUID,
        from sourceURLs: [URL],
        selectedIndex: Int,
        context: ReferenceImageGenerationContext,
        metadata: ImageGenerationCommitMetadata,
        actor: MutationActor = .human
    ) throws -> GeneratedCandidateImportSummary {
        try Task.checkCancellation()
        guard let database else { throw ProjectStoreError.sessionClosed }
        guard context.requirementID == requirementID else {
            throw ProjectStoreError.referenceImageGenerationContextChanged
        }
        if let refusal = context.refusalReason {
            throw ProjectStoreError.assetOperationRefused(reason: refusal)
        }
        guard (1...4).contains(sourceURLs.count) else {
            throw ProjectStoreError.assetOperationRefused(
                reason: "Choose between one and four generated images."
            )
        }
        guard sourceURLs.indices.contains(selectedIndex) else {
            throw ProjectStoreError.assetOperationRefused(
                reason: "Choose one generated image to make current."
            )
        }
        try Self.validateGenerationMetadata(
            metadata,
            sourceCount: sourceURLs.count,
            selectedIndex: selectedIndex
        )
        if let amendment = metadata.visualAmendment {
            guard context.includesCurrentImage,
                  amendment.scope != .characterBundle
                    || (context.entityKind == .character && context.tier == .canonical)
            else {
                throw ProjectStoreError.assetOperationRefused(
                    reason: "That visual amendment does not match this image-edit run."
                )
            }
        }
        try Self.validateGenerationAttachments(metadata.attachments)

        let containment = mediaContainment
        let repository = ProjectRepository(database: database)
        let plan = try database.queue.read { db -> ImportPlan in
            let value = try Self.plan(requirementID: requirementID, in: db)
            let current = try ProjectRepository.referenceImageGenerationContext(
                requirementID: requirementID,
                generationPromptBodySHA256: context.promptBodySHA256,
                includeCurrentImage: context.includesCurrentImage,
                in: db
            )
            guard current == context else {
                throw ProjectStoreError.referenceImageGenerationContextChanged
            }
            return value
        }
        guard plan.isActive else {
            throw ProjectStoreError.requirementInactive(requirementID: requirementID)
        }
        for dependency in context.orderedDependencies {
            try AssetOperations.verifyMedia(
                at: dependency.relativePath,
                sha256: dependency.sha256,
                byteCount: dependency.byteCount,
                using: containment
            )
        }

        var referenced = try repository.referencedMediaPaths()
        var staged: [StagedCandidate] = []
        do {
            for (offset, sourceURL) in sourceURLs.enumerated() {
                let fileName = sourceURL.lastPathComponent
                let declaredSize = (try? FileManager.default.attributesOfItem(
                    atPath: sourceURL.path
                ))?[.size] as? Int
                if let declaredSize {
                    try MediaImportLimits.check(byteCount: declaredSize, fileName: fileName)
                }
                let data = try Data(contentsOf: sourceURL)
                let facts = try AssetPathing.inspectForImport(data, fileName: fileName)
                let relativePath = try Self.stagedDestination(
                    plan: plan,
                    versionNumber: plan.nextVersionNumber + offset,
                    fileExtension: (fileName as NSString).pathExtension.lowercased(),
                    referenced: referenced,
                    in: containment
                )
                try containment.write(data, to: relativePath)
                referenced.insert(relativePath.rawValue)
                staged.append(
                    StagedCandidate(
                        versionID: UUID(),
                        versionNumber: plan.nextVersionNumber + offset,
                        relativePath: relativePath,
                        sha256: data.sha256Hex,
                        originalFileName: fileName,
                        facts: facts
                    )
                )
            }
            try Task.checkCancellation()
        } catch {
            for candidate in staged {
                _ = try? containment.removeIfPresent(at: candidate.relativePath)
            }
            throw error
        }

        let assetID = plan.assetID ?? UUID()
        do {
            let entry = try database.queue.write { db -> JournalEntry in
                guard Task.isCancelled == false else { throw CancellationError() }
                let current = try ProjectRepository.referenceImageGenerationContext(
                    requirementID: requirementID,
                    generationPromptBodySHA256: context.promptBodySHA256,
                    includeCurrentImage: context.includesCurrentImage,
                    in: db
                )
                guard current == context, current.refusalReason == nil else {
                    throw ProjectStoreError.referenceImageGenerationContextChanged
                }
                for dependency in context.orderedDependencies {
                    try AssetOperations.verifyMedia(
                        at: dependency.relativePath,
                        sha256: dependency.sha256,
                        byteCount: dependency.byteCount,
                        using: containment
                    )
                }
                let timestamp = UTCDate.string(from: Date())
                try db.execute(sql: """
                    INSERT INTO image_generation_runs (
                        id, requirement_id, prompt_id, provider_id, model_id,
                        helper_protocol_version, prompt_body_sha256, aspect_ratio,
                        requested_width, requested_height, resolution_label,
                        candidate_count, selected_candidate_index, created_at,
                        visual_amendment, visual_amendment_scope
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '1K', ?, ?, ?, ?, ?)
                    """, arguments: [
                        metadata.runID.uuidString, requirementID.uuidString,
                        context.promptID.uuidString, metadata.providerID, metadata.modelID,
                        metadata.helperProtocolVersion, context.promptBodySHA256,
                        metadata.aspectRatio, metadata.requestedWidth,
                        metadata.requestedHeight, metadata.candidateCount,
                        metadata.selectedCandidateIndex, timestamp,
                        metadata.visualAmendment?.instruction,
                        metadata.visualAmendment?.scope.rawValue,
                    ])
                for (offset, dependency) in context.orderedDependencies.enumerated() {
                    try db.execute(sql: """
                        INSERT INTO image_generation_references (
                            run_id, position, requirement_id, version_id, sha256,
                            byte_count, entity_kind
                        ) VALUES (?, ?, ?, ?, ?, ?, ?)
                        """, arguments: [
                            metadata.runID.uuidString, offset + 1,
                            dependency.requirementID.uuidString,
                            dependency.versionID.uuidString, dependency.sha256,
                            dependency.byteCount, dependency.entityKind.rawValue,
                        ])
                }
                for (offset, attachment) in metadata.attachments.enumerated() {
                    try db.execute(sql: """
                        INSERT INTO image_generation_references (
                            run_id, position, requirement_id, version_id, sha256,
                            byte_count, entity_kind
                        ) VALUES (?, ?, NULL, NULL, ?, ?, ?)
                        """, arguments: [
                            metadata.runID.uuidString,
                            context.orderedDependencies.count + offset + 1,
                            attachment.sha256, attachment.byteCount,
                            attachment.entityKind.rawValue,
                        ])
                }
                for (offset, amendment) in context.activeVisualAmendments.enumerated() {
                    try db.execute(sql: """
                        INSERT INTO image_generation_amendments (
                            run_id, position, amendment_run_id, requirement_id,
                            version_id, instruction, scope, created_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """, arguments: [
                            metadata.runID.uuidString, offset + 1,
                            amendment.runID.uuidString,
                            amendment.requirementID.uuidString,
                            amendment.versionID.uuidString,
                            amendment.instruction,
                            amendment.scope.rawValue,
                            UTCDate.string(from: amendment.createdAt),
                        ])
                }
                let assetExists = try AssetOperations.asset(
                    ofRequirement: requirementID, in: db
                ) != nil
                let nextNumber = assetExists
                    ? try AssetOperations.nextVersionNumber(assetID: assetID, in: db)
                    : 1
                guard nextNumber == plan.nextVersionNumber else {
                    throw ProjectStoreError.assetOperationRefused(
                        reason: "Another image was added while these were being copied. Try again."
                    )
                }

                var children: [EditOperation] = []
                if plan.reviewState == .proposed {
                    let refs = try ReviewOperations.expand(
                        refs: [SubjectRef(kind: .requirement, id: requirementID)], in: db
                    )
                    children += refs.map { EditOperation.acceptFact($0) }
                }
                if !assetExists {
                    children.append(
                        .createAsset(id: assetID, requirementID: requirementID, restoring: [])
                    )
                }
                children += staged.map { candidate in
                    .importAssetVersion(
                        versionID: candidate.versionID,
                        assetID: assetID,
                        versionNumber: candidate.versionNumber,
                        relativePath: candidate.relativePath,
                        sha256: candidate.sha256,
                        byteCount: candidate.facts.byteCount,
                        originalFileName: candidate.originalFileName,
                        mediaKind: .image,
                        pixelWidth: candidate.facts.pixelWidth,
                        pixelHeight: candidate.facts.pixelHeight,
                        promptID: context.promptID,
                        restoring: []
                    )
                }
                children.append(
                    .approveVersion(
                        assetID: assetID,
                        versionID: staged[selectedIndex].versionID
                    )
                )
                if metadata.visualAmendment?.scope == .characterBundle {
                    let siblingRows = try Row.fetchAll(
                        db,
                        sql: """
                            SELECT sibling_asset.id AS asset_id, source.name AS source_name
                            FROM asset_requirements source
                            JOIN asset_requirements sibling
                              ON sibling.entity_id = source.entity_id
                             AND sibling.id <> source.id
                             AND sibling.tier = 'canonical'
                             AND sibling.necessity <> 'not_needed'
                            JOIN assets sibling_asset
                              ON sibling_asset.requirement_id = sibling.id
                            WHERE source.id = ?
                              AND EXISTS (
                                  SELECT 1 FROM asset_versions version
                                  WHERE version.asset_id = sibling_asset.id
                                    AND version.status = 'approved'
                              )
                            ORDER BY sibling.id
                            """,
                        arguments: [requirementID.uuidString]
                    )
                    for sibling in siblingRows {
                        children.append(.markAssetStale(
                            assetID: try UUID.required(sibling["asset_id"]),
                            reason: AssetOperations.staleReason(
                                dependencyName: sibling["source_name"]
                            )
                        ))
                    }
                }
                let entry = try EditPrimitives.performGroup(
                    children,
                    as: .batch(children),
                    actor: actor,
                    jobID: actor.jobID,
                    media: containment,
                    in: db
                )
                for (offset, candidate) in staged.enumerated() {
                    try db.execute(sql: """
                        UPDATE asset_versions
                        SET image_generation_run_id = ?, generation_candidate_index = ?
                        WHERE id = ?
                        """, arguments: [
                            metadata.runID.uuidString, offset, candidate.versionID.uuidString,
                        ])
                }
                return entry
            }
            return GeneratedCandidateImportSummary(
                entry: entry,
                assetID: assetID,
                promptID: context.promptID,
                selectedVersionID: staged[selectedIndex].versionID,
                candidates: staged.enumerated().map { index, candidate in
                    GeneratedCandidateImport(
                        id: candidate.versionID,
                        versionNumber: candidate.versionNumber,
                        relativePath: candidate.relativePath,
                        sha256: candidate.sha256,
                        byteCount: candidate.facts.byteCount,
                        format: candidate.facts.format,
                        pixelWidth: candidate.facts.pixelWidth,
                        pixelHeight: candidate.facts.pixelHeight,
                        isCurrent: index == selectedIndex
                    )
                }
            )
        } catch {
            for candidate in staged {
                _ = try? containment.removeIfPresent(at: candidate.relativePath)
            }
            throw error
        }
    }

    func imageGenerationProvenance(
        versionID: UUID
    ) throws -> ImageGenerationProvenance? {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT r.*, v.generation_candidate_index
                FROM asset_versions v
                JOIN image_generation_runs r ON r.id = v.image_generation_run_id
                WHERE v.id = ?
                """, arguments: [versionID.uuidString]) else { return nil }
            let runID = try UUID.required(row["id"])
            let references = try Row.fetchAll(db, sql: """
                SELECT * FROM image_generation_references
                WHERE run_id = ? ORDER BY position
                """, arguments: [runID.uuidString]).map { reference in
                    guard let kind = EntityKind(rawValue: reference["entity_kind"]) else {
                        throw ProjectStoreError.invalidBundle
                    }
                    return ImageGenerationReferenceProvenance(
                        position: reference["position"],
                        requirementID: try (reference["requirement_id"] as String?).map(UUID.required),
                        versionID: try (reference["version_id"] as String?).map(UUID.required),
                        sha256: reference["sha256"],
                        byteCount: reference["byte_count"],
                        entityKind: kind
                    )
                }
            let amendments = try Row.fetchAll(db, sql: """
                SELECT * FROM image_generation_amendments
                WHERE run_id = ? ORDER BY position
                """, arguments: [runID.uuidString]).map { amendment in
                    guard let scope = VisualAmendmentScope(rawValue: amendment["scope"])
                    else { throw ProjectStoreError.invalidBundle }
                    return ReferenceVisualAmendment(
                        runID: try UUID.required(amendment["amendment_run_id"]),
                        requirementID: try UUID.required(amendment["requirement_id"]),
                        versionID: try UUID.required(amendment["version_id"]),
                        instruction: amendment["instruction"],
                        scope: scope,
                        createdAt: try UTCDate.date(from: amendment["created_at"])
                    )
                }
            return ImageGenerationProvenance(
                id: runID,
                requirementID: try UUID.required(row["requirement_id"]),
                promptID: try (row["prompt_id"] as String?).map(UUID.required),
                providerID: row["provider_id"],
                modelID: row["model_id"],
                helperProtocolVersion: row["helper_protocol_version"],
                promptBodySHA256: row["prompt_body_sha256"],
                aspectRatio: row["aspect_ratio"],
                requestedWidth: row["requested_width"],
                requestedHeight: row["requested_height"],
                candidateCount: row["candidate_count"],
                selectedCandidateIndex: row["selected_candidate_index"],
                candidateIndex: row["generation_candidate_index"],
                createdAt: try UTCDate.date(from: row["created_at"]),
                references: references,
                visualAmendment: try Self.decodeVisualAmendment(row),
                appliedVisualAmendments: amendments
            )
        }
    }

    private static func decodeVisualAmendment(
        _ row: Row
    ) throws -> ImageGenerationVisualAmendment? {
        guard let instruction: String = row["visual_amendment"] else { return nil }
        guard let scope = VisualAmendmentScope(
            rawValue: row["visual_amendment_scope"]
        ) else { throw ProjectStoreError.invalidBundle }
        return ImageGenerationVisualAmendment(instruction: instruction, scope: scope)
    }

    private static func validateGenerationMetadata(
        _ metadata: ImageGenerationCommitMetadata,
        sourceCount: Int,
        selectedIndex: Int
    ) throws {
        func validIdentifier(_ value: String) -> Bool {
            !value.isEmpty && value.utf8.count <= 128 && value.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.union(
                    CharacterSet(charactersIn: "-._")
                ).contains($0)
            }
        }
        let expectedRatio: Double? = switch metadata.aspectRatio {
        case "2:3": 2.0 / 3.0
        case "16:9": 16.0 / 9.0
        case "1:1": 1.0
        default: nil
        }
        let actualRatio = Double(metadata.requestedWidth) / Double(metadata.requestedHeight)
        guard validIdentifier(metadata.providerID), validIdentifier(metadata.modelID),
              metadata.helperProtocolVersion >= 1,
              let expectedRatio,
              abs(actualRatio - expectedRatio) / expectedRatio <= 0.03,
              metadata.requestedWidth > 0, metadata.requestedWidth <= 3_840,
              metadata.requestedHeight > 0, metadata.requestedHeight <= 3_840,
              metadata.candidateCount == sourceCount,
              metadata.selectedCandidateIndex == selectedIndex
        else {
            throw ProjectStoreError.assetOperationRefused(
                reason: "The image provider returned inconsistent generation metadata."
            )
        }
        if let amendment = metadata.visualAmendment {
            guard amendment.instruction.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty == false,
                amendment.instruction.lengthOfBytes(using: .utf8) <= 65_536
            else {
                throw ProjectStoreError.assetOperationRefused(
                    reason: "Keep the visual edit instruction under 65,536 UTF-8 bytes."
                )
            }
        }
    }

    private static func validateGenerationAttachments(
        _ attachments: [ReferenceImageGenerationAttachment]
    ) throws {
        guard attachments.count <= 1 else {
            throw ProjectStoreError.assetOperationRefused(
                reason: "Attach at most one additional reference image."
            )
        }
        for attachment in attachments {
            guard attachment.byteCount == attachment.data.count,
                  attachment.sha256 == attachment.data.sha256Hex
            else {
                throw ProjectStoreError.assetOperationRefused(
                    reason: "The attached reference image changed before import."
                )
            }
            _ = try AssetPathing.inspectForImport(
                attachment.data,
                fileName: attachment.originalFileName
            )
        }
    }

    private func importAssetVersionControlled(
        requirementID: UUID,
        from sourceURL: URL,
        actor: MutationActor,
        promptID: UUID?,
        approveImmediately: Bool
    ) throws -> MediaImportSummary {
        guard let database else { throw ProjectStoreError.sessionClosed }
        let repository = ProjectRepository(database: database)
        let containment = mediaContainment
        let fileName = sourceURL.lastPathComponent

        // §4.1: refuse an over-budget file before reading all of it into memory.
        let declaredSize = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path))?[
            .size
        ] as? Int
        if let declaredSize {
            try MediaImportLimits.check(byteCount: declaredSize, fileName: fileName)
        }
        // Read **once**, outside the bundle, and never mutate the source.
        let data = try Data(contentsOf: sourceURL)
        let facts = try AssetPathing.inspectForImport(data, fileName: fileName)
        let sha256 = data.sha256Hex

        // Everything the destination needs, read before staging. Writes are serialized
        // through this actor, so nothing can move between this read and the transaction —
        // and the transaction re-derives `version_number` and refuses a disagreement rather
        // than trusting what it planned.
        let plan = try database.queue.read { db -> ImportPlan in
            try Self.plan(requirementID: requirementID, in: db)
        }
        guard plan.isActive else {
            throw ProjectStoreError.requirementInactive(requirementID: requirementID)
        }

        let referenced = try repository.referencedMediaPaths()
        let fileExtension = (fileName as NSString).pathExtension.lowercased()
        let relativePath = try Self.stagedDestination(
            plan: plan,
            versionNumber: plan.nextVersionNumber,
            fileExtension: fileExtension,
            referenced: referenced,
            in: containment
        )
        try containment.write(data, to: relativePath)

        let versionID = UUID()
        let assetID = plan.assetID ?? UUID()
        do {
            let entry = try database.queue.write { db -> JournalEntry in
                // §4.1: `version_number` is max + 1 **inside the import transaction**.
                let assetExists = try AssetOperations.asset(
                    ofRequirement: requirementID, in: db
                ) != nil
                let number = assetExists
                    ? try AssetOperations.nextVersionNumber(assetID: assetID, in: db)
                    : 1
                guard number == plan.nextVersionNumber else {
                    throw ProjectStoreError.assetOperationRefused(
                        reason: "Another image was added while this one was being copied. Try again."
                    )
                }

                var children: [EditOperation] = []
                // §7.3: import is the strongest possible accept gesture, so a proposed
                // requirement is accepted implicitly **in the same group** — through the
                // Phase 1 review operation, expanded exactly as `acceptFacts` expands it.
                if plan.reviewState == .proposed {
                    let refs = try ReviewOperations.expand(
                        refs: [SubjectRef(kind: .requirement, id: requirementID)], in: db
                    )
                    children += refs.map { EditOperation.acceptFact($0) }
                }
                if !assetExists {
                    children.append(
                        .createAsset(id: assetID, requirementID: requirementID, restoring: [])
                    )
                }
                children.append(
                    .importAssetVersion(
                        versionID: versionID,
                        assetID: assetID,
                        versionNumber: number,
                        relativePath: relativePath,
                        sha256: sha256,
                        byteCount: facts.byteCount,
                        originalFileName: fileName,
                        mediaKind: .image,
                        pixelWidth: facts.pixelWidth,
                        pixelHeight: facts.pixelHeight,
                        // §7.3: the workshop's Import Result and drop (Plan 015) pass the
                        // current prompt's id; every other call site passes nil. The stamp
                        // is the caller's claim of lineage, never inferred from data.
                        promptID: promptID,
                        restoring: []
                    )
                )
                if approveImmediately {
                    children.append(
                        .approveVersion(assetID: assetID, versionID: versionID)
                    )
                }
                let entry = try EditPrimitives.performGroup(
                    children,
                    as: .batch(children),
                    actor: actor,
                    jobID: actor.jobID,
                    media: containment,
                    in: db
                )
                return entry
            }
            return MediaImportSummary(
                entry: entry,
                assetID: assetID,
                versionID: versionID,
                promptID: promptID,
                versionNumber: plan.nextVersionNumber,
                relativePath: relativePath,
                sha256: sha256,
                byteCount: facts.byteCount,
                format: facts.format,
                pixelWidth: facts.pixelWidth,
                pixelHeight: facts.pixelHeight
            )
        } catch {
            // A filesystem copy and a database write cannot share a transaction, so the
            // staged file is removed by hand — descriptor-relative, `unlinkat`, never
            // through a link (§4.1).
            _ = try? containment.removeIfPresent(at: relativePath)
            throw error
        }
    }

    // MARK: - Rows first, files second (§4.1)

    /// §7.3's `deleteVersion`: allowed only on a `rejected` version, **non-invertible**.
    @discardableResult
    func deleteVersion(versionID: UUID, actor: MutationActor = .human) throws -> JournalEntry {
        try performDestructive(.deleteVersion(versionID: versionID), actor: actor)
    }

    @discardableResult
    func deleteArchivedVersion(
        versionID: UUID,
        actor: MutationActor = .human
    ) throws -> JournalEntry {
        try performDestructive(.deleteArchivedVersion(versionID: versionID), actor: actor)
    }

    /// §7.3's `deleteAsset`: the row, its versions, and their files. **Non-invertible**.
    @discardableResult
    func deleteAsset(assetID: UUID, actor: MutationActor = .human) throws -> JournalEntry {
        try performDestructive(.deleteAsset(id: assetID), actor: actor)
    }

    // MARK: - The rest of §7.3

    @discardableResult
    func rejectVersion(versionID: UUID, actor: MutationActor = .human) throws -> JournalEntry {
        try performMedia(.rejectVersion(versionID: versionID), actor: actor)
    }

    @discardableResult
    func unrejectVersion(versionID: UUID, actor: MutationActor = .human) throws -> JournalEntry {
        try performMedia(.unrejectVersion(versionID: versionID), actor: actor)
    }

    /// §7.3's `approveVersion`: one transaction, demote-first, the asset's own staleness
    /// cleared, and §3.5's fan-out when the approved version changed.
    @discardableResult
    func approveVersion(
        assetID: UUID,
        versionID: UUID,
        actor: MutationActor = .human
    ) throws -> JournalEntry {
        try performMedia(.approveVersion(assetID: assetID, versionID: versionID), actor: actor)
    }

    @discardableResult
    func archiveCurrentVersion(
        requirementID: UUID,
        actor: MutationActor = .human
    ) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        let pair = try database.queue.read { db -> (UUID, UUID) in
            guard let asset = try AssetOperations.asset(ofRequirement: requirementID, in: db)
            else { throw ProjectStoreError.assetNotFound }
            guard let versionID = try AssetOperations.approvedVersionID(assetID: asset.id, in: db)
            else {
                throw ProjectStoreError.assetOperationRefused(
                    reason: "This reference has no current image to archive."
                )
            }
            return (asset.id, versionID)
        }
        return try performMedia(
            .archiveCurrentVersion(assetID: pair.0, versionID: pair.1),
            actor: actor
        )
    }

    /// §3.5's explicit "Mark Current". Refused when the asset is not stale.
    @discardableResult
    func clearAssetStale(assetID: UUID, actor: MutationActor = .human) throws -> JournalEntry {
        try performMedia(.clearAssetStale(assetID: assetID), actor: actor)
    }

    @discardableResult
    func rejectAsset(assetID: UUID, actor: MutationActor = .human) throws -> JournalEntry {
        try performMedia(.rejectAsset(assetID: assetID), actor: actor)
    }

    @discardableResult
    func unrejectAsset(assetID: UUID, actor: MutationActor = .human) throws -> JournalEntry {
        try performMedia(.unrejectAsset(assetID: assetID), actor: actor)
    }

    @discardableResult
    func setAssetNotes(id: UUID, text: String, actor: MutationActor = .human) throws -> JournalEntry {
        try performMedia(.setAssetNotes(id: id, text: text), actor: actor)
    }

    @discardableResult
    func setVersionNotes(id: UUID, text: String, actor: MutationActor = .human) throws -> JournalEntry {
        try performMedia(.setVersionNotes(id: id, text: text), actor: actor)
    }

    // MARK: - Clear Orphaned Media (§4.1)

    /// Deletes the orphaned files the caller confirmed.
    ///
    /// The list comes from `orphanedMedia()` and the **confirmation is the caller's** — the
    /// Clear Job Cache shape, with the extra step §4.1 asks for. Every path is re-checked
    /// against the version rows inside this call, so a file that stopped being an orphan
    /// between the listing and the confirmation is left alone; nothing is journaled, and no
    /// row is touched. Non-invertible by construction: it writes nothing to undo.
    @discardableResult
    func clearOrphanedMedia(
        confirming paths: [RelativeProjectPath]
    ) throws -> ClearedCacheSummary {
        guard let database else { throw ProjectStoreError.sessionClosed }
        let referenced = try ProjectRepository(database: database).referencedMediaPaths()
        let containment = mediaContainment
        var bytes: Int64 = 0
        var removed = 0
        for path in paths {
            guard !referenced.contains(path.rawValue) else { continue }
            guard path.rawValue.hasPrefix("assets/") else { continue }
            let size = (try? containment.withReadDescriptor(at: path) { descriptor -> Int64 in
                var status = stat()
                guard fstat(descriptor, &status) == 0 else { return 0 }
                return Int64(status.st_size)
            }) ?? 0
            if try containment.removeIfPresent(at: path) {
                bytes += size
                removed += 1
            }
        }
        return ClearedCacheSummary(bytesFreed: bytes, filesRemoved: removed)
    }
}

// MARK: - Internals

private extension ProjectSession {
    /// Everything the destination and the group need, read before the bytes are staged.
    struct ImportPlan {
        let entityKind: EntityKind
        let entityNameNormalized: String
        let requirementNameNormalized: String
        let reviewState: ReviewState
        let isActive: Bool
        let assetID: UUID?
        let nextVersionNumber: Int
    }

    struct StagedCandidate {
        let versionID: UUID
        let versionNumber: Int
        let relativePath: RelativeProjectPath
        let sha256: String
        let originalFileName: String
        let facts: AssetPathing.MediaFacts
    }

    static func plan(requirementID: UUID, in db: Database) throws -> ImportPlan {
        guard let row = try Row.fetchOne(
            db,
            sql: """
                SELECT r.name_normalized AS r_name, r.review_state AS r_state,
                       e.kind AS e_kind, e.name_normalized AS e_name
                FROM asset_requirements r
                JOIN entities e ON e.id = r.entity_id
                WHERE r.id = ?
                """,
            arguments: [requirementID.uuidString]
        ) else { throw ProjectStoreError.requirementNotFound }
        guard let kind = EntityKind(rawValue: row["e_kind"]),
              let reviewState = ReviewState(rawValue: row["r_state"])
        else { throw ProjectStoreError.invalidBundle }

        let asset = try AssetOperations.asset(ofRequirement: requirementID, in: db)
        return ImportPlan(
            entityKind: kind,
            entityNameNormalized: row["e_name"],
            requirementNameNormalized: row["r_name"],
            reviewState: reviewState,
            isActive: try AssetOperations.isActive(requirementID: requirementID, in: db),
            assetID: asset?.id,
            nextVersionNumber: asset.map { asset in
                (try? AssetOperations.nextVersionNumber(assetID: asset.id, in: db)) ?? 1
            } ?? 1
        )
    }

    /// §4.1's destination plus its collision rule: `v3.png`, then `v3-2.png`, `v3-3.png`.
    ///
    /// The probe is the containment walk, not `FileManager` — a symlinked directory or a
    /// symlinked candidate leaf **throws** here rather than being side-stepped into a `-2`
    /// name, so the import refuses the planted link. A path some version row already claims
    /// is skipped too: `UNIQUE(relative_path)` would otherwise surface as a raw constraint
    /// failure after the bytes were already staged.
    static func stagedDestination(
        plan: ImportPlan,
        versionNumber: Int,
        fileExtension: String,
        referenced: Set<String>,
        in containment: BundleContainment
    ) throws -> RelativeProjectPath {
        var index = 1
        while true {
            let candidate = try AssetPathing.destination(
                entityKind: plan.entityKind,
                entityNameNormalized: plan.entityNameNormalized,
                requirementNameNormalized: plan.requirementNameNormalized,
                versionNumber: versionNumber,
                fileExtension: fileExtension,
                collisionIndex: index
            )
            let free = try containment.entryKind(at: candidate) == .missing
                && !referenced.contains(candidate.rawValue)
            if free { return candidate }
            index += 1
        }
    }

    /// The shared shape of the invertible §7.3 wrappers.
    func performMedia(_ op: EditOperation, actor: MutationActor) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        let containment = mediaContainment
        return try database.queue.write { db in
            try EditPrimitives.perform(
                op, actor: actor, jobID: actor.jobID, media: containment, in: db
            )
        }
    }

    /// §4.1's rows-first deletion: commit the rows, then unlink.
    ///
    /// A file-removal failure is logged and the file orphaned. The row is already gone and
    /// the operation already succeeded — turning a stubborn `unlink` into a thrown error
    /// would tell the filmmaker a delete failed that in fact happened.
    func performDestructive(_ op: EditOperation, actor: MutationActor) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        let containment = mediaContainment
        let outcome = try database.queue.write { db in
            try EditPrimitives.performDetailed(
                op, actor: actor, jobID: actor.jobID, media: containment, in: db
            )
        }
        for path in outcome.effect.removedMediaPaths {
            do {
                try containment.removeIfPresent(at: path)
            } catch {
                Self.mediaLog.error(
                    """
                    Removing \(path.rawValue, privacy: .public) after its row was deleted \
                    failed; the file is now orphaned and Clear Orphaned Media can sweep it.
                    """
                )
            }
        }
        return outcome.entry
    }

    static let mediaLog = Logger(subsystem: "com.aifilmcamp.FilmCore", category: "media")
}

/// What one media import produced (§4.1's measured facts plus the journal entry).
public struct MediaImportSummary: Equatable, Sendable {
    public let entry: JournalEntry
    public let assetID: UUID
    public let versionID: UUID
    /// §7.3's lineage stamp, when the caller passed one — "from prompt 3" (§5.6).
    public let promptID: UUID?
    public let versionNumber: Int
    public let relativePath: RelativeProjectPath
    public let sha256: String
    public let byteCount: Int
    public let format: ImageFormat
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(
        entry: JournalEntry,
        assetID: UUID,
        versionID: UUID,
        promptID: UUID? = nil,
        versionNumber: Int,
        relativePath: RelativeProjectPath,
        sha256: String,
        byteCount: Int,
        format: ImageFormat,
        pixelWidth: Int,
        pixelHeight: Int
    ) {
        self.entry = entry
        self.assetID = assetID
        self.versionID = versionID
        self.promptID = promptID
        self.versionNumber = versionNumber
        self.relativePath = relativePath
        self.sha256 = sha256
        self.byteCount = byteCount
        self.format = format
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// The identifiers and media facts produced by a direct scene-reference upload.
public struct SceneImageReferenceImportSummary: Equatable, Sendable {
    public let entityID: UUID
    public let requirementID: UUID
    public let media: MediaImportSummary

    public var entry: JournalEntry { media.entry }

    public init(entityID: UUID, requirementID: UUID, media: MediaImportSummary) {
        self.entityID = entityID
        self.requirementID = requirementID
        self.media = media
    }
}
