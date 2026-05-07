import Foundation

/// Maximum context-window sizes per model family, keyed off the raw model string
/// emitted by the Claude API.
///
/// These values are used by ``SessionExpandedData/contextUsageRatio(model:)`` to
/// compute a "how full is the context window" ratio for the session row gauge.
///
/// Values as of 2026-05:
/// - Settings-based 1M detection: cross-references `~/.claude/settings.json` to
///   determine if the JSONL model is configured as a `[1m]` variant
/// - Opus 4.7 / Sonnet 4.7: 1M context (inherent, no settings needed)
/// - Opus 4.x / Sonnet 4.x (pre-4.7): 200K context
/// - Unknown models: 200K (safe conservative default so the gauge never
///   under-reports fullness for an unrecognized model)
///
/// Note: The JSONL API response only contains short model IDs (e.g., `claude-opus-4-6`)
/// which never include the `[1m]` suffix. Detection of 1M variants relies on
/// ``ClaudeSettingsReader`` cross-referencing the user's settings.json configuration.
enum ModelContextLimits {
    /// Returns the maximum context-window token count for the given raw model.
    ///
    /// Matching is case-insensitive and keyword-based. Priority order:
    /// 1. Settings-based detection — ``ClaudeSettingsReader/isOneMillionContext(for:)``
    ///    checks if the user's `~/.claude/settings.json` maps this model to a `[1m]` variant.
    /// 2. The 4.7 generation — inherently 1M without needing the suffix.
    /// 3. Broader "opus"/"sonnet-4" patterns — 200K models.
    ///
    /// Haiku is intentionally unlisted — every shipped Haiku version is 200K,
    /// which is also the safe default, so it falls through the final branch.
    /// Revisit if Haiku ever ships with an expanded window.
    static func maxContext(for rawModel: String) -> Int {
        let lower = rawModel.lowercased()
        // Cross-reference with ~/.claude/settings.json to detect [1m] variants.
        // The JSONL model field never contains [1m], so we must check settings.
        if ClaudeSettingsReader.isOneMillionContext(for: rawModel) {
            return 1_000_000
        }
        if lower.contains("opus-4-7") || lower.contains("sonnet-4-7") {
            return 1_000_000
        }
        if lower.contains("opus") || lower.contains("sonnet-4") {
            return 200_000
        }
        return 200_000 // safe default — never overestimate capacity
    }
}
