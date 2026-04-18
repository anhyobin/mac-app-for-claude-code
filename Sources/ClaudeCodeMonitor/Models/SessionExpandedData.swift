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

    /// Ratio (0.0–1.0+) of how full the context window is for the given model.
    ///
    /// Uses the main session's tokens only — subagents run in their own windows,
    /// so including their tokens here would overstate the main session's fullness.
    /// The numerator is `inputTokens + outputTokens + cacheReadTokens`:
    /// - `cache_read_input_tokens` DOES occupy the window (it's the history Anthropic
    ///   replays via cache).
    /// - `cache_creation_input_tokens` is excluded because on the assistant turn
    ///   where a cache block is *first written*, those tokens are also reported
    ///   under `input_tokens`, so adding them would double-count.
    ///
    /// Returns `nil` when the model is unknown (`model == nil`), so the view layer
    /// can hide the gauge rather than render a misleading bar.
    ///
    /// The ratio may exceed 1.0 near session end as cache-read accumulates; the
    /// view layer should `min(ratio, 1.0)` when drawing a progress bar but may
    /// show the raw value in a tooltip.
    func contextUsageRatio(model: String?) -> Double? {
        guard let model else { return nil }
        let limit = ModelContextLimits.maxContext(for: model)
        guard limit > 0 else { return nil }

        let used = mainTokens.inputTokens
                 + mainTokens.outputTokens
                 + mainTokens.cacheReadTokens
        return Double(used) / Double(limit)
    }
}
