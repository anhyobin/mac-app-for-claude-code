import Foundation

enum PathDecoder {
    static func projectName(from cwd: String) -> String {
        let url = URL(fileURLWithPath: cwd)
        let name = url.lastPathComponent
        return name.isEmpty ? cwd : name
    }

    /// Encodes a project path to the directory name format used by Claude CLI.
    static func encodedProjectPath(from projectPath: String) -> String {
        projectPath
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }
}
