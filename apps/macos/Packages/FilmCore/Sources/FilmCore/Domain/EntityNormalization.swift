import Foundation

/// The single case-folding function behind `entities.name_normalized` and
/// `entity_aliases.normalized` (PHASE1_DESIGN §3.4, §3.5).
///
/// One column, one key space: every normalized value in the database is produced here.
/// Cue aliases are peeled by `FilmScript.CueNormalizer` *first* and then normalized here,
/// so `SARAH`, `SARAH (V.O.)`, and `SARAH (CONT'D)` share one row (§3.5).
///
/// Diacritics are deliberately **not** folded — `RENÉ` and `RENE` are different names.
public enum EntityNormalization: Sendable {
    /// Unicode case-fold, NFC, whitespace-collapse, trim.
    public static func normalize(_ raw: String) -> String {
        let folded = raw.folding(options: [.caseInsensitive], locale: nil)
        let collapsed = folded
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        return collapsed.precomposedStringWithCanonicalMapping
    }
}
