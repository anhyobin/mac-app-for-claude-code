import SwiftUI

struct RecentSessionsSection: View {
    let sessions: [SessionLog]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RECENT SESSIONS")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            if sessions.isEmpty {
                Text("No recent sessions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach(sessions) { session in
                    RecentSessionRow(session: session)
                }
            }
        }
    }
}

private struct RecentSessionRow: View {
    let session: SessionLog

    var body: some View {
        HStack(spacing: 8) {
            StatusIndicator(isActive: false)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(session.projectName)
                        .font(.system(.body, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    if let endTime = session.endTime {
                        Text(relativeTime(since: endTime))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 4) {
                    // Model family badge replaces the prior plain-text model
                    // name — same info, but the tint makes Opus/Sonnet/Haiku
                    // distinguishable in a dense list without reading.
                    ModelBadge(rawModel: session.model)
                    if let duration = session.duration {
                        if session.model != nil {
                            Text("\u{00B7}")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Text(RelativeTimeFormatter.string(from: duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if session.tokens.coreTokens > 0 {
                        Text("\u{00B7}")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        TokenBadge(count: session.tokens.coreTokens)
                    }
                    ThinkingCounter(count: session.thinkingBlockCount)
                    SkillCounter(count: session.skillCounts.values.reduce(0, +))
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    private func relativeTime(since date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}
