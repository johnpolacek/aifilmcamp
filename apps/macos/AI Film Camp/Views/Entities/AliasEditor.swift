import FilmCore
import SwiftUI

/// The inspector's alias section, editable (§3.5, §3.11): every surface form that maps to
/// this entity, each with its own lock (an **alias lock** pins that form to this entity
/// and refuses removal, re-targeting, and split), plus the field that adds one.
///
/// A conflicting alias is FilmCore's refusal to make — `.aliasConflict(existingEntityID:)`
/// — and it is surfaced verbatim rather than pre-checked here.
struct AliasEditor: View {
    @Bindable var model: ProjectWindowModel
    let detail: EntityDetail

    @State private var newAlias = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(detail.aliases) { alias in
                row(alias)
            }
            HStack(spacing: 6) {
                TextField("New alias", text: $newAlias)
                    .textFieldStyle(.roundedBorder)
                    .tracksTextEditing(model)
                    .accessibilityIdentifier("newAliasField")
                    .accessibilityLabel("New alias")
                Button("Add") { add() }
                    .disabled(trimmedNewAlias.isEmpty || isRecordLocked)
                    .accessibilityIdentifier("addAliasButton")
                    .accessibilityLabel("Add alias")
            }
        }
    }

    @ViewBuilder
    private func row(_ alias: EntityAlias) -> some View {
        let subject = SubjectRef(kind: .alias, id: alias.id)
        HStack(spacing: 6) {
            Text("\(alias.alias) · \(alias.aliasKind.rawValue.capitalized)")
                .textSelection(.enabled)
            Spacer(minLength: 8)
            LockButton(model: model, subject: subject, field: .whole, name: "Alias")
            Button {
                Task { await model.removeAlias(aliasID: alias.id) }
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(model.isLocked(subject, field: .whole) || isRecordLocked)
            .accessibilityIdentifier("removeAliasButton")
            .accessibilityLabel("Remove alias \(alias.alias)")
        }
    }

    private var trimmedNewAlias: String {
        newAlias.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A whole-record lock on the entity blocks alias addition **and** removal (§3.7).
    private var isRecordLocked: Bool {
        model.isLocked(SubjectRef(kind: .entity, id: detail.entity.id), field: .whole)
    }

    private func add() {
        let alias = trimmedNewAlias
        guard !alias.isEmpty else { return }
        newAlias = ""
        Task { await model.addAlias(entityID: detail.entity.id, alias: alias) }
    }
}
