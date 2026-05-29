import SwiftUI

@main
struct ClaudeCodeMonitorApp: App {
    @State private var dataStore = ClaudeDataStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environment(dataStore)
        } label: {
            HStack(spacing: 2) {
                menuBarIcon
                    // State dot sits on the icon's top-right. Offset keeps it
                    // within the menu-bar height while clearly detached from
                    // the glyph. The overlay layer is outside the `isTemplate`
                    // image so the dot keeps its color.
                    .overlay(alignment: .topTrailing) {
                        MenuBarDot(state: dataStore.menuBarDotState)
                            .offset(x: 3, y: -2)
                    }
                if !dataStore.activeSessions.isEmpty {
                    // Goal/workflow indicator folded into the count color.
                    // Priority: goal (blue accent) > running workflow (purple)
                    // > normal. Goal wins so an explicit /goal is never masked
                    // by a workflow tint. Pulse when either signal is active.
                    PulsingSessionCount(
                        count: dataStore.activeSessions.count,
                        tint: countTint,
                        pulsing: shouldPulse,
                        accessibilityText: accessibilityText
                    )
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIcon: some View {
        Group {
            // Load @2x for retina crispness, display at 18x18pt
            if let url = Bundle.module.url(forResource: "menubar-icon@2x", withExtension: "png"),
               let icon = NSImage(contentsOf: url) {
                Image(nsImage: {
                    icon.isTemplate = true
                    icon.size = NSSize(width: 21, height: 13) // point size, @2x pixels
                    return icon
                }())
            } else {
                Image(systemName: "terminal.fill")
            }
        }
    }

    /// Count color priority: goal (blue) > running workflow (purple) > normal.
    /// Purple is the single source of truth on ``WorkflowSection`` so the
    /// menu-bar tint and the in-dropdown workflow accent never drift apart.
    private var countTint: Color {
        if dataStore.hasActiveGoal { return .accentColor }
        if dataStore.hasRunningWorkflow { return WorkflowSection.workflowColor }
        return .primary
    }

    /// Pulse when either a goal or a workflow is active.
    private var shouldPulse: Bool {
        dataStore.hasActiveGoal || dataStore.hasRunningWorkflow
    }

    private var accessibilityText: String {
        let n = dataStore.activeSessions.count
        if dataStore.hasActiveGoal { return "\(n) sessions, goal in progress" }
        if dataStore.hasRunningWorkflow { return "\(n) sessions, workflow running" }
        return "\(n) sessions"
    }
}

/// Active-session count with an optional pulsing tint. Modeled on
/// ``MenuBarDot``'s `PulseRing`: the pulsing variant is a conditionally
/// rendered subview so SwiftUI fires `onAppear` fresh each time pulsing
/// begins — this makes a workflow that starts mid-session (after the
/// always-present menu-bar label has already appeared) animate correctly,
/// rather than freezing at a static dimmed opacity.
private struct PulsingSessionCount: View {
    let count: Int
    let tint: Color
    let pulsing: Bool
    let accessibilityText: String

    var body: some View {
        Group {
            if pulsing {
                Pulsing(tint: tint, count: count)
            } else {
                Text("\(count)")
                    .font(.caption2)
                    .foregroundStyle(tint)
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    /// Fresh-mounted whenever `pulsing` flips true, so its `onAppear`
    /// reliably starts the repeating fade. Opacity eases 1.0 → 0.4 forever.
    private struct Pulsing: View {
        let tint: Color
        let count: Int
        @State private var dim = false

        var body: some View {
            Text("\(count)")
                .font(.caption2)
                .foregroundStyle(tint)
                .opacity(dim ? 0.4 : 1.0)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: dim)
                .onAppear { dim = true }
        }
    }
}
