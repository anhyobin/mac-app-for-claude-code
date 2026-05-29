import Foundation

/// Aggregate state for a single workflow run within a session.
///
/// Sourced from `workflows/{id}.json` (run state, written at completion) and
/// `subagents/workflows/{id}/` (agent transcripts + journal). When the
/// `.json` is absent (run still starting), `name` falls back to the
/// `scripts/{name}-{id}.js` filename and phases collapse to a single
/// "running" group.
struct WorkflowInfo: Identifiable, Sendable {
    let id: String              // wf_id
    let name: String
    let status: WorkflowRunStatus
    let phases: [WorkflowPhase]
    let totalTokens: TokenUsage
    let totalToolCalls: Int
    let agentCount: Int
    let durationMs: Int?
    let lastActivity: Date?     // workflows/{id} dir or journal mtime

    var isRunning: Bool { status == .running }

    /// Count of agents that are no longer active, used for the progress bar.
    /// Smoother than phase-granularity. "Done" here means `SubagentInfo`'s
    /// 60s-mtime `isActive` is false — a heuristic, not a true result-presence
    /// check, which is sufficient for a progress indicator.
    var completedAgentCount: Int {
        phases.reduce(0) { acc, phase in
            acc + phase.agents.filter { !$0.isActive }.count
        }
    }

    /// Number of phases that are fully complete, for the "phase n/m" text.
    var completedPhaseCount: Int {
        phases.filter { $0.isComplete }.count
    }
}
