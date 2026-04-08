import Foundation

struct ConversationEntry: Identifiable, Sendable {
    let id: String
    let role: String
    let timestamp: Date?
    let contentPreview: String
    let toolUses: [String]
    let toolResultCount: Int
}
