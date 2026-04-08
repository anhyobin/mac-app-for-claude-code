import Foundation

struct SessionExpandedData: Sendable {
    let agents: [SubagentInfo]
    let tasks: [TaskEntry]
    let mainTokens: TokenUsage
    let totalTokens: TokenUsage
    let mainJSONLMtime: Date?
}
