import XCTest
@testable import ClaudeCodeMonitor

/// Verifies JSONLParser's handling of the `/goal` attachment schema:
///   - `attachment.type == "goal_status"` with `met:false, sentinel:true`
///     is the start marker (condition + timestamp).
///   - `met:true` after a start marker is the achievement marker.
///   - `turnsElapsed` = assistant messages between the start marker and
///     the end of file (or the achievement marker).
///   - When a session has multiple goals, only the most recent one is
///     surfaced.
final class GoalStatusParsingTests: XCTestCase {

    private func writeTempJSONL(_ lines: [String]) throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
        let url = tmpDir.appendingPathComponent("goal-test-\(UUID().uuidString).jsonl")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // Minimal assistant-message line used to drive `turnsElapsed` counting.
    private func assistantLine(ts: String) -> String {
        #"{"type":"assistant","timestamp":"\#(ts)","message":{"model":"claude-opus-4-7-20260315","content":[]}}"#
    }

    private func goalStartLine(ts: String, condition: String, uuid: String = UUID().uuidString) -> String {
        // Match the real schema observed in JSONL: top-level `type:"attachment"`,
        // nested `attachment.type:"goal_status"`, `met:false`, `sentinel:true`.
        let escaped = condition.replacingOccurrences(of: "\"", with: "\\\"")
        return #"{"type":"attachment","uuid":"\#(uuid)","timestamp":"\#(ts)","attachment":{"type":"goal_status","met":false,"sentinel":true,"condition":"\#(escaped)"}}"#
    }

    private func goalAchievedLine(ts: String, uuid: String = UUID().uuidString) -> String {
        #"{"type":"attachment","uuid":"\#(uuid)","timestamp":"\#(ts)","attachment":{"type":"goal_status","met":true,"sentinel":true,"condition":""}}"#
    }

    func testNoGoalReturnsNil() throws {
        let url = try writeTempJSONL([
            assistantLine(ts: "2026-05-13T10:00:00.000Z"),
            assistantLine(ts: "2026-05-13T10:01:00.000Z")
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let stats = JSONLParser.scanTokensAndThinking(at: url)
        XCTAssertNil(stats.activeGoal)
    }

    func testActiveGoalCapturesConditionAndTurns() throws {
        let url = try writeTempJSONL([
            assistantLine(ts: "2026-05-13T10:00:00.000Z"),
            goalStartLine(ts: "2026-05-13T10:01:00.000Z", condition: "add caching"),
            assistantLine(ts: "2026-05-13T10:02:00.000Z"),
            assistantLine(ts: "2026-05-13T10:03:00.000Z"),
            assistantLine(ts: "2026-05-13T10:04:00.000Z")
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let stats = JSONLParser.scanTokensAndThinking(at: url)
        let goal = try XCTUnwrap(stats.activeGoal)
        XCTAssertEqual(goal.condition, "add caching")
        XCTAssertTrue(goal.isActive)
        XCTAssertNil(goal.achievedAt)
        // Three assistant messages come after the start marker.
        XCTAssertEqual(goal.turnsElapsed, 3)
    }

    func testAchievedGoalSetsAchievedAtAndFreezesTurns() throws {
        let url = try writeTempJSONL([
            goalStartLine(ts: "2026-05-13T10:00:00.000Z", condition: "ship feature"),
            assistantLine(ts: "2026-05-13T10:01:00.000Z"),
            assistantLine(ts: "2026-05-13T10:02:00.000Z"),
            goalAchievedLine(ts: "2026-05-13T10:03:00.000Z"),
            // Post-achievement assistant messages must NOT inflate turnsElapsed.
            assistantLine(ts: "2026-05-13T10:04:00.000Z"),
            assistantLine(ts: "2026-05-13T10:05:00.000Z")
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let stats = JSONLParser.scanTokensAndThinking(at: url)
        let goal = try XCTUnwrap(stats.activeGoal)
        XCTAssertFalse(goal.isActive)
        XCTAssertNotNil(goal.achievedAt)
        XCTAssertEqual(goal.turnsElapsed, 2)
    }

    func testMostRecentGoalOverridesEarlierOne() throws {
        // Old goal, achieved. Then a new goal installed — we should surface
        // the new one with a fresh `isActive: true` state.
        let url = try writeTempJSONL([
            goalStartLine(ts: "2026-05-13T09:00:00.000Z", condition: "old goal"),
            assistantLine(ts: "2026-05-13T09:01:00.000Z"),
            goalAchievedLine(ts: "2026-05-13T09:02:00.000Z"),
            assistantLine(ts: "2026-05-13T09:30:00.000Z"),
            goalStartLine(ts: "2026-05-13T10:00:00.000Z", condition: "new goal"),
            assistantLine(ts: "2026-05-13T10:01:00.000Z"),
            assistantLine(ts: "2026-05-13T10:02:00.000Z")
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let stats = JSONLParser.scanTokensAndThinking(at: url)
        let goal = try XCTUnwrap(stats.activeGoal)
        XCTAssertEqual(goal.condition, "new goal")
        XCTAssertTrue(goal.isActive)
        XCTAssertEqual(goal.turnsElapsed, 2)
    }

    func testMultilineKoreanConditionPreserved() throws {
        // Real-world conditions observed in JSONL often contain Korean + long
        // text. JSON encoding takes care of newlines via \n — we don't use
        // them in the test body because JSON strings can't have raw newlines.
        let condition = "데모 실행하면 우측에 메트릭이 보여지는데 표시가 안됨. 실시간성을 높여줘."
        let url = try writeTempJSONL([
            goalStartLine(ts: "2026-05-13T10:00:00.000Z", condition: condition),
            assistantLine(ts: "2026-05-13T10:01:00.000Z")
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let stats = JSONLParser.scanTokensAndThinking(at: url)
        let goal = try XCTUnwrap(stats.activeGoal)
        XCTAssertEqual(goal.condition, condition)
    }

    func testTruncatedFileReturnsNilGoal() {
        // Point at a non-existent path — readFileIfAllowed returns nil, so
        // the parser surfaces `truncated: true` with no goal.
        let url = URL(fileURLWithPath: "/nonexistent/path/to/session.jsonl")
        let stats = JSONLParser.scanTokensAndThinking(at: url)
        XCTAssertTrue(stats.truncated)
        XCTAssertNil(stats.activeGoal)
    }

    /// Integration-style check against the real JSONL that contains a goal
    /// event. Skipped when the file is missing (CI/other machines) — this
    /// is a developer-machine sanity check, not a hard CI gate.
    func testRealWorldLeaderboardSession() throws {
        let path = "/Users/anhyobin/.claude/projects/-Users-anhyobin-dev-real-time-leaderboard/03ce38d5-ba5d-45d0-b327-bfb9981b66d0.jsonl"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Real-world fixture not present")
        }
        let stats = JSONLParser.scanTokensAndThinking(at: URL(fileURLWithPath: path))
        let goal = try XCTUnwrap(stats.activeGoal)
        XCTAssertTrue(goal.condition.contains("메트릭"))
    }
}
