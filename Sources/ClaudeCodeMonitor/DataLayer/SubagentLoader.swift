import Foundation

enum SubagentLoader {
    private static let projectsDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }()

    static func loadAgents(sessionId: String, projectPath: String,
                           previousAgents: [SubagentInfo]? = nil) -> [SubagentInfo] {
        let fm = FileManager.default

        // Find the encoded project directory
        let encodedPath = PathDecoder.encodedProjectPath(from: projectPath)

        let subagentsDir = projectsDirectory
            .appendingPathComponent(encodedPath)
            .appendingPathComponent(sessionId)
            .appendingPathComponent("subagents")

        guard fm.fileExists(atPath: subagentsDir.path) else { return [] }

        guard let files = try? fm.contentsOfDirectory(atPath: subagentsDir.path) else {
            print("[SubagentLoader] Failed to list subagents directory")
            return []
        }

        let jsonlFiles = files.filter { $0.hasSuffix(".jsonl") && $0.hasPrefix("agent-") }
        var agents: [SubagentInfo] = []
        let decoder = JSONDecoder()

        // Index previous agents by id for O(1) lookup
        let previousById: [String: SubagentInfo]? = previousAgents.map {
            Dictionary(uniqueKeysWithValues: $0.map { ($0.id, $0) })
        }

        for jsonlFile in jsonlFiles {
            // Extract agent hash from filename: agent-{hash}.jsonl
            let hash = String(jsonlFile.dropFirst("agent-".count).dropLast(".jsonl".count))
            let jsonlPath = subagentsDir.appendingPathComponent(jsonlFile)

            // Get file modification time for active/inactive detection
            let mtime: Date? = {
                guard let attrs = try? fm.attributesOfItem(atPath: jsonlPath.path) else { return nil }
                return attrs[.modificationDate] as? Date
            }()

            // Reuse cached agent if mtime unchanged (skip expensive JSONL re-parse)
            if let prev = previousById?[hash],
               let prevMtime = prev.lastActivity,
               let curMtime = mtime,
               prevMtime == curMtime {
                agents.append(prev)
                continue
            }

            // Load meta.json
            let metaFile = "agent-\(hash).meta.json"
            let metaPath = subagentsDir.appendingPathComponent(metaFile)
            var agentType = "unknown"
            var description: String?

            if let metaData = fm.contents(atPath: metaPath.path),
               let meta = try? decoder.decode(SubagentMeta.self, from: metaData) {
                agentType = meta.agentType
                description = meta.description
            }

            // Parse JSONL for tokens and tool counts
            let (tokens, toolUseCount, messageCount, toolBreakdown, skillCounts) = scanAgentJSONL(at: jsonlPath)

            agents.append(SubagentInfo(
                id: hash,
                agentType: agentType,
                description: description,
                tokens: tokens,
                toolUseCount: toolUseCount,
                messageCount: messageCount,
                toolBreakdown: toolBreakdown,
                skillCounts: skillCounts,
                lastActivity: mtime
            ))
        }

        // Sort: active first, then by most recent activity, then by token usage
        agents.sort { a, b in
            if a.isActive != b.isActive { return a.isActive }
            if let aTime = a.lastActivity, let bTime = b.lastActivity, aTime != bTime {
                return aTime > bTime
            }
            return a.tokens.total > b.tokens.total
        }
        return agents
    }

    private static func scanAgentJSONL(at path: URL) -> (TokenUsage, Int, Int, [String: Int], [String: Int]) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
              let fileSize = attrs[.size] as? UInt64,
              fileSize <= 50 * 1024 * 1024 else {
            return (TokenUsage(), 0, 0, [:], [:])
        }

        guard let data = try? Data(contentsOf: path) else {
            print("[SubagentLoader] Failed to read: \(path.lastPathComponent)")
            return (TokenUsage(), 0, 0, [:], [:])
        }

        let lines = data.split(separator: UInt8(ascii: "\n"))
        var tokens = TokenUsage()
        var toolUseCount = 0
        var messageCount = 0
        var toolBreakdown: [String: Int] = [:]
        var skillCounts: [String: Int] = [:]

        for lineData in lines {
            let lineStr = String(decoding: lineData, as: UTF8.self)
            guard lineStr.contains("\"type\":\"assistant\"") else { continue }

            guard let entry = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let message = entry["message"] as? [String: Any] else { continue }

            messageCount += 1

            if let usage = message["usage"] as? [String: Any] {
                tokens.add(TokenUsage(
                    inputTokens: usage["input_tokens"] as? Int ?? 0,
                    outputTokens: usage["output_tokens"] as? Int ?? 0,
                    cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0,
                    cacheWriteTokens: usage["cache_creation_input_tokens"] as? Int ?? 0
                ))
            }

            if let content = message["content"] as? [[String: Any]] {
                for block in content where block["type"] as? String == "tool_use" {
                    toolUseCount += 1
                    if let name = block["name"] as? String {
                        toolBreakdown[name, default: 0] += 1
                        if name == "Skill",
                           let input = block["input"] as? [String: Any],
                           let skill = input["skill"] as? String {
                            skillCounts[skill, default: 0] += 1
                        }
                    }
                }
            }
        }

        return (tokens, toolUseCount, messageCount, toolBreakdown, skillCounts)
    }
}
