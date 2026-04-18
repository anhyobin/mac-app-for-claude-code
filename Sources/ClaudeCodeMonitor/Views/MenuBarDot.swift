import SwiftUI

/// Small colored dot overlaid on the menu-bar icon to surface session state.
///
/// Sized per macOS menu-bar convention (8pt). Rendered as a separate view so
/// ``ClaudeCodeMonitorApp`` can sit it on top of the template icon as an
/// overlay without affecting the icon's `isTemplate` treatment — template
/// tinting is applied to the `Image`, not to sibling overlays, so the dot
/// keeps its color in both light and dark menu bars.
///
/// Only the `.processing` state animates — a static pulse on `.active` would
/// conflict with the macOS convention that "everything fine" does not visually
/// draw attention. `.processing` is a transient state the user wants to notice.
struct MenuBarDot: View {
    let state: MenuBarDotState

    var body: some View {
        if state != .hidden {
            ZStack {
                // Pulse ring is drawn behind the solid dot so it reads as a
                // halo. Only rendered for `.processing`; other states are
                // intentionally static per Apple menu-bar conventions.
                if state == .processing {
                    PulseRing(color: fillColor)
                }
                Circle()
                    .fill(fillColor)
                    .frame(width: 8, height: 8)
            }
            .accessibilityLabel(accessibilityLabel)
        }
    }

    private var fillColor: Color {
        switch state {
        case .hidden: return .clear
        case .inactive: return .secondary
        case .active: return .green
        case .processing: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .hidden: return ""
        case .inactive: return "Sessions inactive"
        case .active: return "Session active"
        case .processing: return "Session processing"
        case .warning: return "Context window nearly full"
        case .error: return "Session error"
        }
    }
}

/// Concentric ring that scales from 100% → 200% while fading 1.0 → 0.0 on
/// a 1.5s infinite loop. Kept as its own view so the `onAppear` toggle that
/// starts the animation cleanly re-triggers when `.processing` appears.
private struct PulseRing: View {
    let color: Color
    @State private var animating = false

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 1)
            .frame(width: 8, height: 8)
            .scaleEffect(animating ? 2.0 : 1.0)
            .opacity(animating ? 0 : 1)
            .animation(
                .easeOut(duration: 1.5).repeatForever(autoreverses: false),
                value: animating
            )
            .onAppear { animating = true }
    }
}
