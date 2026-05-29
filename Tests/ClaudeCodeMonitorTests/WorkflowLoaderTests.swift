import XCTest
@testable import ClaudeCodeMonitor

// Build note: `swift test` requires the Xcode SDK. On CLT-only machines,
// `swift build` succeeds. Run these via Xcode.

final class WorkflowLoaderTests: XCTestCase {

    // MARK: name parsing

    /// scripts filename is "{name}-{wf_id}.js" — strip the trailing
    /// "-wf_…" and ".js" to recover the workflow name.
    func testWorkflowNameFromScriptFilename() {
        XCTAssertEqual(
            WorkflowLoader.workflowName(fromScriptFilename: "game-design-synthesis-wf_b9155143-fd4.js"),
            "game-design-synthesis"
        )
    }

    /// Names may contain hyphens; only the "-wf_…" segment is removed.
    func testWorkflowNameKeepsInnerHyphens() {
        XCTAssertEqual(
            WorkflowLoader.workflowName(fromScriptFilename: "itch-asset-research-wf_a7b7e65c-49f.js"),
            "itch-asset-research"
        )
    }

    /// A filename that doesn't match the pattern returns nil (caller falls
    /// back to the wf_id).
    func testWorkflowNameUnparseableReturnsNil() {
        XCTAssertNil(WorkflowLoader.workflowName(fromScriptFilename: "random.txt"))
    }

    // MARK: phase mapping

    /// workflowProgress maps each agent to a phase by phaseIndex; the agent's
    /// label becomes the SubagentInfo description. Phases are built in index
    /// order and group their agents.
    func testMapAgentsToPhases() {
        let progress: [[String: Any]] = [
            ["type": "workflow_phase", "index": 1, "title": "Design Lenses"],
            ["type": "workflow_phase", "index": 2, "title": "Synthesize"],
            ["type": "workflow_agent", "index": 1, "label": "balance",
             "phaseIndex": 1, "agentId": "a1"],
            ["type": "workflow_agent", "index": 2, "label": "mvp",
             "phaseIndex": 1, "agentId": "a2"],
            ["type": "workflow_agent", "index": 3, "label": "synth",
             "phaseIndex": 2, "agentId": "a3"],
        ]
        // a3 is still running (no result yet).
        let agentsById: [String: SubagentInfo] = [
            "a1": Self.makeAgent(id: "a1", active: false),
            "a2": Self.makeAgent(id: "a2", active: false),
            "a3": Self.makeAgent(id: "a3", active: true),
        ]

        let phases = WorkflowLoader.mapAgentsToPhases(progress: progress, agentsById: agentsById)

        XCTAssertEqual(phases.count, 2)
        XCTAssertEqual(phases[0].id, 1)
        XCTAssertEqual(phases[0].title, "Design Lenses")
        XCTAssertEqual(phases[0].agents.count, 2)
        XCTAssertEqual(phases[0].agents.map(\.description), ["balance", "mvp"])
        XCTAssertTrue(phases[0].isComplete)       // a1,a2 both inactive
        XCTAssertEqual(phases[1].agents.count, 1)
        XCTAssertFalse(phases[1].isComplete)      // a3 active
    }

    /// Empty progress → no phases.
    func testMapAgentsToPhasesEmpty() {
        let phases = WorkflowLoader.mapAgentsToPhases(progress: [], agentsById: [:])
        XCTAssertTrue(phases.isEmpty)
    }

    // helper
    private static func makeAgent(id: String, active: Bool) -> SubagentInfo {
        SubagentInfo(
            id: id,
            agentType: "general-purpose",
            description: nil,
            tokens: TokenUsage(),
            toolUseCount: 0,
            messageCount: 0,
            toolBreakdown: [:],
            skillCounts: [:],
            // active = mtime within 60s; inactive = old date.
            lastActivity: active ? Date() : Date(timeIntervalSince1970: 0)
        )
    }
}
