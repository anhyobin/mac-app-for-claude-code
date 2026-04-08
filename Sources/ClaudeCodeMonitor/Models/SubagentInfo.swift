import Foundation

struct SubagentInfo: Identifiable, Sendable {
    let id: String
    let agentType: String
    let description: String?
    var tokens: TokenUsage
    let toolUseCount: Int
    let messageCount: Int
    let toolBreakdown: [String: Int]
    let lastActivity: Date?  // mtime of agent JSONL file
    var isActive: Bool { // active if modified within last 60 seconds
        guard let lastActivity else { return false }
        return Date().timeIntervalSince(lastActivity) < 60
    }
}
