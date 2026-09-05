import FilmCore
import SwiftUI

/// The per-field lock control of §3.7 and §3.11 — one button per lockable field, aliases
/// included.
///
/// It toggles **its own** `(subject, field)` row and nothing else: a field that reads as
/// locked because a whole-record lock covers it is not this button's to unlock, so the
/// button stays showing the record lock and disables itself. Icon-only, so it carries an
/// accessibility label as well as an identifier, and the identifier says which way the
/// next click goes — `lockNameButton` when it will lock, `unlockNameButton` when it will
/// unlock.
struct LockButton: View {
    @Bindable var model: ProjectWindowModel
    let subject: SubjectRef
    let field: LockField
    /// The noun the label says and the identifier capitalizes: "Name", "Description",
    /// "Alias", "Synopsis", "Record".
    let name: String

    var body: some View {
        let isLocked = model.hasLock(subject, field: field)
        let isCoveredByRecordLock = !isLocked && field != .whole
            && model.hasLock(subject, field: .whole)
        return Button {
            Task {
                if isLocked {
                    await model.unlock(subject: subject, field: field)
                } else {
                    await model.lock(subject: subject, field: field)
                }
            }
        } label: {
            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                .foregroundStyle(isLocked ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.borderless)
        .disabled(isCoveredByRecordLock)
        .accessibilityIdentifier("\(isLocked ? "unlock" : "lock")\(name)Button")
        .accessibilityLabel(isLocked ? "Unlock \(name)" : "Lock \(name)")
    }
}
