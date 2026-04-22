import Foundation

struct SessionExpandedData: Sendable {
    let agents: [SubagentInfo]
    let tasks: [TaskEntry]
    let mainTokens: TokenUsage
    let totalTokens: TokenUsage
    let mainJSONLMtime: Date?
    /// Extended-thinking blocks emitted by the main session's assistant.
    ///
    /// Counted only from the main session JSONL — subagent thinking blocks are
    /// intentionally excluded for v0.2 because the UI surface is the session row,
    /// not the aggregate. Call sites should treat this as "main session only".
    let mainThinkingBlockCount: Int
    /// Raw model string for the main session (e.g. `claude-opus-4-7-20260315`).
    ///
    /// Pulled from the first assistant message's `model` field. `nil` when the
    /// session has no assistant turns yet, in which case context-window gauges
    /// and model badges should be hidden.
    let mainModel: String?
    /// Usage snapshot from the most recent assistant turn in the main session.
    ///
    /// Unlike `mainTokens` (which sums *every* turn's usage, inflating
    /// cache_read for sessions that reuse a stable cache across many turns),
    /// this is a point-in-time view of what the model saw on its last request.
    /// This is the correct numerator source for context-window fullness.
    /// `nil` when the session has no assistant turns yet.
    let mainLastTurnUsage: TokenUsage?
    /// True when the source JSONL was larger than the parser's size cap and
    /// could not be read. Views should render "unknown" rather than "empty".
    let mainTruncated: Bool
    /// Count of Skill tool invocations in the main session JSONL only,
    /// keyed by the invoked skill name (namespace preserved).
    ///
    /// This is the "main session" slice — subagent skill calls are tracked
    /// separately on each ``SubagentInfo`` and aggregated into
    /// ``totalSkillCounts``.
    let mainSkillCounts: [String: Int]

    /// Session-wide Skill invocation totals = main + every subagent (active
    /// AND completed). The view layer binds to this so that skill calls
    /// made by subagents remain visible after the agents drop off the
    /// active list.
    var totalSkillCounts: [String: Int] {
        var totals = mainSkillCounts
        for agent in agents {
            for (skill, count) in agent.skillCounts {
                totals[skill, default: 0] += count
            }
        }
        return totals
    }

    /// Ratio (0.0–1.0+) of how full the context window is for the given model.
    ///
    /// Uses the main session's **last assistant turn** as the window snapshot:
    /// `input_tokens + cache_read_input_tokens + cache_creation_input_tokens`.
    /// This intentionally mirrors what the model saw on its most recent
    /// request — summing usage across turns would multi-count cache reads
    /// that remain stable across a long session, causing warning-threshold
    /// false positives.
    ///
    /// Rationale for the three components:
    /// - `input_tokens`: the non-cached prompt prefix for this turn.
    /// - `cache_read_input_tokens`: prompt prefix served from cache. Still
    ///   occupies the window even though it was billed cheaply.
    /// - `cache_creation_input_tokens`: prompt prefix written to cache this
    ///   turn. Occupies the window for subsequent requests. On the creation
    ///   turn itself it may overlap with `input_tokens` depending on API
    ///   version, but including it is the conservative (larger) choice, and
    ///   we'd rather over-warn than under-warn on window saturation.
    ///
    /// Returns `nil` when either the model is unknown or no assistant turn
    /// has been observed yet (so no snapshot is available). The view layer
    /// should hide the gauge in that case.
    ///
    /// The ratio may exceed 1.0 in edge cases (Anthropic has occasionally
    /// permitted slight overages); the view layer should `min(ratio, 1.0)`
    /// when drawing a progress bar but may show the raw value in a tooltip.
    func contextUsageRatio(model: String?) -> Double? {
        guard let model else { return nil }
        guard let snapshot = mainLastTurnUsage else { return nil }
        let limit = ModelContextLimits.maxContext(for: model)
        guard limit > 0 else { return nil }

        let windowTokens = snapshot.inputTokens
                         + snapshot.cacheReadTokens
                         + snapshot.cacheWriteTokens
        return Double(windowTokens) / Double(limit)
    }
}
