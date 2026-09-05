import Foundation

/// PHASE4_DESIGN §5.3's dashboard help text — §3.5's three stated bounds and the asset
/// line's definition, one home out of the views and asserted by
/// `ReadinessWindowModelTests`. Stated honestly rather than discovered.
enum DashboardCopy {
    /// Bound 1: the figures are *per-asset*; choosing an optimal set is a set-cover
    /// computation V1 does not attempt (§13.7).
    static let boundPerAsset =
        "Figures are per asset: approving one asset advances its own scenes and unblocks its own dependents, not an optimal combination."

    /// Bound 2: advancing ≠ completing — a scene missing three assets appears in all
    /// three counts.
    static let boundAdvancesNotCompletes =
        "“Advances” counts scenes an approval moves closer, not scenes it alone completes — a scene missing three assets appears in all three counts."

    /// Bound 3: unblocks is deliberately strict — a dependent waiting on two blockers
    /// counts for neither until only one remains (§14.1).
    static let boundSoleUnsatisfied =
        "“Unblocks” is strict: an asset waiting on two blockers counts for neither until only one remains."

    /// The asset line's definition, stated on the surface (§5.3): manifest completion,
    /// not scene gating — optional rows are in the denominator here.
    static let assetsDefinition =
        "Approved reference requirements out of all active requirements — manifest completion, not scene gating."
}
