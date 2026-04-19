import SwiftUI

private enum Layout {
    static let width: CGFloat = 350
    static let height: CGFloat = 500
}

struct MenuBarContentView: View {
    @Environment(ClaudeDataStore.self) private var dataStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let _ = context.date // Force re-render every 60s for relative time updates
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Claude Code Monitor")
                        .font(.headline)
                    Spacer()
                    Text("\(dataStore.activeSessions.count) active")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider()

                // Sessions list
                ScrollView {
                    VStack(spacing: 12) {
                        ActiveSessionsSection(sessions: dataStore.activeSessions)
                            .padding(.top, 8)

                        if !dataStore.recentSessions.isEmpty {
                            Divider()
                                .padding(.horizontal, 8)

                            RecentSessionsSection(sessions: dataStore.recentSessions)
                        }
                    }
                    .padding(.bottom, 8)
                }

                Divider()

                // Footer
                HStack {
                    Text("v0.2.0")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button {
                        dataStore.forceRefresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(width: Layout.width)
            // MenuBarExtra(style: .window) sizes the window from the content's
            // intrinsic/ideal size. ScrollView reports ideal height = 0, so the
            // middle region collapses and only header + footer remain (~70 pt).
            // Pin a fixed height here; ScrollView will fill it.
            .frame(height: Layout.height)
        }
    }
}
