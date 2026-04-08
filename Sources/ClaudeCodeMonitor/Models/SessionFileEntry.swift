import Foundation

struct SessionFileEntry: Decodable, Sendable {
    let pid: Int32
    let sessionId: String
    let cwd: String
    let startedAt: Double
    let kind: String
    let entrypoint: String
    let name: String?

    var startedAtDate: Date {
        Date(timeIntervalSince1970: startedAt / 1000.0)
    }
}
