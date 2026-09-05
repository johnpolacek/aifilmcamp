import FilmCore
import SwiftUI

/// §3.11's scene detail: selectable scene text with a scene-local screenplay editor,
/// the **editable** synopsis (`SceneSynopsisEditor`, over `setSynopsis`),
/// the entities by role with the editor that adds and removes them, and the states active
/// in the scene.
///
struct SceneDetailView: View {
    @Bindable var model: ProjectWindowModel
    @State private var isEditingScreenplay = false

    var body: some View {
        Group {
            if model.selection(in: .scenes).count > 1 {
                // Multi-selection shows a count and no actions (§3.11).
                ContentUnavailableView(
                    "\(model.selection(in: .scenes).count) selected",
                    systemImage: ProjectSection.scenes.systemImage
                )
            } else if let detail = model.sceneDetail {
                ScrollView { content(detail) }
            } else {
                ContentUnavailableView("No Selection", systemImage: ProjectSection.scenes.systemImage)
            }
        }
        .task(id: model.selectedSceneID) {
            await model.loadSceneDetail()
        }
        .sheet(isPresented: $isEditingScreenplay) {
            if let sceneID = model.selectedSceneID {
                SceneScreenplayEditorSheet(
                    model: model,
                    sceneID: sceneID,
                    initialText: model.sceneDetailText
                )
            }
        }
    }

    @ViewBuilder
    private func content(_ detail: SceneDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(detail.scene.heading)
                    .font(.title3)
                    .textSelection(.enabled)
                Text(subheading(detail.scene))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SceneSynopsisEditor(model: model, scene: detail.scene)

            // PHASE4_DESIGN §5.2's Required Assets panel: the checklist rows in contract
            // B's order restricted to this scene, every row a deep link into the workshop.
            requiredAssetsPanel(detail)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Entities").font(.headline)
                    Spacer(minLength: 8)
                    Button("Edit Entities") {
                        model.presentedSheet = .sceneEntities(sceneID: detail.scene.id)
                    }
                    .accessibilityIdentifier("editSceneEntitiesButton")
                    .accessibilityLabel("Add or remove entities in this scene")
                }
                if detail.entitiesByRole.isEmpty {
                    Text("No entities in this scene yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(SceneEntityRole.allCases, id: \.self) { role in
                    let entities = detail.entities(role: role)
                    if !entities.isEmpty {
                        Text(role.displayName).font(.caption).foregroundStyle(.secondary)
                        ForEach(entities) { entity in
                            Button {
                                Task { await model.reveal(.entity(id: entity.id)) }
                            } label: {
                                Text(entity.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.link)
                            .accessibilityIdentifier("revealEntityButton")
                            .accessibilityLabel("Reveal entity: \(entity.name)")
                        }
                    }
                }
            }

            if !detail.states.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("States in This Scene").font(.headline)
                    ForEach(detail.states) { state in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(model.entityNames[state.entityID] ?? "Entity") · \(state.category.displayName): \(state.description)")
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Scene Text").font(.headline)
                    Spacer()
                    Button("Edit Screenplay…") { isEditingScreenplay = true }
                        .accessibilityIdentifier("editSceneScreenplayButton")
                }
                Text(sceneText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.default, value: model.isHighlightFlashing)
                    .accessibilityIdentifier("sceneTextView")
                    .accessibilityLabel("Scene text")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private func subheading(_ scene: FilmCore.Scene) -> String {
        var parts = ["Scene \(scene.ordinal)"]
        if let number = scene.sceneNumber, !number.isEmpty { parts.append("#\(number)") }
        if !scene.intExt.displayName.isEmpty { parts.append(scene.intExt.displayName) }
        if !scene.locationText.isEmpty { parts.append(scene.locationText) }
        if !scene.timeOfDay.isEmpty { parts.append(scene.timeOfDay) }
        if scene.isOmitted { parts.append("Omitted") }
        return parts.joined(separator: " · ")
    }

    // MARK: - PHASE4_DESIGN §5.2's Required Assets panel

    @ViewBuilder
    private func requiredAssetsPanel(_ detail: SceneDetail) -> some View {
        if let row = model.readinessRow(forSceneID: detail.scene.id),
           !row.missing.isEmpty || !row.optionalRequirements.isEmpty
        {
            VStack(alignment: .leading, spacing: 6) {
                Text("Required Assets").font(.headline)

                // The panel header's state and count line (§5.2).
                Text(
                    "\(row.state.displayName) · \(row.readyCount) / \(row.requiredCount)"
                )
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("sceneReadinessPanelHeader")

                ForEach(Array(row.missing.enumerated()), id: \.element.id) { index, item in
                    checklistRow(row.ordinal, index: index + 1, item: item)
                }

                // Optional rows below: greyed, tagged `optional`, uncounted (§3.4, §14.5).
                ForEach(Array(row.optionalRequirements.enumerated()), id: \.element.id) {
                    index, optional in
                    optionalRow(row.ordinal, index: row.missing.count + index + 1, optional: optional)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sceneReadinessPanel")
        }
    }

    private func checklistRow(_ ordinal: Int, index: Int, item: SceneMissingRequirement) -> some View {
        Button {
            Task { await model.reveal(.requirement(id: item.requirementID)) }
        } label: {
            HStack(spacing: 6) {
                Text(item.displayStatus == .approved ? "✓" : "✕")
                    .foregroundStyle(item.displayStatus == .approved ? .green : .secondary)
                    .monospacedDigit()
                // The entity — requirement display convention (the Phase 2 rule).
                Text("\(item.entityName) — \(item.requirementName)")
                    .frame(maxWidth: .infinity, alignment: .leading)
                if item.isBlocked, let first = item.blockedBy.first {
                    // The requirement-Blocked badge names the first entry's display name.
                    Text("Blocked by \(first.displayName)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("sceneChecklistBlockedBadge_\(ordinal)_\(index)")
                }
                Text(item.displayStatus.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sceneChecklistRow_\(ordinal)_\(index)")
        .accessibilityLabel("\(item.entityName) — \(item.requirementName): \(item.displayStatus.displayName)")
    }

    private func optionalRow(_ ordinal: Int, index: Int, optional: SceneOptionalRequirement)
        -> some View
    {
        Button {
            Task { await model.reveal(.requirement(id: optional.requirementID)) }
        } label: {
            HStack(spacing: 6) {
                Text(optional.displayStatus == .approved ? "✓" : "✕")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text("\(optional.entityName) — \(optional.requirementName)")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("optional")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(optional.displayStatus.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sceneOptionalRow_\(ordinal)_\(index)")
        .accessibilityLabel("Optional: \(optional.entityName) — \(optional.requirementName)")
    }

    /// The scene body with the revealed evidence span highlighted in **semantic** colors —
    /// a flash right after the reveal, then a quieter steady highlight. No parsing: the
    /// span comes from the evidence row, mapped into the scene's own text by the model.
    private var sceneText: AttributedString {
        let text = model.sceneDetailText
        guard let span = model.highlightInSceneText,
              let low = Self.index(atUTF16: span.lowerBound, in: text),
              let high = Self.index(atUTF16: span.upperBound, in: text),
              low < high, high <= text.endIndex
        else { return AttributedString(text) }
        var result = AttributedString(String(text[text.startIndex ..< low]))
        var highlighted = AttributedString(String(text[low ..< high]))
        highlighted.backgroundColor = model.isHighlightFlashing
            ? Color.accentColor.opacity(0.45)
            : Color.secondary.opacity(0.25)
        result += highlighted
        result += AttributedString(String(text[high ..< text.endIndex]))
        return result
    }

    /// `String.Index(utf16Offset:in:)` clamps rather than failing, so the bounds are
    /// checked here before the highlight math trusts an offset.
    private static func index(atUTF16 offset: Int, in text: String) -> String.Index? {
        guard offset >= 0, offset <= (text as NSString).length else { return nil }
        return String.Index(utf16Offset: offset, in: text)
    }
}
