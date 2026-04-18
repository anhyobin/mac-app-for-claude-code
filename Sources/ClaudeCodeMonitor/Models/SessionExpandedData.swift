import Foundation

struct SessionExpandedData: Sendable {
    let agents: [SubagentInfo]
    let tasks: [TaskEntry]
    let mainTokens: TokenUsage
    let totalTokens: TokenUsage
    let mainJSONLMtime: Date?
    /// Extended-thinking blocks emitted by the main session's assistant.
    ///
    /// Counted only from the main session JSONL — subagent thinking blocks are
    /// intentionally excluded for v0.2 because the UI surface is the session row,
    /// not the aggregate. Call sites should treat this as "main session only".
    let mainThinkingBlockCount: Int
}
