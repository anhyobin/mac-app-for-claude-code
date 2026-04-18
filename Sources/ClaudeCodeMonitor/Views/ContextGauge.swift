import SwiftUI

/// 2pt hairline progress bar showing how full the session's context window is.
///
/// Hidden when the ratio is nil (unknown model or no assistant turn yet). The
/// ratio may exceed 1.0 in edge cases (see ``SessionExpandedData/contextUsageRatio(model:)``),
/// so the fill is clamped before binding to ``ProgressView``.
///
/// Color thresholds match the menu-bar dot warning semantics:
/// - `< 80%` → secondary (calm, no signal)
/// - `80-94%` → orange (user should think about compacting soon)
/// - `≥ 95%` → red (matches ``MenuBarDotState/warning`` threshold)
///
/// Rendered via `.scaleEffect(y: 0.5)` because SwiftUI's linear ProgressView
/// has a ~4pt minimum intrinsic height on macOS; scaling gives us the 2pt
/// hairline without a custom shape.
struct ContextGauge: View {
    let ratio: Double

    private var tint: Color {
        switch ratio {
        case ..<0.80: return .secondary
        case ..<0.95: return .orange
        default: return .red
        }
    }

    var body: some View {
        ProgressView(value: min(max(ratio, 0), 1.0))
            .progressViewStyle(.linear)
            .tint(tint)
            .scaleEffect(x: 1, y: 0.5, anchor: .center)
            .frame(height: 2)
            // Avoid the gauge inheriting button animation timing from the
            // enclosing SessionRow when the chevron expands.
            .animation(nil, value: ratio)
    }
}
