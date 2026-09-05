import SwiftUI

struct AddMissingEntityButton: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        Button {
            Task { await model.addMissingEntity() }
        } label: {
            Label("Add Missing…", systemImage: "plus")
        }
        .disabled(model.section.entityKind == nil)
        .accessibilityIdentifier("addMissingEntityButton")
    }
}
