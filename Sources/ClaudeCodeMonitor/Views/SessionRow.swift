import SwiftUI

struct SessionRow: View {
    @Environment(ClaudeDataStore.self) private var dataStore
    let session: ActiveSession
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
                if isExpanded {
                    Task {
                        await dataStore.loadSessionDetail(
                            sessionId: session.id,
                            projectPath: session.cwd
                        )
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    StatusIndicator(isActive: true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.projectName)
                            .font(.system(.body, weight: .semibold))
                            .lineLimit(1)

                        Text("\(session.name ?? session.kind) \u{00B7} \(RelativeTimeFormatter.string(from: session.elapsed))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Model family badge (visible without expanding). Kept left of
                    // the token badge so the family color reads first — that's the
                    // most-scannable signal when skimming multiple active sessions.
                    if let expanded = dataStore.expandedSessionData[session.id] {
                        ModelBadge(rawModel: expanded.mainModel)
                    }

                    // Compact token badge (visible without expanding)
                    if let expanded = dataStore.expandedSessionData[session.id],
                       expanded.totalTokens.total > 0 {
                        Text(TokenFormatter.compact(expanded.totalTokens.total))
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    // Thinking-block counter (hidden when zero so rows without
                    // extended thinking stay uncluttered).
                    if let expanded = dataStore.expandedSessionData[session.id] {
                        ThinkingCounter(count: expanded.mainThinkingBlockCount)
                    }

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Context window gauge. Lives outside the button's contentShape so
            // tapping the bar does not toggle expansion. Uses the same
            // horizontal padding as the row content for visual alignment.
            if let expanded = dataStore.expandedSessionData[session.id],
               let ratio = expanded.contextUsageRatio(model: expanded.mainModel) {
                ContextGauge(ratio: ratio)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 2)
            }

            if isExpanded {
                if let data = dataStore.expandedSessionData[session.id] {
                    SessionDetailView(
                        data: data,
                        sessionId: session.id,
                        projectPath: session.cwd
                    )
                } else {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }
}
