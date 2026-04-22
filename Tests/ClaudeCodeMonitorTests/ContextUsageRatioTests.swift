import XCTest
@testable import ClaudeCodeMonitor

// Build note: `swift test` requires the Xcode SDK (XCTest is not in the
// Command Line Tools SDK). On machines with only CLT, `swift build` and
// `bash scripts/build-app.sh` still succeed because test targets are not
// built by those commands. Run these tests via Xcode or on a machine
// with full Xcode installed.

/// Regression guard for the contextUsageRatio calculation, which previously
/// multi-counted `cache_read_input_tokens` across turns because it summed
/// every turn's usage. The fix: use ONLY the last assistant turn's snapshot.
final class ContextUsageRatioTests: XCTestCase {

    private func makeExpanded(
        lastTurn: TokenUsage?,
        model: String? = "claude-opus-4-7-20260315"
    ) -> SessionExpandedData {
        SessionExpandedData(
            agents: [],
            tasks: [],
            mainTokens: TokenUsage(), // intentionally unused by contextUsageRatio
            totalTokens: TokenUsage(),
            mainJSONLMtime: nil,
            mainThinkingBlockCount: 0,
            mainModel: model,
            mainLastTurnUsage: lastTurn,
            mainTruncated: false,
            mainSkillCounts: [:]
        )
    }

    func testNilModelReturnsNil() {
        let data = makeExpanded(
            lastTurn: TokenUsage(inputTokens: 1000, outputTokens: 500),
            model: "claude-opus-4-7-20260315"
        )
        XCTAssertNil(data.contextUsageRatio(model: nil))
    }

    func testNilLastTurnReturnsNil() {
        let data = makeExpanded(lastTurn: nil)
        XCTAssertNil(data.contextUsageRatio(model: "claude-opus-4-7-20260315"))
    }

    /// Simulates a 10-turn session where cache_read stays at 50K every turn.
    /// If the old code summed across turns, it would compute (50K * 10) / 200K = 2.5
    /// which would trip the 0.95 warning threshold falsely.
    /// The fix: contextUsageRatio reads ONLY the last turn, so the ratio is
    /// based on the final snapshot (2K input + 50K cache_read), giving 52K/200K = 0.26.
    func testRatioUsesLastTurnOnly() {
        let lastTurn = TokenUsage(
            inputTokens: 2_000,
            outputTokens: 500,
            cacheReadTokens: 50_000,
            cacheWriteTokens: 0
        )
        let data = makeExpanded(lastTurn: lastTurn, model: "claude-opus-4-5-20260101")
        let ratio = data.contextUsageRatio(model: "claude-opus-4-5-20260101")
        XCTAssertNotNil(ratio)
        XCTAssertLessThan(ratio!, 0.30)
        XCTAssertGreaterThanOrEqual(ratio!, 0.25)
    }

    /// 500K tokens would be 2.5x the 200K window but only 0.5x the 1M window.
    /// Correct behavior for a 4.7 model: this returns 0.5.
    func testOpus47UsesOneMillionLimit() {
        let lastTurn = TokenUsage(
            inputTokens: 500_000,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheWriteTokens: 0
        )
        let data = makeExpanded(lastTurn: lastTurn, model: "claude-opus-4-7-20260315")
        let ratio = data.contextUsageRatio(model: "claude-opus-4-7-20260315")
        XCTAssertNotNil(ratio)
        XCTAssertEqual(ratio!, 0.5, accuracy: 0.001)
    }

    /// A turn that writes 100K to cache should count that toward window occupancy.
    func testCacheCreationCounted() {
        let lastTurn = TokenUsage(
            inputTokens: 0,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheWriteTokens: 100_000
        )
        let data = makeExpanded(lastTurn: lastTurn, model: "claude-opus-4-5-20260101")
        let ratio = data.contextUsageRatio(model: "claude-opus-4-5-20260101")
        XCTAssertNotNil(ratio)
        XCTAssertEqual(ratio!, 0.5, accuracy: 0.001)
    }

    func testWarningThresholdTrips() {
        let lastTurn = TokenUsage(
            inputTokens: 90_000,
            outputTokens: 0,
            cacheReadTokens: 100_000,
            cacheWriteTokens: 0
        )
        let data = makeExpanded(lastTurn: lastTurn, model: "claude-opus-4-6-20260101")
        let ratio = data.contextUsageRatio(model: "claude-opus-4-6-20260101")
        XCTAssertNotNil(ratio)
        XCTAssertGreaterThanOrEqual(ratio!, 0.95)
    }
}

final class ModelContextLimitsTests: XCTestCase {
    func testOpus47IsOneMillion() {
        XCTAssertEqual(ModelContextLimits.maxContext(for: "claude-opus-4-7-20260315"), 1_000_000)
    }

    func testSonnet47IsOneMillion() {
        XCTAssertEqual(ModelContextLimits.maxContext(for: "claude-sonnet-4-7-20260315"), 1_000_000)
    }

    func testOpus46FallsBackTo200K() {
        XCTAssertEqual(ModelContextLimits.maxContext(for: "claude-opus-4-6-20260101"), 200_000)
    }

    /// Haiku is intentionally unlisted; 200K default is correct for current versions.
    func testHaikuFallsThrough() {
        XCTAssertEqual(ModelContextLimits.maxContext(for: "claude-haiku-4-7-20260101"), 200_000)
        XCTAssertEqual(ModelContextLimits.maxContext(for: "claude-haiku-3-5-20240307"), 200_000)
    }

    func testUnknownReturnsDefault() {
        XCTAssertEqual(ModelContextLimits.maxContext(for: "future-model-xyz"), 200_000)
    }
}

final class ModelFamilyTests: XCTestCase {
    func testOpus() {
        XCTAssertEqual(ModelNameFormatter.family(from: "claude-opus-4-7-20260315"), .opus)
    }

    func testSonnet() {
        XCTAssertEqual(ModelNameFormatter.family(from: "claude-sonnet-4-6-20260101"), .sonnet)
    }

    func testHaiku() {
        XCTAssertEqual(ModelNameFormatter.family(from: "claude-haiku-4-5-20250101"), .haiku)
    }

    func testUnknown() {
        XCTAssertEqual(ModelNameFormatter.family(from: "gpt-4"), .unknown)
    }

    /// Regression guard: if the ordering in knownModels ever flips, this
    /// test surfaces it before it reaches users.
    func testFourSevenMatchesBeforeFourSix() {
        XCTAssertEqual(ModelNameFormatter.displayName(from: "claude-opus-4-7-20260315"), "Opus 4.7")
        XCTAssertEqual(ModelNameFormatter.displayName(from: "claude-opus-4-6-20260101"), "Opus 4.6")
    }
}
