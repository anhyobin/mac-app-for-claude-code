import SwiftUI

struct ActiveSessionsSection: View {
    let sessions: [ActiveSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ACTIVE SESSIONS")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            if sessions.isEmpty {
                VStack(spacing: 4) {
                    Text("No active sessions")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Run 'claude' in terminal to start")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
            } else {
                ForEach(sessions) { session in
                    SessionRow(session: session)
                }
            }
        }
    }
}
