import SwiftUI

/// "Workflows" section shown at the top of SessionDetailView when a session
/// has one or more workflow runs. Running workflows are always expanded with
/// their phase tree; completed workflows collapse to a one-line summary.
///
/// Color/chevron conventions (app-design-conventions): completed uses
/// `.secondary` (never green — green = active only); chevron is
/// right (collapsed) / down (expanded); tinted surface uses opacity 0.08 +
/// continuous corner radius (macOS sidebar-selection tone).
struct WorkflowSection: View {
    let workflows: [WorkflowInfo]
    let sessionId: String
    let projectPath: String

    /// Workflow accent (purple) — distinct from goal's accentColor (blue).
    static let workflowColor = Color(red: 94/255, green: 92/255, blue: 230/255)

    var body: some View {
        if !workflows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    if workflows.contains(where: { $0.isRunning }) {
                        ProgressView().controlSize(.mini)
                    }
                    Text("Workflows")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                ForEach(workflows) { workflow in
                    WorkflowRow(
                        workflow: workflow,
                        sessionId: sessionId,
                        projectPath: projectPath
                    )
                }
            }
        }
    }
}

/// One workflow run. Running = always expanded; completed = collapsible.
private struct WorkflowRow: View {
    let workflow: WorkflowInfo
    let sessionId: String
    let projectPath: String

    @State private var isExpanded: Bool

    init(workflow: WorkflowInfo, sessionId: String, projectPath: String) {
        self.workflow = workflow
        self.sessionId = sessionId
        self.projectPath = projectPath
        // Running workflows start expanded; completed start collapsed.
        _isExpanded = State(initialValue: workflow.isRunning)
    }

    private var tint: Color {
        workflow.isRunning ? WorkflowSection.workflowColor : .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            if isExpanded {
                ForEach(workflow.phases) { phase in
                    phaseView(phase)
                }
            }
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(workflow.isRunning
                      ? WorkflowSection.workflowColor.opacity(0.08)
                      : Color.secondary.opacity(0.06))
        )
        .overlay(alignment: .leading) {
            // Left accent rule.
            Rectangle().fill(tint).frame(width: 2)
        }
        .animation(.easeInOut(duration: 0.15), value: isExpanded)
    }

    @ViewBuilder private var header: some View {
        // A running workflow has nothing to toggle (always expanded), so it is
        // a plain view — NOT a disabled Button. A `.disabled` Button dims its
        // whole label subtree, which would mute the purple running-name (the
        // feature's primary in-dropdown signal). Only the collapsible
        // completed case is a Button. (App convention: no dead tap targets.)
        if workflow.isRunning {
            headerContent
        } else {
            Button {
                isExpanded.toggle()
            } label: {
                headerContent
            }
            .buttonStyle(.plain)
        }

        if workflow.isRunning && !workflow.phases.isEmpty {
            ProgressView(value: progressFraction)
                .tint(WorkflowSection.workflowColor)
                .scaleEffect(x: 1, y: 0.6, anchor: .center)
        }
    }

    private var headerContent: some View {
        // Name and summary stack vertically rather than sharing one row: at the
        // fixed 350pt dropdown width a long name + long summary would otherwise
        // truncate the summary on the right. Stacking mirrors the other detail
        // rows (Context:/Thinking:/Skills:) and loses no information.
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                // Chevron only on the collapsible (completed) case.
                if !workflow.isRunning {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                Text(workflow.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(workflow.isRunning ? WorkflowSection.workflowColor : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            Text(summaryLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var summaryLine: String {
        let phaseCount = workflow.phases.count
        var parts: [String] = []
        if workflow.isRunning {
            parts.append("running")
        } else {
            parts.append("completed")
        }
        if phaseCount > 0 {
            parts.append("phase \(workflow.completedPhaseCount)/\(phaseCount)")
        }
        parts.append("\(workflow.agentCount) agents")
        parts.append(TokenFormatter.compact(workflow.totalTokens.total) + " tok")
        return parts.joined(separator: " · ")
    }

    private var progressFraction: Double {
        guard workflow.agentCount > 0 else { return 0 }
        return min(1.0, Double(workflow.completedAgentCount) / Double(workflow.agentCount))
    }

    @ViewBuilder private func phaseView(_ phase: WorkflowPhase) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                if phase.isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)   // not green: completed tone
                } else {
                    ProgressView().controlSize(.mini)
                }
                Text(phase.title)
                    .font(.system(size: 9, weight: .medium))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 3)

            ForEach(phase.agents) { agent in
                AgentRow(
                    agent: agent,
                    sessionId: sessionId,
                    projectPath: projectPath,
                    workflowId: workflow.id
                )
                .padding(.leading, 6)
            }
        }
    }
}
