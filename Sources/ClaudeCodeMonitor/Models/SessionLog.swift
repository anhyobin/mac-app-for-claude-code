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
}
