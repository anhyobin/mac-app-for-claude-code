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
                    Text("\(dataStore.activeSessions.count)")
                        .font(.caption2)
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
}
