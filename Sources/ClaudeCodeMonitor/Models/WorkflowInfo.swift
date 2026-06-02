import Foundation

/// Aggregate state for a single workflow run within a session.
///
/// Sourced from `workflows/{id}.json` (run state, written at completion),
/// `workflows/scripts/{name}-{id}.js` (phase plan, written at start), and
/// `subagents/workflows/{id}/` (agent transcripts + journal).
///
/// **Phase attribution asymmetry (load-bearing):** the `agentId → phase`
/// mapping only exists in the completion-time JSON. While running, agents
/// cannot be placed in phases (measured ~5% recoverable from prompts), so
/// `phases` carries the **skeleton** (titles only, empty `agents`) and the
/// per-agent detail lives in the flat `agents` list. On completion, `phases`
/// becomes the full attributed tree.
struct WorkflowInfo: Identifiable, Sendable {
    let id: String              // wf_id
    let name: String
    let status: WorkflowRunStatus
    let phases: [WorkflowPhase]
    /// Flat list of all known agents — the running view's agent rows. On a
    /// completed run the same agents also appear attributed inside `phases`.
    let agents: [SubagentInfo]
    /// Total tokens across the run. Trusts the state JSON's pre-computed total
    /// when present (the logical-agent figure, excluding retry/nested files
    /// that inflate a raw on-disk sweep); falls back to the file sum mid-run.
    let totalTokens: Int
    let totalToolCalls: Int
    let agentCount: Int          // denominator for the progress aggregate
    /// Numerator: agents finished. Running → journal `result` count; completed
    /// → equals `agentCount`.
    let doneAgentCount: Int
    let durationMs: Int?
    let lastActivity: Date?     // workflows/{id} dir or journal mtime

    var isRunning: Bool { status == .running }

    /// Number of phases fully complete, for the completed "phase n/m" text.
    /// Meaningful only once completed (a running skeleton reports 0).
    var completedPhaseCount: Int {
        phases.filter { $0.isComplete }.count
    }
}
