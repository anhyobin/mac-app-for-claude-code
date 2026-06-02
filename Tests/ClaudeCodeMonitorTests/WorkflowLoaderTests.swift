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

    // MARK: phase-title parsing (running skeleton)

    /// Mid-run there is no state JSON, but the script carries a pure-literal
    /// `meta.phases`. We recover the ordered titles for the running skeleton.
    func testPhaseTitlesFromScript() {
        let js = """
        export const meta = {
          name: 'opus48-research',
          description: 'x',
          phases: [
            { title: 'Research', detail: 'a' },
            { title: 'Synthesize', detail: 'b' },
          ],
        }
        const X = 1
        """
        XCTAssertEqual(WorkflowLoader.phaseTitles(fromScript: js), ["Research", "Synthesize"])
    }

    /// No meta block → no skeleton.
    func testPhaseTitlesNoMetaReturnsEmpty() {
        XCTAssertEqual(WorkflowLoader.phaseTitles(fromScript: "const a = 1"), [])
    }

    /// A `detail` string containing `]` must not truncate the bracket scan.
    func testPhaseTitlesToleratesBracketInDetail() {
        let js = """
        export const meta = {
          phases: [
            { title: 'A', detail: 'uses array[0] syntax' },
            { title: 'B', detail: 'b' },
          ],
        }
        """
        XCTAssertEqual(WorkflowLoader.phaseTitles(fromScript: js), ["A", "B"])
    }

    /// A schema property named `phases` before the meta block must not win.
    func testPhaseTitlesAnchorsAtMetaBlock() {
        let js = """
        const SCHEMA = { phases: ['x', 'y'] }
        export const meta = { phases: [ { title: 'Real', detail: 'd' } ] }
        """
        XCTAssertEqual(WorkflowLoader.phaseTitles(fromScript: js), ["Real"])
    }

    // MARK: journal counts (running aggregate)

    /// The running "M/N done" aggregate comes from the journal: distinct
    /// `started` = N, started-and-resulted = M.
    func testJournalStartedAndFinishedCounts() {
        let s = WorkflowJournal.parse(text: """
        {"type":"started","agentId":"a1"}
        {"type":"started","agentId":"a2"}
        {"type":"started","agentId":"a3"}
        {"type":"result","agentId":"a1"}
        {"type":"result","agentId":"a2"}
        """)
        XCTAssertEqual(s.startedCount, 3)
        XCTAssertEqual(s.finishedCount, 2)
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

    /// Regression: a phase whose agents all reached a terminal `state`
    /// ("done"/"error") must read as complete EVEN IF their JSONL files were
    /// touched within the last 60s. The old code derived completeness purely
    /// from `SubagentInfo.isActive` (an mtime heuristic), so a workflow that
    /// had just finished showed "phase 0/n" until 60s elapsed — and the
    /// mtime-cache then froze that wrong snapshot permanently.
    func testPhaseCompleteFromTerminalStateDespiteFreshMtime() {
        let progress: [[String: Any]] = [
            ["type": "workflow_phase", "index": 1, "title": "Research"],
            ["type": "workflow_phase", "index": 2, "title": "Synthesize"],
            ["type": "workflow_agent", "index": 1, "label": "fetch", "state": "done",
             "phaseIndex": 1, "agentId": "a1"],
            ["type": "workflow_agent", "index": 2, "label": "map", "state": "done",
             "phaseIndex": 1, "agentId": "a2"],
            ["type": "workflow_agent", "index": 3, "label": "synth", "state": "done",
             "phaseIndex": 2, "agentId": "a3"],
        ]
        // All agents touched just now (the just-completed case).
        let agentsById: [String: SubagentInfo] = [
            "a1": Self.makeAgent(id: "a1", active: true),
            "a2": Self.makeAgent(id: "a2", active: true),
            "a3": Self.makeAgent(id: "a3", active: true),
        ]

        let phases = WorkflowLoader.mapAgentsToPhases(progress: progress, agentsById: agentsById)

        XCTAssertTrue(phases[0].isComplete, "all agents state=done → phase complete")
        XCTAssertTrue(phases[1].isComplete, "all agents state=done → phase complete")
    }

    /// `state: "error"` is also terminal — a phase of errored agents is done
    /// (it will not progress further), so it must not spin forever.
    func testPhaseCompleteWhenAllAgentsErrored() {
        let progress: [[String: Any]] = [
            ["type": "workflow_phase", "index": 1, "title": "Verify"],
            ["type": "workflow_agent", "index": 1, "label": "v", "state": "error",
             "phaseIndex": 1, "agentId": "a1"],
        ]
        let agentsById = ["a1": Self.makeAgent(id: "a1", active: true)]

        let phases = WorkflowLoader.mapAgentsToPhases(progress: progress, agentsById: agentsById)

        XCTAssertTrue(phases[0].isComplete, "state=error is terminal → phase complete")
    }

    /// A non-terminal agent ("progress"/"start") keeps its phase incomplete
    /// regardless of mtime — this is the genuinely-running case the spinner is
    /// meant for.
    func testPhaseIncompleteWhenAgentStillProgressing() {
        let progress: [[String: Any]] = [
            ["type": "workflow_phase", "index": 1, "title": "Build"],
            ["type": "workflow_agent", "index": 1, "label": "a", "state": "done",
             "phaseIndex": 1, "agentId": "a1"],
            ["type": "workflow_agent", "index": 2, "label": "b", "state": "progress",
             "phaseIndex": 1, "agentId": "a2"],
        ]
        let agentsById: [String: SubagentInfo] = [
            "a1": Self.makeAgent(id: "a1", active: false),
            "a2": Self.makeAgent(id: "a2", active: true),
        ]

        let phases = WorkflowLoader.mapAgentsToPhases(progress: progress, agentsById: agentsById)

        XCTAssertFalse(phases[0].isComplete, "one agent still in 'progress' → phase incomplete")
    }

    /// Regression: a declared phase that dispatched ZERO agents (a workflow
    /// conditionally skipped it — e.g. a "Fix" phase with nothing to fix) must
    /// read as complete once the workflow itself is finished. The old guard
    /// `!agents.isEmpty && …` left such phases forever-incomplete, so a
    /// finished run showed "phase 2/3" with a perpetual spinner on the skipped
    /// phase.
    func testEmptyPhaseIsCompleteWhenWorkflowCompleted() {
        let progress: [[String: Any]] = [
            ["type": "workflow_phase", "index": 1, "title": "Implement"],
            ["type": "workflow_phase", "index": 2, "title": "Fix"],   // skipped
            ["type": "workflow_agent", "index": 1, "label": "impl", "state": "done",
             "phaseIndex": 1, "agentId": "a1"],
        ]
        let agentsById = ["a1": Self.makeAgent(id: "a1", active: false)]

        let phases = WorkflowLoader.mapAgentsToPhases(
            progress: progress, agentsById: agentsById, workflowCompleted: true)

        XCTAssertTrue(phases[0].isComplete)
        XCTAssertTrue(phases[1].isComplete, "skipped phase of a completed workflow is done")
    }

    /// An empty phase in a STILL-RUNNING workflow has simply not started yet,
    /// so it stays incomplete (pending) — distinct from the skipped case above.
    func testEmptyPhaseIsIncompleteWhenWorkflowRunning() {
        let progress: [[String: Any]] = [
            ["type": "workflow_phase", "index": 1, "title": "Implement"],
            ["type": "workflow_phase", "index": 2, "title": "Review"],  // not started
            ["type": "workflow_agent", "index": 1, "label": "impl", "state": "done",
             "phaseIndex": 1, "agentId": "a1"],
        ]
        let agentsById = ["a1": Self.makeAgent(id: "a1", active: true)]

        let phases = WorkflowLoader.mapAgentsToPhases(
            progress: progress, agentsById: agentsById, workflowCompleted: false)

        XCTAssertTrue(phases[0].isComplete)
        XCTAssertFalse(phases[1].isComplete, "not-yet-started phase of a running workflow is pending")
    }

    /// Back-compat: when progress entries carry no `state` field at all (older
    /// runs, or a defensive fallback), completeness falls back to the mtime
    /// heuristic so behavior doesn't regress for data without state.
    func testPhaseCompletenessFallsBackToMtimeWhenStateAbsent() {
        let progress: [[String: Any]] = [
            ["type": "workflow_phase", "index": 1, "title": "Old"],
            ["type": "workflow_agent", "index": 1, "label": "a",
             "phaseIndex": 1, "agentId": "a1"],
        ]
        // No "state" key. Inactive mtime → complete; active → incomplete.
        XCTAssertTrue(
            WorkflowLoader.mapAgentsToPhases(
                progress: progress,
                agentsById: ["a1": Self.makeAgent(id: "a1", active: false)]
            )[0].isComplete
        )
        XCTAssertFalse(
            WorkflowLoader.mapAgentsToPhases(
                progress: progress,
                agentsById: ["a1": Self.makeAgent(id: "a1", active: true)]
            )[0].isComplete
        )
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
