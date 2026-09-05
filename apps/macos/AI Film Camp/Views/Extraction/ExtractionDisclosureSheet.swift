import SwiftUI

struct ExtractionDisclosureSheet: View {
    let continueAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Before analyzing", systemImage: "hand.raised.fill")
                .font(.title2.bold())
            Text(ExtractionDisclosureText.firstRun)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel", role: .cancel, action: cancelAction)
                Spacer()
                Button("Continue", action: continueAction)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("continueExtractionDisclosureButton")
            }
        }
        .padding(24)
        .frame(width: 580)
        .accessibilityIdentifier("extractionDisclosureSheet")
    }
}
