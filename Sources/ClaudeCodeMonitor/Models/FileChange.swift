import Foundation

struct FileChange: Identifiable, Sendable {
    var id: String { filePath }
    let filePath: String
    let toolName: String
    let timestamp: Date?
}
