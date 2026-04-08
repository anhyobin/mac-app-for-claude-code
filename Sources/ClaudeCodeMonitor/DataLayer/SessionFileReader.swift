import Foundation

enum SessionFileReader {
    private static let sessionsDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions")
    }()

    static func readActiveSessions() -> [ActiveSession] {
        let fm = FileManager.default
        let dir = sessionsDirectory.path

        guard fm.fileExists(atPath: dir) else { return [] }

        let files: [String]
        do {
            files = try fm.contentsOfDirectory(atPath: dir)
        } catch {
            print("[SessionFileReader] Failed to list sessions directory: \(error)")
            return []
        }

        var sessions: [ActiveSession] = []
        let decoder = JSONDecoder()

        for file in files where file.hasSuffix(".json") {
            let filePath = sessionsDirectory.appendingPathComponent(file)
            guard let data = fm.contents(atPath: filePath.path) else { continue }

            let entry: SessionFileEntry
            do {
                entry = try decoder.decode(SessionFileEntry.self, from: data)
            } catch {
                print("[SessionFileReader] Failed to decode \(file): \(error)")
                continue
            }

            guard PIDValidator.isAlive(entry.pid) else { continue }

            let session = ActiveSession(
                id: entry.sessionId,
                pid: entry.pid,
                cwd: entry.cwd,
                projectName: PathDecoder.projectName(from: entry.cwd),
                startedAt: entry.startedAtDate,
                kind: entry.kind,
                entrypoint: entry.entrypoint,
                name: entry.name,
                lastActivity: nil
            )
            sessions.append(session)
        }

        return sessions
    }
}
