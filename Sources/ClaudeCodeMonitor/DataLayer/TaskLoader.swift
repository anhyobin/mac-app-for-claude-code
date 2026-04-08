import Foundation

enum TaskLoader {
    private static let tasksDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/tasks")
    }()

    /// Load tasks for a session. Checks both session-ID directory and team-name directories.
    /// Team tasks are found by checking which task directories have been recently modified
    /// and contain tasks that match the session's timeframe.
    static func loadTasks(for sessionId: String) -> [TaskEntry] {
        let fm = FileManager.default
        var allTasks: [TaskEntry] = []

        // 1. Load tasks from session-specific directory
        let sessionTasksDir = tasksDirectory.appendingPathComponent(sessionId)
        if fm.fileExists(atPath: sessionTasksDir.path) {
            allTasks.append(contentsOf: loadTasksFromDirectory(sessionTasksDir))
        }

        // 2. Also check for team task directories (non-UUID names)
        if let dirs = try? fm.contentsOfDirectory(atPath: tasksDirectory.path) {
            for dir in dirs {
                // Skip UUID-format directories (already handled above) and hidden files
                if dir.hasPrefix(".") { continue }
                if dir.contains("-") && dir.count > 30 { continue } // UUID pattern

                let teamDir = tasksDirectory.appendingPathComponent(dir)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: teamDir.path, isDirectory: &isDir), isDir.boolValue else { continue }

                // Check if this team dir was modified recently (within last hour)
                if let attrs = try? fm.attributesOfItem(atPath: teamDir.path),
                   let mtime = attrs[.modificationDate] as? Date,
                   Date().timeIntervalSince(mtime) < 3600 {
                    allTasks.append(contentsOf: loadTasksFromDirectory(teamDir))
                }
            }
        }

        // Sort by ID numerically
        allTasks.sort { (Int($0.id) ?? 0) < (Int($1.id) ?? 0) }
        return allTasks
    }

    private static func loadTasksFromDirectory(_ dir: URL) -> [TaskEntry] {
        let fm = FileManager.default
        let decoder = JSONDecoder()

        guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else {
            print("[TaskLoader] Failed to list tasks directory: \(dir.lastPathComponent)")
            return []
        }

        var tasks: [TaskEntry] = []
        for file in files where file.hasSuffix(".json") {
            let filePath = dir.appendingPathComponent(file)
            guard let data = fm.contents(atPath: filePath.path) else { continue }

            do {
                let task = try decoder.decode(TaskEntry.self, from: data)
                tasks.append(task)
            } catch {
                print("[TaskLoader] Failed to decode \(file): \(error)")
            }
        }
        return tasks
    }
}
