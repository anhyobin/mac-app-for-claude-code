import Foundation

enum JSONLParser {
    private static let maxFileSize: UInt64 = 50 * 1024 * 1024 // 50MB

    static func scanSessionSummary(at path: URL) -> SessionLog? {
        guard let (data, _) = readFileIfAllowed(at: path) else { return nil }

        let lines = data.split(separator: UInt8(ascii: "\n"))

        var sessionId: String?
        var projectPath: String?
        var slug: String?
        var model: String?
        var startTime: Date?
        var endTime: Date?
        var userMessageCount = 0
        var assistantMessageCount = 0
        var tokens = TokenUsage()
        var toolCounts: [String: Int] = [:]

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let isoFormatterNoFrac = ISO8601DateFormatter()
        isoFormatterNoFrac.formatOptions = [.withInternetDateTime]

        for lineData in lines {
            let lineStr = String(decoding: lineData, as: UTF8.self)

            let isUser = lineStr.contains("\"type\":\"user\"")
            let isAssistant = lineStr.contains("\"type\":\"assistant\"")
            guard isUser || isAssistant else { continue }

            guard let entry = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            // Extract timestamp
            if let ts = entry["timestamp"] as? String {
                let date = isoFormatter.date(from: ts) ?? isoFormatterNoFrac.date(from: ts)
                if let date {
                    if startTime == nil { startTime = date }
                    endTime = date
                }
            }

            // Extract sessionId, cwd, slug (from first matching entry)
            if sessionId == nil, let sid = entry["sessionId"] as? String {
                sessionId = sid
            }
            if projectPath == nil, let cwd = entry["cwd"] as? String {
                projectPath = cwd
            }
            if slug == nil, let s = entry["slug"] as? String {
                slug = s
            }

            if isUser {
                // Skip meta messages
                if entry["isMeta"] as? Bool == true { continue }
                userMessageCount += 1
            }

            if isAssistant {
                assistantMessageCount += 1
                guard let message = entry["message"] as? [String: Any] else { continue }

                // Extract model
                if model == nil, let m = message["model"] as? String {
                    model = m
                }

                // Extract usage
                if let usage = message["usage"] as? [String: Any] {
                    let input = usage["input_tokens"] as? Int ?? 0
                    let output = usage["output_tokens"] as? Int ?? 0
                    let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
                    let cacheWrite = usage["cache_creation_input_tokens"] as? Int ?? 0
                    tokens.add(TokenUsage(
                        inputTokens: input,
                        outputTokens: output,
                        cacheReadTokens: cacheRead,
                        cacheWriteTokens: cacheWrite
                    ))
                }

                // Extract tool_use counts
                if let content = message["content"] as? [[String: Any]] {
                    for block in content {
                        if block["type"] as? String == "tool_use",
                           let name = block["name"] as? String {
                            toolCounts[name, default: 0] += 1
                        }
                    }
                }
            }
        }

        guard let sid = sessionId else { return nil }

        let duration: TimeInterval?
        if let s = startTime, let e = endTime {
            duration = e.timeIntervalSince(s)
        } else {
            duration = nil
        }

        let resolvedPath = projectPath ?? path.deletingLastPathComponent().lastPathComponent
        return SessionLog(
            id: sid,
            projectPath: resolvedPath,
            projectName: PathDecoder.projectName(from: resolvedPath),
            startTime: startTime,
            endTime: endTime,
            duration: duration,
            userMessageCount: userMessageCount,
            assistantMessageCount: assistantMessageCount,
            tokens: tokens,
            toolCounts: toolCounts,
            model: model,
            slug: slug
        )
    }

    // MARK: - Lightweight Token-Only Parsing

    /// Extracts only token usage from a JSONL file — much faster than full scanSessionSummary.
    static func scanTokensOnly(at path: URL) -> TokenUsage {
        guard let (data, _) = readFileIfAllowed(at: path) else { return TokenUsage() }

        let lines = data.split(separator: UInt8(ascii: "\n"))
        var tokens = TokenUsage()

        for lineData in lines {
            let lineStr = String(decoding: lineData, as: UTF8.self)
            guard lineStr.contains("\"type\":\"assistant\"") else { continue }

            guard let entry = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let message = entry["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { continue }

            tokens.add(TokenUsage(
                inputTokens: usage["input_tokens"] as? Int ?? 0,
                outputTokens: usage["output_tokens"] as? Int ?? 0,
                cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0,
                cacheWriteTokens: usage["cache_creation_input_tokens"] as? Int ?? 0
            ))
        }

        return tokens
    }

    // MARK: - Agent Detail Parsing

    static func parseRecentMessages(at path: URL, count: Int = 10) -> [ConversationEntry] {
        guard let (data, _) = readFileIfAllowed(at: path) else { return [] }

        let lines = data.split(separator: UInt8(ascii: "\n"))

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFormatterNoFrac = ISO8601DateFormatter()
        isoFormatterNoFrac.formatOptions = [.withInternetDateTime]

        var entries: [ConversationEntry] = []

        for lineData in lines {
            let lineStr = String(decoding: lineData, as: UTF8.self)
            let isUser = lineStr.contains("\"type\":\"user\"")
            let isAssistant = lineStr.contains("\"type\":\"assistant\"")
            guard isUser || isAssistant else { continue }

            guard let entry = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            if isUser, entry["isMeta"] as? Bool == true { continue }

            let role = isUser ? "user" : "assistant"
            let uuid = entry["uuid"] as? String ?? UUID().uuidString

            var timestamp: Date?
            if let ts = entry["timestamp"] as? String {
                timestamp = isoFormatter.date(from: ts) ?? isoFormatterNoFrac.date(from: ts)
            }

            var contentPreview = ""
            var toolUses: [String] = []
            var toolResultCount = 0

            if let message = entry["message"] as? [String: Any] {
                if let content = message["content"] as? String {
                    contentPreview = String(content.prefix(100))
                } else if let content = message["content"] as? [[String: Any]] {
                    for block in content {
                        let blockType = block["type"] as? String ?? ""
                        if blockType == "text", let text = block["text"] as? String, contentPreview.isEmpty {
                            contentPreview = String(text.prefix(100))
                        } else if blockType == "thinking", let text = block["thinking"] as? String, contentPreview.isEmpty {
                            contentPreview = String(text.prefix(100))
                        } else if blockType == "tool_use", let name = block["name"] as? String {
                            toolUses.append(name)
                        } else if blockType == "tool_result" {
                            toolResultCount += 1
                            if contentPreview.isEmpty {
                                if let resultText = block["content"] as? String {
                                    contentPreview = String(resultText.prefix(100))
                                } else if let resultArray = block["content"] as? [[String: Any]] {
                                    for item in resultArray {
                                        if item["type"] as? String == "text",
                                           let text = item["text"] as? String {
                                            contentPreview = String(text.prefix(100))
                                            break
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            entries.append(ConversationEntry(
                id: uuid,
                role: role,
                timestamp: timestamp,
                contentPreview: contentPreview,
                toolUses: toolUses,
                toolResultCount: toolResultCount
            ))
        }

        return Array(entries.suffix(count))
    }

    static func extractFileChanges(at path: URL) -> [FileChange] {
        let fileTools: Set<String> = ["Edit", "Write", "NotebookEdit"]

        guard let (data, _) = readFileIfAllowed(at: path) else { return [] }

        let lines = data.split(separator: UInt8(ascii: "\n"))

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFormatterNoFrac = ISO8601DateFormatter()
        isoFormatterNoFrac.formatOptions = [.withInternetDateTime]

        // Track latest change per file path
        var latestByPath: [String: FileChange] = [:]

        for lineData in lines {
            let lineStr = String(decoding: lineData, as: UTF8.self)
            guard lineStr.contains("\"type\":\"assistant\"") else { continue }

            guard let entry = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let message = entry["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { continue }

            var timestamp: Date?
            if let ts = entry["timestamp"] as? String {
                timestamp = isoFormatter.date(from: ts) ?? isoFormatterNoFrac.date(from: ts)
            }

            for block in content {
                guard block["type"] as? String == "tool_use",
                      let name = block["name"] as? String,
                      fileTools.contains(name),
                      let input = block["input"] as? [String: Any],
                      let filePath = input["file_path"] as? String else { continue }

                latestByPath[filePath] = FileChange(
                    filePath: filePath,
                    toolName: name,
                    timestamp: timestamp
                )
            }
        }

        return latestByPath.values.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
    }

    // MARK: - Helpers

    private static func readFileIfAllowed(at path: URL) -> (Data, UInt64)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
              let fileSize = attrs[.size] as? UInt64,
              fileSize <= maxFileSize else {
            return nil
        }
        guard let data = try? Data(contentsOf: path) else {
            print("[JSONLParser] Failed to read file: \(path.lastPathComponent)")
            return nil
        }
        return (data, fileSize)
    }
}
