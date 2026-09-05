import FilmCore
import Foundation

/// §3.11's navigation API target: what `ProjectWindowModel.reveal(_:)` may point at.
///
/// The highlight is a span in `Script.sourceText` (§3.3) — an evidence row's range — which
/// the scene detail maps into the scene's own text and flashes.
///
/// PHASE4_DESIGN §5.4 adds `.requirement`, the deep link into the Asset Workshop, routed
/// by `reveal(_:)` to the shipped `revealRequirement(id:)`. PHASE5_DESIGN §5.4 adds
/// `.scenePackage`, the deep link into the Generation section's package view — added
/// beside the shipped cases, carried through the same window-model routing.
enum RevealTarget: Equatable, Sendable {
    case scene(id: UUID, highlight: UTF16Range?)
    case entity(id: UUID)
    case requirement(id: UUID)
    case scenePackage(id: UUID)
}
