import Foundation

struct AgentDetailData: Sendable {
    let recentMessages: [ConversationEntry]
    let fileChanges: [FileChange]
    let toolBreakdown: [String: Int]
    /// Count of Skill tool invocations made by this subagent, keyed by
    /// skill name (plugin namespace preserved). Sourced from the cached
    /// ``SubagentInfo.skillCounts`` so the detail view does not need to
    /// re-scan the agent JSONL.
    let skillBreakdown: [String: Int]
}
