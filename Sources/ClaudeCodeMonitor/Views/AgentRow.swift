import SwiftUI

struct AgentRow: View {
    @Environment(ClaudeDataStore.self) private var dataStore
    let agent: SubagentInfo
    let sessionId: String
    let projectPath: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
                if isExpanded {
                    Task {
                        await dataStore.loadAgentDetail(
                            sessionId: sessionId,
                            agentHash: agent.id,
                            projectPath: projectPath
                        )
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    // Active indicator
                    if agent.isActive {
                        Circle()
                            .fill(.green)
                            .frame(width: 5, height: 5)
                    }

                    Text(agent.agentType)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(agentColor.opacity(agent.isActive ? 0.2 : 0.1))
                        .foregroundStyle(agentColor)
                        .clipShape(Capsule())

                    if let desc = agent.description {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if agent.messageCount > 0 {
                        let topTools = agent.toolBreakdown.sorted { $0.value > $1.value }.prefix(3).map(\.key).joined(separator: ", ")
                        Text(topTools.isEmpty ? "\(agent.messageCount) msgs" : topTools)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if agent.tokens.coreTokens > 0 {
                        TokenBadge(count: agent.tokens.coreTokens)
                    }

                    if agent.toolUseCount > 0 {
                        Label("\(agent.toolUseCount)", systemImage: "wrench")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                let key = "\(sessionId)/\(agent.id)"
                if let detail = dataStore.agentDetailData[key] {
                    AgentDetailView(data: detail)
                        .padding(.top, 4)
                } else {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    private var agentColor: Color {
        switch agent.agentType.lowercased() {
        case "dev": return .blue
        case "review": return .orange
        case "qa": return .green
        case "explore": return .purple
        case "plan": return .teal
        default: return .gray
        }
    }
}
