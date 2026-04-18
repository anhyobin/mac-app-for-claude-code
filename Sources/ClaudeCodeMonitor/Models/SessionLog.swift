import Foundation

struct SessionLog: Identifiable, Sendable {
    let id: String
    let projectPath: String
    let projectName: String
    let startTime: Date?
    let endTime: Date?
    let duration: TimeInterval?
    let userMessageCount: Int
    let assistantMessageCount: Int
    var tokens: TokenUsage
    let toolCounts: [String: Int]
    let model: String?
    let slug: String?
    /// Number of extended-thinking blocks emitted by the assistant in this session.
    ///
    /// Counted from `message.content[].type == "thinking"` in JSONL lines. The
    /// JSONL parser sets this to 0 when the session contains no thinking blocks.
    let thinkingBlockCount: Int
}
