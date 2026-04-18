import SwiftUI

struct SessionDetailView: View {
    let data: SessionExpandedData
    let sessionId: String
    let projectPath: String

    @State private var showCompletedAgents = false
    @State private var showAllCompleted = false

    private var activeAgents: [SubagentInfo] {
        data.agents.filter { $0.isActive }
    }

    private var completedAgents: [SubagentInfo] {
        data.agents.filter { !$0.isActive }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Token summary
            if data.totalTokens.total > 0 {
                // When subagents exist and main session has tokens, label it as "Total"
                if !data.agents.isEmpty, data.mainTokens.total > 0 {
                    Text("Total")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    tokenLabel("In", count: data.totalTokens.inputTokens, color: .blue)
                    tokenLabel("Out", count: data.totalTokens.outputTokens, color: .green)
                }
                if (data.totalTokens.cacheReadTokens + data.totalTokens.cacheWriteTokens) > 0 {
                    Text("Cache: \(TokenFormatter.compact(data.totalTokens.cacheReadTokens + data.totalTokens.cacheWriteTokens))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Context window detail. Only rendered when the gauge itself would
            // render — keeps the row quiet for sessions where the ratio is
            // unknown (no assistant turn yet, unknown model).
            if let model = data.mainModel,
               let ratio = data.contextUsageRatio(model: model),
               let snapshot = data.mainLastTurnUsage {
                let used = snapshot.inputTokens + snapshot.cacheReadTokens + snapshot.cacheWriteTokens
                let limit = ModelContextLimits.maxContext(for: model)
                Text("Context: \(TokenFormatter.compact(used)) / \(TokenFormatter.compact(limit)) (\(Int((min(ratio, 1.0)) * 100))%)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            // Active agents section
            if !activeAgents.isEmpty {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text("Active (\(activeAgents.count))")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }

                ForEach(activeAgents) { agent in
                    AgentRow(
                        agent: agent,
                        sessionId: sessionId,
                        projectPath: projectPath
                    )
                }
            }

            // Completed agents section
            if !completedAgents.isEmpty {
                if activeAgents.isEmpty && completedAgents.count <= 5 {
                    // Few agents, no active — just show all
                    Text("Agents (\(completedAgents.count))")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    ForEach(completedAgents) { agent in
                        AgentRow(
                            agent: agent,
                            sessionId: sessionId,
                            projectPath: projectPath
                        )
                    }
                } else {
                    // Many agents or mixed — collapsible section
                    Button {
                        showCompletedAgents.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showCompletedAgents ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8))
                            Text("\(completedAgents.count) completed")
                                .font(.caption)
                                .fontWeight(.medium)

                            // Compact summary when collapsed
                            if !showCompletedAgents {
                                Text("· \(completedAgentsSummary)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    if showCompletedAgents {
                        let visibleAgents = showAllCompleted ? completedAgents : Array(completedAgents.prefix(5))
                        ForEach(visibleAgents) { agent in
                            AgentRow(
                                agent: agent,
                                sessionId: sessionId,
                                projectPath: projectPath
                            )
                            .opacity(0.7)
                        }

                        if !showAllCompleted && completedAgents.count > 5 {
                            Button {
                                showAllCompleted = true
                            } label: {
                                Text("Show all \(completedAgents.count) agents")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 4)
                        }
                    }
                }
            }

            if data.agents.isEmpty {
                Text("No agents")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Tasks section
            if !data.tasks.isEmpty {
                Text("Tasks (\(data.tasks.count))")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                ForEach(data.tasks) { task in
                    HStack(spacing: 6) {
                        Image(systemName: task.statusSymbol)
                            .font(.caption)
                            .foregroundStyle(taskColor(for: task.status))

                        Text(task.subject)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(task.status == "completed" ? .secondary : .primary)
                    }
                }
            } else {
                Text("No tasks")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.15), value: showCompletedAgents)
        .animation(.easeInOut(duration: 0.15), value: showAllCompleted)
    }

    /// Compact summary of completed agent types, e.g. "3 dev, 2 qa, 1 review"
    private var completedAgentsSummary: String {
        var typeCounts: [String: Int] = [:]
        for agent in completedAgents {
            typeCounts[agent.agentType, default: 0] += 1
        }
        return typeCounts
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { "\($0.value) \($0.key)" }
            .joined(separator: ", ")
    }

    private func tokenLabel(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(TokenFormatter.compact(count))
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }

    private func taskColor(for status: String) -> Color {
        switch status {
        case "completed": return .green
        case "in_progress": return .blue
        default: return .secondary
        }
    }
}
