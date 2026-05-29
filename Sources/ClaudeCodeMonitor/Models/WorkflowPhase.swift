import Foundation

/// One phase of a workflow run, with the agents assigned to it.
///
/// Agents reuse ``SubagentInfo`` because workflow agents are written in the
/// same JSONL format as flat subagents (just one directory deeper). The
/// workflow's human label for the agent (e.g. "game-design-balance") is
/// carried in ``SubagentInfo/description``.
struct WorkflowPhase: Identifiable, Sendable {
    let id: Int          // phaseIndex from workflowProgress
    let title: String
    let agents: [SubagentInfo]
    /// Parse-time snapshot: true when no agent in this phase was active
    /// (within the 60s mtime window) at load time. The producing loader must
    /// set this from the same snapshot it builds `agents` with, since
    /// `SubagentInfo.isActive` is time-varying.
    let isComplete: Bool
}
