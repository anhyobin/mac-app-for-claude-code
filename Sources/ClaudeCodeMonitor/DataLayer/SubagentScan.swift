import Foundation

/// Result of scanning one agent's JSONL transcript for usage stats.
///
/// Shared by ``SubagentLoader`` (flat `subagents/agent-*.jsonl`) and
/// ``WorkflowLoader`` (`subagents/workflows/{id}/agent-*.jsonl`) — both read
/// the identical assistant-turn JSONL format.
enum SubagentScan {

    struct Result: Sendable {
        var tokens = TokenUsage()
        var toolUseCount = 0
        var messageCount = 0
        var toolBreakdown: [String: Int] = [:]
        var skillCounts: [String: Int] = [:]
    }

    /// Scan an agent JSONL file. Files larger than 50MB are skipped (returns
    /// zeros) to bound per-refresh cost.
    static func scan(jsonlPath path: URL) -> Result {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
              let fileSize = attrs[.size] as? UInt64,
              fileSize <= 50 * 1024 * 1024 else {
            return Result()
        }
        guard let data = try? Data(contentsOf: path) else {
            return Result()
        }

        var out = Result()
        let lines = data.split(separator: UInt8(ascii: "\n"))
        for lineData in lines {
            let lineStr = String(decoding: lineData, as: UTF8.self)
            guard lineStr.contains("\"type\":\"assistant\"") else { continue }
            guard let entry = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let message = entry["message"] as? [String: Any] else { continue }

            out.messageCount += 1

            if let usage = message["usage"] as? [String: Any] {
                out.tokens.add(TokenUsage(
                    inputTokens: usage["input_tokens"] as? Int ?? 0,
                    outputTokens: usage["output_tokens"] as? Int ?? 0,
                    cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0,
                    cacheWriteTokens: usage["cache_creation_input_tokens"] as? Int ?? 0
                ))
            }

            if let content = message["content"] as? [[String: Any]] {
                for block in content where block["type"] as? String == "tool_use" {
                    out.toolUseCount += 1
                    if let name = block["name"] as? String {
                        out.toolBreakdown[name, default: 0] += 1
                        if name == "Skill",
                           let input = block["input"] as? [String: Any],
                           let skill = input["skill"] as? String {
                            out.skillCounts[skill, default: 0] += 1
                        }
                    }
                }
            }
        }
        return out
    }
}
