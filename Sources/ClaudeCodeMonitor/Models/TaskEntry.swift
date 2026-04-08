import Foundation

struct TaskEntry: Identifiable, Sendable, Decodable {
    let id: String
    let subject: String
    let description: String?
    let status: String
    let blocks: [String]?
    let blockedBy: [String]?

    var statusSymbol: String {
        switch status {
        case "completed": return "checkmark.circle.fill"
        case "in_progress": return "circle.dashed"
        default: return "circle"
        }
    }
}
