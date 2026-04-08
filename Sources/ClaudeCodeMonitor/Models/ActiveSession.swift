import Foundation

struct ActiveSession: Identifiable, Sendable {
    let id: String
    let pid: Int32
    let cwd: String
    let projectName: String
    let startedAt: Date
    let kind: String
    let entrypoint: String
    let name: String?
    let lastActivity: Date?

    var elapsed: TimeInterval {
        Date().timeIntervalSince(startedAt)
    }
}
