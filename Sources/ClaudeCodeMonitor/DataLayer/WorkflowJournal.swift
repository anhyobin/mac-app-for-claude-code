import Foundation

/// Parses a workflow's `journal.jsonl` into a running/complete summary.
///
/// The journal appends one `{"type":"started","agentId":...}` per agent
/// launch and one `{"type":"result","agentId":...}` per completion. An agent
/// that has `started` but no `result` is still executing — this is the
/// primary signal for "workflow is running", because `workflows/{id}.json`
/// is only written at completion and can't be relied on mid-run.
enum WorkflowJournal {

    struct Summary: Sendable, Equatable {
        /// All agentIds that have a `started` event, in first-seen order.
        let startedAgentIds: [String]
        /// agentIds with `started` but no matching `result`, in first-seen order.
        let unfinishedAgentIds: [String]

        var hasUnfinishedAgents: Bool { !unfinishedAgentIds.isEmpty }

        /// Distinct agents that have launched. Live denominator for "M/N done".
        var startedCount: Int { startedAgentIds.count }
        /// Agents that launched and produced a `result`. Live numerator.
        var finishedCount: Int { startedAgentIds.count - unfinishedAgentIds.count }
    }

    /// Parse raw journal text (newline-delimited JSON).
    static func parse(text: String) -> Summary {
        var startedOrder: [String] = []
        var started: Set<String> = []
        var resulted: Set<String> = []

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, let data = line.data(using: .utf8) else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = obj["type"] as? String,
                  let agentId = obj["agentId"] as? String else { continue }

            switch type {
            case "started":
                if !started.contains(agentId) {
                    started.insert(agentId)
                    startedOrder.append(agentId)
                }
            case "result":
                resulted.insert(agentId)
            default:
                break
            }
        }

        let unfinished = startedOrder.filter { !resulted.contains($0) }
        return Summary(startedAgentIds: startedOrder, unfinishedAgentIds: unfinished)
    }

    /// Convenience: parse a journal file at `url`. Returns an empty summary
    /// if the file is missing or unreadable (workflow with no journal yet).
    static func parse(fileAt url: URL) -> Summary {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return Summary(startedAgentIds: [], unfinishedAgentIds: [])
        }
        return parse(text: text)
    }
}
