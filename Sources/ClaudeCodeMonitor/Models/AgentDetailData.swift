import Foundation

struct AgentDetailData: Sendable {
    let recentMessages: [ConversationEntry]
    let fileChanges: [FileChange]
    let toolBreakdown: [String: Int]
}
