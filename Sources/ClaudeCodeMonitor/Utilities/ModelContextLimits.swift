import Foundation

/// Maximum context-window sizes per model family, keyed off the raw model string
/// emitted by the Claude API.
///
/// These values are used by ``SessionExpandedData/contextUsageRatio(model:)`` to
/// compute a "how full is the context window" ratio for the session row gauge.
///
/// Values as of 2026-04:
/// - Opus 4.7 / Sonnet 4.7: 1M context
/// - Opus 4.x / Sonnet 4.x (pre-4.7): 200K context
/// - Unknown models: 200K (safe conservative default so the gauge never
///   under-reports fullness for an unrecognized model)
enum ModelContextLimits {
    /// Returns the maximum context-window token count for the given raw model.
    ///
    /// Matching is case-insensitive and keyword-based. The 4.7 generation must
    /// be checked before the broader "opus"/"sonnet-4" patterns so that a
    /// 1M-context 4.7 model isn't misclassified as a 200K model.
    static func maxContext(for rawModel: String) -> Int {
        let lower = rawModel.lowercased()
        if lower.contains("opus-4-7") || lower.contains("sonnet-4-7") {
            return 1_000_000
        }
        if lower.contains("opus") || lower.contains("sonnet-4") {
            return 200_000
        }
        return 200_000 // safe default — never overestimate capacity
    }
}
