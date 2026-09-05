import FilmCore
import SwiftUI

struct CharacterBundlePicker: View {
    let model: ProjectWindowModel
    let sceneID: UUID
    let currentRequirementIDs: Set<UUID>
    @Environment(\.dismiss) private var dismiss
    @State private var bundles: [CharacterOutfitBundle] = []
    @State private var isLoading = true
    @State private var isSelecting = false
    @State private var selectionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Choose Character Bundle").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.disabled(isSelecting)
            }
            Text("Use an original or saved outfit in this scene. Choosing a bundle replaces only this character’s outfit here; other scenes keep their selection.")
                .foregroundStyle(.secondary)
            if isLoading {
                ProgressView("Loading character bundles…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if bundles.isEmpty {
                ContentUnavailableView("No Ready Character Bundles", systemImage: "person.crop.rectangle.stack",
                    description: Text("Create a character’s face and body references first."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(bundles) { bundle in
                            HStack(spacing: 14) {
                                ReferenceVersionImage(model: model, version: bundle.faceVersion,
                                                      size: .card, minimumHeight: 86)
                                    .frame(width: 86, height: 86).clipped()
                                ReferenceVersionImage(model: model, version: bundle.bodyVersion,
                                                      size: .card, minimumHeight: 86)
                                    .frame(width: 150, height: 86).clipped()
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(bundle.entityName).font(.headline)
                                    Text(bundle.name).foregroundStyle(.secondary)
                                }
                                Spacer()
                                let isCurrent = currentRequirementIDs.contains(bundle.bodyRequirementID)
                                    && currentRequirementIDs.contains(bundle.faceRequirementID)
                                Button(isCurrent ? "In This Scene" : "Use in Scene") {
                                    isSelecting = true
                                    selectionError = nil
                                    Task {
                                        let selected = await model.useCharacterOutfit(bundle, sceneID: sceneID)
                                        isSelecting = false
                                        if selected { dismiss() }
                                        else { selectionError = "Could not select this bundle. Check that its references are available and unlocked." }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isSelecting || isCurrent)
                                .accessibilityLabel("Use \(bundle.entityName), \(bundle.name), in scene")
                                .accessibilityIdentifier("characterBundle.use.\(bundle.id.uuidString)")
                            }
                            .padding(12)
                            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
            if let selectionError {
                Text(selectionError).foregroundStyle(.orange)
            }
        }
        .padding(22)
        .frame(width: 780, height: 560)
        .task {
            bundles = await model.savedCharacterOutfitBundles()
            isLoading = false
        }
        .accessibilityIdentifier("characterBundle.picker")
    }
}
