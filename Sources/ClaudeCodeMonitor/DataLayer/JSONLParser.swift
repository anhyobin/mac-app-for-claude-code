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
        var skillCounts: [String: Int] = [:]
        var thinkingBlockCount = 0

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

                // Extract model — overwrite on every assistant turn so the
                // final value reflects the most recent model, catching mid-
                // session `/model` swaps. Mirrors the last-turn rule used by
                // `mainLastTurnUsage`.
                if let m = message["model"] as? String {
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

                // Extract tool_use counts, Skill sub-tallies, and thinking
                // blocks in a single pass. When a tool_use names the "Skill"
                // tool, also tally by `input.skill` so the UI can surface
                // per-skill invocation counts.
                if let content = message["content"] as? [[String: Any]] {
                    for block in content {
                        switch block["type"] as? String {
                        case "tool_use":
                            if let name = block["name"] as? String {
                                toolCounts[name, default: 0] += 1
                                if name == "Skill",
                                   let input = block["input"] as? [String: Any],
                                   let skill = input["skill"] as? String {
                                    skillCounts[skill, default: 0] += 1
                                }
                            }
                        case "thinking":
                            thinkingBlockCount += 1
                        default:
                            break
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
            slug: slug,
            thinkingBlockCount: thinkingBlockCount,
            skillCounts: skillCounts
        )
    }

    // MARK: - Lightweight Token-Only Parsing

    /// Lightweight aggregate of tokens, thinking-block count, model name, and
    /// the *last assistant turn's* usage snapshot.
    ///
    /// `tokens` is the cumulative sum across all assistant turns — meaningful
    /// for "total usage" displays but NOT for context-window fullness
    /// (because `cache_read_input_tokens` is reported per-turn and accumulates
    /// across stable cache reads, which would multi-count window occupancy).
    ///
    /// `lastTurnUsage` is the raw usage block from the *most recent* assistant
    /// message. This is what should drive context-window ratios: it's a single
    /// point-in-time snapshot of what the model saw on its last request.
    /// `nil` when the session has no assistant messages yet.
    ///
    /// `truncated` indicates that the file exceeded the 50MB size cap and the
    /// stats are empty/stale. Callers can treat this as "unknown state" rather
    /// than "zero usage" to avoid misreporting a full window as empty.
    struct SessionQuickStats: Sendable {
        var tokens: TokenUsage
        var thinkingBlockCount: Int
        /// Raw model string from the most recent assistant message that
        /// reports one. Captures mid-session `/model` swaps.
        /// `nil` when the session has no assistant messages yet.
        var model: String?
        /// Snapshot of the usage block on the most recent assistant turn.
        /// Used to estimate current context-window occupancy without the
        /// per-turn accumulation pitfall of summed `cache_read_input_tokens`.
        var lastTurnUsage: TokenUsage?
        /// True when the source JSONL exceeded the max file size and was not
        /// parsed. Views should render an "unknown" state rather than "empty".
        var truncated: Bool
        /// Count of Skill tool invocations in this session keyed by skill
        /// name (plugin namespace preserved). Empty when the session has
        /// no Skill tool_use blocks or when parsing was skipped.
        var skillCounts: [String: Int]
        /// Most recent `/goal` status for this session. `nil` when the
        /// session has never had a goal installed, when the parse was
        /// truncated (>50MB cap), or when the file couldn't be read.
        /// The parser tracks only the latest start marker — if a session
        /// achieved goal A and then started goal B, only B is reported.
        var activeGoal: GoalStatus?
    }

    /// Extracts cumulative tokens, thinking-block count, model name, and the
    /// last assistant turn's usage snapshot in a single pass. Used by
    /// ``ClaudeDataStore`` to populate ``SessionExpandedData`` for active
    /// sessions, where all four values are needed per refresh.
    static func scanTokensAndThinking(at path: URL) -> SessionQuickStats {
        guard let (data, _) = readFileIfAllowed(at: path) else {
            // File missing, over 50MB, or unreadable. Surface as `truncated` so
            // the view layer doesn't misinterpret "no data" as "empty window".
            return SessionQuickStats(
                tokens: TokenUsage(),
                thinkingBlockCount: 0,
                model: nil,
                lastTurnUsage: nil,
                truncated: true,
                skillCounts: [:],
                activeGoal: nil
            )
        }

        let lines = data.split(separator: UInt8(ascii: "\n"))
        var tokens = TokenUsage()
        var thinkingBlockCount = 0
        var model: String?
        var lastTurnUsage: TokenUsage?
        var skillCounts: [String: Int] = [:]

        // Goal tracking state. We walk the file top-to-bottom; each time we
        // see a start marker (met:false, sentinel:true) we RESET the tracker
        // so the reported goal is always the most-recent one. `startIndex`
        // records the assistant-message count at the moment the start marker
        // was seen; subtracting that from the final count yields
        // `turnsElapsed`. `achievedAt` is stamped when a met:true shows up
        // AFTER the latest start marker — achievements for earlier goals are
        // ignored because the tracker was reset when the new start landed.
        var goalCondition: String?
        var goalStartedAt: Date?
        var goalStartIndexAssistant: Int = 0
        var goalAchievedAt: Date?
        var goalAchievedIndexAssistant: Int?

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFormatterNoFrac = ISO8601DateFormatter()
        isoFormatterNoFrac.formatOptions = [.withInternetDateTime]

        func parseDate(_ raw: String) -> Date? {
            isoFormatter.date(from: raw) ?? isoFormatterNoFrac.date(from: raw)
        }

        var assistantCount = 0

        for lineData in lines {
            let lineStr = String(decoding: lineData, as: UTF8.self)
            let isAssistant = lineStr.contains("\"type\":\"assistant\"")
            // `goal_status` events ride on attachment lines. Cheap string
            // guard keeps JSON decoding off the hot path for unrelated rows.
            let isAttachmentCandidate = !isAssistant
                && lineStr.contains("\"type\":\"attachment\"")
                && lineStr.contains("\"goal_status\"")
            guard isAssistant || isAttachmentCandidate else { continue }

            guard let entry = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            if isAssistant {
                assistantCount += 1
                guard let message = entry["message"] as? [String: Any] else { continue }

                if let m = message["model"] as? String {
                    model = m
                }

                if let usage = message["usage"] as? [String: Any] {
                    let turn = TokenUsage(
                        inputTokens: usage["input_tokens"] as? Int ?? 0,
                        outputTokens: usage["output_tokens"] as? Int ?? 0,
                        cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0,
                        cacheWriteTokens: usage["cache_creation_input_tokens"] as? Int ?? 0
                    )
                    tokens.add(turn)
                    // Overwrite on every assistant turn so the final value is the
                    // most recent one — this is the point-in-time window snapshot.
                    lastTurnUsage = turn
                }

                if let content = message["content"] as? [[String: Any]] {
                    for block in content {
                        switch block["type"] as? String {
                        case "tool_use":
                            // Only tally Skill invocations here — other tool counts
                            // are not needed for the active-session fast path.
                            if block["name"] as? String == "Skill",
                               let input = block["input"] as? [String: Any],
                               let skill = input["skill"] as? String {
                                skillCounts[skill, default: 0] += 1
                            }
                        case "thinking":
                            thinkingBlockCount += 1
                        default:
                            break
                        }
                    }
                }
            } else {
                // Attachment line carrying a goal_status event.
                guard let attachment = entry["attachment"] as? [String: Any],
                      attachment["type"] as? String == "goal_status" else { continue }

                let met = attachment["met"] as? Bool ?? false
                let sentinel = attachment["sentinel"] as? Bool ?? false
                let tsRaw = entry["timestamp"] as? String

                if !met && sentinel {
                    // New goal installed. Reset any prior tracker so the
                    // latest goal is the one we surface.
                    goalCondition = attachment["condition"] as? String ?? ""
                    goalStartedAt = tsRaw.flatMap(parseDate)
                    goalStartIndexAssistant = assistantCount
                    goalAchievedAt = nil
                    goalAchievedIndexAssistant = nil
                } else if met, goalStartedAt != nil, goalAchievedAt == nil {
                    // Achievement applies to the most recent start marker.
                    // Ignore `met:true` that appears before any start — it
                    // would be orphan data and shouldn't be surfaced.
                    goalAchievedAt = tsRaw.flatMap(parseDate)
                    goalAchievedIndexAssistant = assistantCount
                }
            }
        }

        let activeGoal: GoalStatus? = {
            guard let condition = goalCondition, let startedAt = goalStartedAt else {
                return nil
            }
            // For an active goal, turnsElapsed = total assistant messages
            // seen minus the count at the start marker. For an achieved
            // goal, we freeze the elapsed count at achievement time so the
            // "took N turns" figure doesn't keep growing.
            let endIndex = goalAchievedIndexAssistant ?? assistantCount
            let turns = max(0, endIndex - goalStartIndexAssistant)
            return GoalStatus(
                condition: condition,
                startedAt: startedAt,
                achievedAt: goalAchievedAt,
                turnsElapsed: turns
            )
        }()

        return SessionQuickStats(
            tokens: tokens,
            thinkingBlockCount: thinkingBlockCount,
            model: model,
            lastTurnUsage: lastTurnUsage,
            truncated: false,
            skillCounts: skillCounts,
            activeGoal: activeGoal
        )
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
              let fileSize = attrs[.size] as? UInt64 else {
            return nil
        }
        if fileSize > maxFileSize {
            // Oversize JSONLs almost certainly correspond to sessions with very
            // full context windows — the exact case where we MOST want an
            // accurate warning dot. Log once so operators can see we're
            // skipping, and let the caller surface `truncated: true` upstream.
            print("[JSONLParser] Skipping oversize file (\(fileSize) bytes > \(maxFileSize)): \(path.lastPathComponent)")
            return nil
        }
        guard let data = try? Data(contentsOf: path) else {
            print("[JSONLParser] Failed to read file: \(path.lastPathComponent)")
            return nil
        }
        return (data, fileSize)
    }
}
