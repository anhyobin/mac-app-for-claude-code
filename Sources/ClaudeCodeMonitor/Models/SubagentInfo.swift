import Foundation

struct SubagentInfo: Identifiable, Sendable {
    let id: String
    let agentType: String
    let description: String?
    var tokens: TokenUsage
    let toolUseCount: Int
    let messageCount: Int
    let toolBreakdown: [String: Int]
    /// Count of Skill tool invocations keyed by the invoked skill name.
    ///
    /// Extracted from `tool_use` blocks where `name == "Skill"` in the
    /// subagent's JSONL, using `input.skill` as the key. Plugin namespace
    /// is preserved verbatim (e.g., `oh-my-claudecode:hud`).
    let skillCounts: [String: Int]
    let lastActivity: Date?  // mtime of agent JSONL file
    var isActive: Bool { // active if modified within last 60 seconds
        guard let lastActivity else { return false }
        return Date().timeIntervalSince(lastActivity) < 60
    }
}
