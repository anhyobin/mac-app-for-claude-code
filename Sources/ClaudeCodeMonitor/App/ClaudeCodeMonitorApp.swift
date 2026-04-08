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
