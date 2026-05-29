import XCTest
@testable import ClaudeCodeMonitor

// Build note: `swift test` requires the Xcode SDK (XCTest is not in the
// Command Line Tools SDK). On CLT-only machines, `swift build` succeeds
// because test targets are not built. Run these via Xcode.

final class WorkflowJournalTests: XCTestCase {

    /// Every started agent has a matching result → all done → not running,
    /// and the set of unfinished agents is empty.
    func testAllResultsMeansComplete() {
        let lines = """
        {"type":"started","agentId":"a1"}
        {"type":"started","agentId":"a2"}
        {"type":"result","agentId":"a1"}
        {"type":"result","agentId":"a2"}
        """
        let summary = WorkflowJournal.parse(text: lines)
        XCTAssertFalse(summary.hasUnfinishedAgents)
        XCTAssertTrue(summary.unfinishedAgentIds.isEmpty)
        XCTAssertEqual(summary.startedAgentIds, ["a1", "a2"])
    }

    /// A started agent with no matching result → that agent is still running.
    func testStartedWithoutResultMeansRunning() {
        let lines = """
        {"type":"started","agentId":"a1"}
        {"type":"started","agentId":"a2"}
        {"type":"result","agentId":"a1"}
        """
        let summary = WorkflowJournal.parse(text: lines)
        XCTAssertTrue(summary.hasUnfinishedAgents)
        XCTAssertEqual(summary.unfinishedAgentIds, ["a2"])
    }

    /// Blank lines and malformed JSON are skipped without crashing.
    func testIgnoresBlankAndMalformedLines() {
        let lines = """
        {"type":"started","agentId":"a1"}

        not-json
        {"type":"result","agentId":"a1"}
        """
        let summary = WorkflowJournal.parse(text: lines)
        XCTAssertFalse(summary.hasUnfinishedAgents)
        XCTAssertEqual(summary.startedAgentIds, ["a1"])
    }

    /// Empty input → no agents, not running.
    func testEmptyInput() {
        let summary = WorkflowJournal.parse(text: "")
        XCTAssertFalse(summary.hasUnfinishedAgents)
        XCTAssertTrue(summary.startedAgentIds.isEmpty)
    }

    /// Journals interleave: a `result` can appear before its `started`, and an
    /// orphan `result` (no matching `started`) can appear. `unfinished` is
    /// computed once from the final sets, so event order doesn't matter and an
    /// orphan result is absent from both arrays. Regression guard against a
    /// future refactor to incremental running-detection.
    func testResultBeforeStartedAndOrphanResult() {
        let lines = """
        {"type":"result","agentId":"a1"}
        {"type":"started","agentId":"a1"}
        {"type":"result","agentId":"a3"}
        {"type":"started","agentId":"a2"}
        """
        let summary = WorkflowJournal.parse(text: lines)
        // a1 has a result (order irrelevant) → finished; a2 started, no result → unfinished.
        XCTAssertEqual(summary.unfinishedAgentIds, ["a2"])
        // a3's orphan result never appears (it had no started event).
        XCTAssertEqual(summary.startedAgentIds, ["a1", "a2"])
    }

    /// Duplicate `started` events for one agent are deduped, preserving
    /// first-seen order.
    func testDuplicateStartedIsDeduped() {
        let lines = """
        {"type":"started","agentId":"a1"}
        {"type":"started","agentId":"a1"}
        """
        let summary = WorkflowJournal.parse(text: lines)
        XCTAssertEqual(summary.startedAgentIds, ["a1"])
        XCTAssertEqual(summary.unfinishedAgentIds, ["a1"])
    }
}
