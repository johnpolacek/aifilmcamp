import FilmCore
import SwiftUI

/// §3.5's split: pull some of an entity's surface forms out into a new entity of the same
/// kind.
///
/// The sheet lists the entity's aliases and **its appearances with the alias that produced
/// each**, preselecting the appearances whose `matched_alias_id` is a selected alias — the
/// link FilmCore follows by itself. The rest of the list is the reason this sheet exists:
/// an appearance that lost a merge collision no longer carries the alias that produced it,
/// and no rule can recover the link, so the operator selects those by hand. What stays
/// checked is what travels, as `movedAppearanceIDs`.
struct SplitSheet: View {
    @Bindable var model: ProjectWindowModel
    let detail: EntityDetail

    @State private var newName = ""
    @State private var selectedAliasIDs: Set<UUID> = []
    @State private var movedAppearanceIDs: Set<UUID> = []
    @State private var isSplitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Split \(detail.entity.name)")
                .font(.headline)
                .accessibilityIdentifier("splitSheetTitle")

            HStack(spacing: 6) {
                Text("New name")
                TextField("New name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("splitNewNameField")
                    .accessibilityLabel("New entity name")
            }

            Text("Aliases to move").font(.subheadline)
            List(detail.aliases, selection: $selectedAliasIDs) { alias in
                Text("\(alias.alias) · \(alias.aliasKind.rawValue.capitalized)")
                    .tag(alias.id)
            }
            .frame(minHeight: 96)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("splitAliasList")
            .accessibilityLabel("Aliases to move")

            Text("Appearances to move").font(.subheadline)
            List {
                ForEach(detail.appearances) { appearance in
                    Toggle(isOn: appearanceBinding(appearance)) {
                        Text(appearanceLine(appearance))
                    }
                    .accessibilityIdentifier("splitAppearanceToggle")
                    .accessibilityLabel("Move appearance: \(appearanceLine(appearance))")
                }
            }
            .frame(minHeight: 96)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("splitAppearanceList")
            .accessibilityLabel("Appearances to move")

            HStack {
                Spacer()
                Button("Cancel") { model.presentedSheet = nil }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("cancelSplitButton")
                    .accessibilityLabel("Cancel split")
                Button("Split") { split() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSplit)
                    .accessibilityIdentifier("confirmSplitButton")
                    .accessibilityLabel("Split entity")
            }
        }
        .padding(16)
        .frame(minWidth: 460, minHeight: 460)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("splitSheet")
        .accessibilityLabel("Split entity")
        // Selecting an alias preselects the appearances it produced; anything else the
        // operator checks by hand stays checked.
        .onChange(of: selectedAliasIDs) { _, aliasIDs in
            movedAppearanceIDs = Set(
                detail.appearances
                    .filter { $0.matchedAliasID.map(aliasIDs.contains) == true }
                    .map(\.id)
            )
        }
    }

    /// §3.5: at least one alias moves and at least one has to remain on the source.
    private var canSplit: Bool {
        !isSplitting
            && !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !selectedAliasIDs.isEmpty
            && selectedAliasIDs.count < detail.aliases.count
    }

    private func appearanceBinding(_ appearance: SceneEntity) -> Binding<Bool> {
        Binding(
            get: { movedAppearanceIDs.contains(appearance.id) },
            set: { isOn in
                if isOn {
                    movedAppearanceIDs.insert(appearance.id)
                } else {
                    movedAppearanceIDs.remove(appearance.id)
                }
            }
        )
    }

    /// Scene · role · **the alias that produced this appearance**, which is the whole
    /// point of the list.
    private func appearanceLine(_ appearance: SceneEntity) -> String {
        let scene = model.scenes.first { $0.id == appearance.sceneID }
        let heading = scene.map { "\($0.ordinal). \($0.heading)" } ?? "Scene"
        let alias = appearance.matchedAliasID
            .flatMap { id in detail.aliases.first { $0.id == id }?.alias }
            ?? "no alias"
        return "\(heading) · \(appearance.role.displayName) · \(alias)"
    }

    private func split() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSplit else { return }
        isSplitting = true
        Task {
            let created = await model.splitEntity(
                entityID: detail.entity.id,
                aliasIDs: detail.aliases.map(\.id).filter { selectedAliasIDs.contains($0) },
                newName: name,
                movedAppearanceIDs: detail.appearances.map(\.id)
                    .filter { movedAppearanceIDs.contains($0) }
            )
            isSplitting = false
            guard created != nil else { return }
            model.presentedSheet = nil
        }
    }
}
