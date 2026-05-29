# 워크플로우 가시성 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Claude Code Monitor가 dynamic workflow 실행(에이전트 fan-out)을 세션 확장 뷰의 "Workflows" 섹션과 메뉴바 보라 틴트로 표시하도록 한다.

**Architecture:** `subagents/workflows/{wf_id}/` (워크플로우 에이전트)와 `workflows/{wf_id}.json` (런 상태)를 읽는 신규 `WorkflowLoader`를 `SubagentLoader`의 형제로 추가. 실행 중 판정은 `journal.jsonl`의 unmatched `started`로(mtime 60s fallback). 신규 `WorkflowInfo`/`WorkflowPhase` 모델은 기존 `SubagentInfo`/`AgentRow`/`AgentDetailView`를 재사용. 신규 `WorkflowSection` 뷰를 `SessionDetailView` 맨 위에 삽입. 메뉴바는 `/goal` 틴트 패턴 재사용.

**Tech Stack:** Swift 6 / SwiftUI, SwiftPM (`swift build`), XCTest. **빌드 환경 주의: 이 머신은 Xcode.app 없이 Command Line Tools만 있어 `swift test`(XCTest) 실행 불가. 검증은 `swift build`(컴파일) + 코드 인스펙션으로 하고, XCTest 실행은 Xcode 보유 머신에서.**

**Spec:** `docs/superpowers/specs/2026-05-30-workflow-visibility-design.md`

---

## File Structure

| 파일 | 책임 | 신규/수정 |
|---|---|---|
| `Sources/ClaudeCodeMonitor/Models/WorkflowInfo.swift` | 워크플로우 1개 런 상태 + `WorkflowRunStatus` enum | 신규 |
| `Sources/ClaudeCodeMonitor/Models/WorkflowPhase.swift` | 페이즈 1개 + 소속 에이전트 | 신규 |
| `Sources/ClaudeCodeMonitor/DataLayer/WorkflowJournal.swift` | journal.jsonl 파싱 → running 판정 (순수 함수, 테스트 용이) | 신규 |
| `Sources/ClaudeCodeMonitor/DataLayer/WorkflowLoader.swift` | 디스크 → `[WorkflowInfo]`, mtime 캐시 | 신규 |
| `Sources/ClaudeCodeMonitor/Models/SessionExpandedData.swift` | `workflows` 필드 추가 | 수정 |
| `Sources/ClaudeCodeMonitor/DataLayer/ClaudeDataStore.swift` | 로더 호출 + `hasRunningWorkflow` + detail nested 경로 | 수정 |
| `Sources/ClaudeCodeMonitor/Views/WorkflowSection.swift` | "Workflows" 섹션 + 페이즈 트리 | 신규 |
| `Sources/ClaudeCodeMonitor/Views/AgentRow.swift` | 옵셔널 `workflowId` 파라미터 | 수정 |
| `Sources/ClaudeCodeMonitor/Views/SessionDetailView.swift` | `WorkflowSection` 삽입 | 수정 |
| `Sources/ClaudeCodeMonitor/App/ClaudeCodeMonitorApp.swift` | 세션 수 보라 틴트 | 수정 |
| `Tests/ClaudeCodeMonitorTests/WorkflowJournalTests.swift` | running 판정 회귀 가드 | 신규 |
| `Tests/ClaudeCodeMonitorTests/WorkflowLoaderTests.swift` | 이름 파싱 + 페이즈 매핑 회귀 가드 | 신규 |
| `Tests/ClaudeCodeMonitorTests/ContextUsageRatioTests.swift` | `makeExpanded` 헬퍼에 `workflows:` 인자 추가 | 수정 |

---

### Task 1: WorkflowInfo / WorkflowPhase / WorkflowRunStatus 모델

**Files:**
- Create: `Sources/ClaudeCodeMonitor/Models/WorkflowRunStatus.swift`
- Create: `Sources/ClaudeCodeMonitor/Models/WorkflowPhase.swift`
- Create: `Sources/ClaudeCodeMonitor/Models/WorkflowInfo.swift`

- [ ] **Step 1: WorkflowRunStatus 작성**

`Sources/ClaudeCodeMonitor/Models/WorkflowRunStatus.swift`:

```swift
import Foundation

/// Whether a workflow run is still executing or has finished.
///
/// `.running` is detected from `journal.jsonl` (a `started` event with no
/// matching `result`) or a fresh directory mtime — NOT from the
/// `workflows/{id}.json` `status` field, which is only written when the run
/// completes (the file may be absent or stale mid-run).
enum WorkflowRunStatus: Sendable, Equatable {
    case running
    case completed
}
```

- [ ] **Step 2: WorkflowPhase 작성**

`Sources/ClaudeCodeMonitor/Models/WorkflowPhase.swift`:

```swift
import Foundation

/// One phase of a workflow run, with the agents assigned to it.
///
/// Agents reuse ``SubagentInfo`` because workflow agents are written in the
/// same JSONL format as flat subagents (just one directory deeper). The
/// workflow's human label for the agent (e.g. "game-design-balance") is
/// carried in ``SubagentInfo/description``.
struct WorkflowPhase: Identifiable, Sendable {
    let id: Int          // phaseIndex from workflowProgress
    let title: String
    let agents: [SubagentInfo]
    /// True when every agent in this phase has produced a result (none active).
    let isComplete: Bool
}
```

- [ ] **Step 3: WorkflowInfo 작성**

`Sources/ClaudeCodeMonitor/Models/WorkflowInfo.swift`:

```swift
import Foundation

/// Aggregate state for a single workflow run within a session.
///
/// Sourced from `workflows/{id}.json` (run state, written at completion) and
/// `subagents/workflows/{id}/` (agent transcripts + journal). When the
/// `.json` is absent (run still starting), `name` falls back to the
/// `scripts/{name}-{id}.js` filename and phases collapse to a single
/// "running" group.
struct WorkflowInfo: Identifiable, Sendable {
    let id: String              // wf_id
    let name: String
    let status: WorkflowRunStatus
    let phases: [WorkflowPhase]
    let totalTokens: TokenUsage
    let totalToolCalls: Int
    let agentCount: Int
    let durationMs: Int?
    let lastActivity: Date?     // workflows/{id} dir or journal mtime

    var isRunning: Bool { status == .running }

    /// Count of agents that have finished (have a result), used for the
    /// progress bar. Smoother than phase-granularity. Derived from phases:
    /// a phase agent is "done" when it is not active.
    var completedAgentCount: Int {
        phases.reduce(0) { acc, phase in
            acc + phase.agents.filter { !$0.isActive }.count
        }
    }

    /// Number of phases that are fully complete, for the "phase n/m" text.
    var completedPhaseCount: Int {
        phases.filter { $0.isComplete }.count
    }
}
```

- [ ] **Step 4: 컴파일 통과 확인**

Run: `swift build 2>&1 | tail -5`
Expected: 에러 없이 빌드 완료 (`Build complete!`). 아직 소비자가 없으니 경고 없이 통과.

- [ ] **Step 5: 커밋**

```bash
git add Sources/ClaudeCodeMonitor/Models/WorkflowRunStatus.swift Sources/ClaudeCodeMonitor/Models/WorkflowPhase.swift Sources/ClaudeCodeMonitor/Models/WorkflowInfo.swift
git commit -m "feat: add WorkflowInfo / WorkflowPhase / WorkflowRunStatus models"
```

---

### Task 2: WorkflowJournal — running 판정 (순수 함수 + 테스트)

journal.jsonl 파싱은 "실행 중" 판정의 load-bearing 로직이므로 순수 함수로 분리해 테스트한다.

**Files:**
- Create: `Sources/ClaudeCodeMonitor/DataLayer/WorkflowJournal.swift`
- Test: `Tests/ClaudeCodeMonitorTests/WorkflowJournalTests.swift`

- [ ] **Step 1: 실패 테스트 먼저 작성**

`Tests/ClaudeCodeMonitorTests/WorkflowJournalTests.swift`:

```swift
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
}
```

- [ ] **Step 2: 테스트 실패 확인 (코드 인스펙션 — XCTest 실행 불가 환경)**

`WorkflowJournal` 타입이 아직 없으므로 컴파일 자체가 실패할 것 (`cannot find 'WorkflowJournal' in scope`). Xcode 머신이면 `swift test --filter WorkflowJournalTests` → 컴파일 에러로 FAIL.

- [ ] **Step 3: WorkflowJournal 구현**

`Sources/ClaudeCodeMonitor/DataLayer/WorkflowJournal.swift`:

```swift
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
```

- [ ] **Step 4: 컴파일 통과 확인**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`. Xcode 머신이면 `swift test --filter WorkflowJournalTests` → 4개 PASS.

- [ ] **Step 5: 커밋**

```bash
git add Sources/ClaudeCodeMonitor/DataLayer/WorkflowJournal.swift Tests/ClaudeCodeMonitorTests/WorkflowJournalTests.swift
git commit -m "feat: add WorkflowJournal running-detection parser + tests"
```

---

### Task 3: WorkflowLoader — 이름 파싱 + 페이즈 매핑 (테스트 우선)

**Files:**
- Create: `Sources/ClaudeCodeMonitor/DataLayer/WorkflowLoader.swift`
- Test: `Tests/ClaudeCodeMonitorTests/WorkflowLoaderTests.swift`

이 Task는 두 개의 순수 헬퍼(`workflowName(fromScriptFilename:)`, `mapAgentsToPhases(...)`)를 먼저
테스트한 뒤, 디스크 I/O를 묶는 `loadWorkflows`를 구현한다. I/O 함수는 CLT 환경에서 테스트 불가하므로
순수 헬퍼만 회귀 가드한다.

- [ ] **Step 1: 실패 테스트 먼저 작성**

`Tests/ClaudeCodeMonitorTests/WorkflowLoaderTests.swift`:

```swift
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
```

- [ ] **Step 2: 테스트 실패 확인 (코드 인스펙션)**

`WorkflowLoader`가 없어 컴파일 실패 (`cannot find 'WorkflowLoader'`). Xcode 머신이면 FAIL.

**주의:** `mapAgentsToPhases`는 `agentId`로 받은 `SubagentInfo`에 `label`을 입혀 새 `SubagentInfo`를
만들어야 한다(원본 description은 nil). 즉 매핑 시 `description`을 label로 교체한 복사본을 phase에 담는다.

- [ ] **Step 3: WorkflowLoader 구현**

`Sources/ClaudeCodeMonitor/DataLayer/WorkflowLoader.swift`:

```swift
import Foundation

/// Loads workflow runs for a session from disk.
///
/// Sibling of ``SubagentLoader``. Workflow agents live one directory deeper
/// (`subagents/workflows/{wf_id}/agent-*.jsonl`) than flat subagents, so
/// ``SubagentLoader`` never sees them. This loader reads both the agent
/// transcripts and the `workflows/{wf_id}.json` run-state file, and uses
/// ``WorkflowJournal`` for live running-detection.
enum WorkflowLoader {

    private static let projectsDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }()

    /// "running" if the directory was touched within this window even when
    /// the journal looks complete — covers brief gaps between journal writes.
    private static let activityWindow: TimeInterval = 60

    // MARK: - Pure helpers (unit-tested)

    /// Recover a workflow name from its script filename "{name}-{wf_id}.js".
    /// Returns nil if the pattern doesn't match.
    static func workflowName(fromScriptFilename filename: String) -> String? {
        guard filename.hasSuffix(".js") else { return nil }
        let base = String(filename.dropLast(3)) // remove ".js"
        // Remove the trailing "-wf_…" segment.
        guard let range = base.range(of: "-wf_", options: .backwards) else { return nil }
        let name = String(base[..<range.lowerBound])
        return name.isEmpty ? nil : name
    }

    /// Build phases from a `workflowProgress` array, attaching each agent's
    /// label as the SubagentInfo description. Phases come out in index order.
    static func mapAgentsToPhases(
        progress: [[String: Any]],
        agentsById: [String: SubagentInfo]
    ) -> [WorkflowPhase] {
        // Collect phase definitions, ordered by index.
        var phaseTitles: [(index: Int, title: String)] = []
        // phaseIndex -> [(orderIndex, labelledAgent)]
        var phaseAgents: [Int: [(Int, SubagentInfo)]] = [:]

        for item in progress {
            guard let type = item["type"] as? String else { continue }
            if type == "workflow_phase",
               let index = item["index"] as? Int,
               let title = item["title"] as? String {
                phaseTitles.append((index, title))
            } else if type == "workflow_agent",
                      let phaseIndex = item["phaseIndex"] as? Int,
                      let agentId = item["agentId"] as? String {
                let order = item["index"] as? Int ?? 0
                let label = item["label"] as? String
                if var agent = agentsById[agentId] {
                    // Replace description with the workflow label.
                    agent = SubagentInfo(
                        id: agent.id,
                        agentType: agent.agentType,
                        description: label ?? agent.description,
                        tokens: agent.tokens,
                        toolUseCount: agent.toolUseCount,
                        messageCount: agent.messageCount,
                        toolBreakdown: agent.toolBreakdown,
                        skillCounts: agent.skillCounts,
                        lastActivity: agent.lastActivity
                    )
                    phaseAgents[phaseIndex, default: []].append((order, agent))
                }
            }
        }

        return phaseTitles
            .sorted { $0.index < $1.index }
            .map { phase in
                let agents = (phaseAgents[phase.index] ?? [])
                    .sorted { $0.0 < $1.0 }
                    .map { $0.1 }
                let isComplete = !agents.isEmpty && agents.allSatisfy { !$0.isActive }
                return WorkflowPhase(
                    id: phase.index,
                    title: phase.title,
                    agents: agents,
                    isComplete: isComplete
                )
            }
    }

    // MARK: - Disk loading

    static func loadWorkflows(
        sessionId: String,
        projectPath: String,
        previous: [WorkflowInfo]? = nil
    ) -> [WorkflowInfo] {
        let fm = FileManager.default
        let encodedPath = PathDecoder.encodedProjectPath(from: projectPath)
        let sessionDir = projectsDirectory
            .appendingPathComponent(encodedPath)
            .appendingPathComponent(sessionId)

        let wfAgentsRoot = sessionDir
            .appendingPathComponent("subagents")
            .appendingPathComponent("workflows")
        let wfStateDir = sessionDir.appendingPathComponent("workflows")
        let wfScriptsDir = wfStateDir.appendingPathComponent("scripts")

        // No workflows directory → nothing to do (zero cost for the common case).
        guard let wfIds = try? fm.contentsOfDirectory(atPath: wfAgentsRoot.path) else {
            return []
        }

        let previousById: [String: WorkflowInfo]? = previous.map {
            Dictionary(uniqueKeysWithValues: $0.map { ($0.id, $0) })
        }

        var workflows: [WorkflowInfo] = []

        for wfId in wfIds where wfId.hasPrefix("wf_") {
            let agentDir = wfAgentsRoot.appendingPathComponent(wfId)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: agentDir.path, isDirectory: &isDir), isDir.boolValue else { continue }

            // mtime cache: reuse if directory unchanged.
            let dirMtime: Date? = {
                guard let attrs = try? fm.attributesOfItem(atPath: agentDir.path) else { return nil }
                return attrs[.modificationDate] as? Date
            }()
            if let prev = previousById?[wfId],
               let prevMtime = prev.lastActivity,
               let curMtime = dirMtime,
               prevMtime == curMtime {
                workflows.append(prev)
                continue
            }

            // Parse agent transcripts (reuse SubagentLoader's per-agent scan).
            let agentsById = loadAgents(in: agentDir)

            // journal → running detection.
            let journal = WorkflowJournal.parse(
                fileAt: agentDir.appendingPathComponent("journal.jsonl"))
            let fresh = dirMtime.map { Date().timeIntervalSince($0) < activityWindow } ?? false
            let isRunning = journal.hasUnfinishedAgents || fresh

            // Run-state JSON (present at completion).
            let stateURL = wfStateDir.appendingPathComponent("\(wfId).json")
            let state = (try? Data(contentsOf: stateURL))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }

            // Name: json.workflowName → scripts filename → wfId.
            let name = (state?["workflowName"] as? String)
                ?? scriptName(in: wfScriptsDir, wfId: wfId, fm: fm)
                ?? wfId

            // Phases from workflowProgress, else single fallback phase.
            let progress = state?["workflowProgress"] as? [[String: Any]] ?? []
            let phases: [WorkflowPhase]
            if progress.isEmpty {
                let agents = Array(agentsById.values).sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
                phases = agents.isEmpty ? [] : [WorkflowPhase(id: 0, title: "Running", agents: agents, isComplete: false)]
            } else {
                phases = mapAgentsToPhases(progress: progress, agentsById: agentsById)
            }

            // Aggregate tokens/tools across agents.
            var totalTokens = TokenUsage()
            var totalToolCalls = 0
            for agent in agentsById.values {
                totalTokens.add(agent.tokens)
                totalToolCalls += agent.toolUseCount
            }

            workflows.append(WorkflowInfo(
                id: wfId,
                name: name,
                status: isRunning ? .running : .completed,
                phases: phases,
                totalTokens: totalTokens,
                totalToolCalls: totalToolCalls,
                agentCount: (state?["agentCount"] as? Int) ?? agentsById.count,
                durationMs: state?["durationMs"] as? Int,
                lastActivity: dirMtime
            ))
        }

        // Running first, then most-recently-active.
        workflows.sort { a, b in
            if a.isRunning != b.isRunning { return a.isRunning }
            return (a.lastActivity ?? .distantPast) > (b.lastActivity ?? .distantPast)
        }
        return workflows
    }

    // MARK: - private disk helpers

    /// Find the scripts filename for a wf_id and recover its name.
    private static func scriptName(in scriptsDir: URL, wfId: String, fm: FileManager) -> String? {
        guard let files = try? fm.contentsOfDirectory(atPath: scriptsDir.path) else { return nil }
        guard let match = files.first(where: { $0.contains(wfId) && $0.hasSuffix(".js") }) else { return nil }
        return workflowName(fromScriptFilename: match)
    }

    /// Parse all `agent-*.jsonl` in a workflow agent directory into
    /// SubagentInfo keyed by agent hash. Mirrors SubagentLoader's scan.
    private static func loadAgents(in dir: URL) -> [String: SubagentInfo] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { return [:] }
        let jsonlFiles = files.filter { $0.hasSuffix(".jsonl") && $0.hasPrefix("agent-") }

        var result: [String: SubagentInfo] = [:]
        let decoder = JSONDecoder()

        for file in jsonlFiles {
            let hash = String(file.dropFirst("agent-".count).dropLast(".jsonl".count))
            let jsonlPath = dir.appendingPathComponent(file)
            let mtime: Date? = {
                guard let attrs = try? fm.attributesOfItem(atPath: jsonlPath.path) else { return nil }
                return attrs[.modificationDate] as? Date
            }()

            // meta.json for agentType.
            var agentType = "general-purpose"
            let metaPath = dir.appendingPathComponent("agent-\(hash).meta.json")
            if let metaData = fm.contents(atPath: metaPath.path),
               let meta = try? decoder.decode(SubagentMeta.self, from: metaData) {
                agentType = meta.agentType
            }

            let scan = SubagentScan.scan(jsonlPath: jsonlPath)
            result[hash] = SubagentInfo(
                id: hash,
                agentType: agentType,
                description: nil,
                tokens: scan.tokens,
                toolUseCount: scan.toolUseCount,
                messageCount: scan.messageCount,
                toolBreakdown: scan.toolBreakdown,
                skillCounts: scan.skillCounts,
                lastActivity: mtime
            )
        }
        return result
    }
}
```

**참고:** 위 구현은 `SubagentScan.scan(jsonlPath:)`를 호출한다 — 이는 Task 4에서 `SubagentLoader`의
private `scanAgentJSONL`을 공유 가능한 형태로 추출한 것이다. Task 3에서는 일단 컴파일을 위해
Task 4를 먼저 하거나, 임시로 `SubagentLoader` 로직을 인라인한다. **권장: Task 4를 Task 3보다 먼저
실행** (아래 Task 4가 추출을 담당). 실행 순서: Task 1 → 2 → 4 → 3.

- [ ] **Step 4: 컴파일 통과 확인**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!` (Task 4의 `SubagentScan` 추출이 선행된 상태에서). Xcode 머신이면 `swift test --filter WorkflowLoaderTests` → 5개 PASS.

- [ ] **Step 5: 커밋**

```bash
git add Sources/ClaudeCodeMonitor/DataLayer/WorkflowLoader.swift Tests/ClaudeCodeMonitorTests/WorkflowLoaderTests.swift
git commit -m "feat: add WorkflowLoader with name parsing + phase mapping + tests"
```

---

### Task 4: SubagentScan 추출 (SubagentLoader와 WorkflowLoader 공유)

`SubagentLoader.scanAgentJSONL`은 private이고 `WorkflowLoader`도 동일 파싱이 필요하다. DRY를 위해
공유 타입으로 추출한다. **이 Task는 Task 3보다 먼저 실행한다.**

**Files:**
- Create: `Sources/ClaudeCodeMonitor/DataLayer/SubagentScan.swift`
- Modify: `Sources/ClaudeCodeMonitor/DataLayer/SubagentLoader.swift:70, 96-149`

- [ ] **Step 1: SubagentScan 작성 (scanAgentJSONL 본문 이동)**

`Sources/ClaudeCodeMonitor/DataLayer/SubagentScan.swift`:

```swift
import Foundation

/// Result of scanning one agent's JSONL transcript for usage stats.
///
/// Shared by ``SubagentLoader`` (flat `subagents/agent-*.jsonl`) and
/// ``WorkflowLoader`` (`subagents/workflows/{id}/agent-*.jsonl`) — both read
/// the identical assistant-turn JSONL format.
enum SubagentScan {

    struct Result: Sendable {
        var tokens = TokenUsage()
        var toolUseCount = 0
        var messageCount = 0
        var toolBreakdown: [String: Int] = [:]
        var skillCounts: [String: Int] = [:]
    }

    /// Scan an agent JSONL file. Files larger than 50MB are skipped (returns
    /// zeros) to bound per-refresh cost.
    static func scan(jsonlPath path: URL) -> Result {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
              let fileSize = attrs[.size] as? UInt64,
              fileSize <= 50 * 1024 * 1024 else {
            return Result()
        }
        guard let data = try? Data(contentsOf: path) else {
            return Result()
        }

        var out = Result()
        let lines = data.split(separator: UInt8(ascii: "\n"))
        for lineData in lines {
            let lineStr = String(decoding: lineData, as: UTF8.self)
            guard lineStr.contains("\"type\":\"assistant\"") else { continue }
            guard let entry = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let message = entry["message"] as? [String: Any] else { continue }

            out.messageCount += 1

            if let usage = message["usage"] as? [String: Any] {
                out.tokens.add(TokenUsage(
                    inputTokens: usage["input_tokens"] as? Int ?? 0,
                    outputTokens: usage["output_tokens"] as? Int ?? 0,
                    cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0,
                    cacheWriteTokens: usage["cache_creation_input_tokens"] as? Int ?? 0
                ))
            }

            if let content = message["content"] as? [[String: Any]] {
                for block in content where block["type"] as? String == "tool_use" {
                    out.toolUseCount += 1
                    if let name = block["name"] as? String {
                        out.toolBreakdown[name, default: 0] += 1
                        if name == "Skill",
                           let input = block["input"] as? [String: Any],
                           let skill = input["skill"] as? String {
                            out.skillCounts[skill, default: 0] += 1
                        }
                    }
                }
            }
        }
        return out
    }
}
```

- [ ] **Step 2: SubagentLoader가 SubagentScan을 쓰도록 수정**

`Sources/ClaudeCodeMonitor/DataLayer/SubagentLoader.swift`의 70행:

```swift
            // Parse JSONL for tokens and tool counts
            let (tokens, toolUseCount, messageCount, toolBreakdown, skillCounts) = scanAgentJSONL(at: jsonlPath)
```

을 다음으로 교체:

```swift
            // Parse JSONL for tokens and tool counts (shared scanner)
            let scan = SubagentScan.scan(jsonlPath: jsonlPath)
            let tokens = scan.tokens
            let toolUseCount = scan.toolUseCount
            let messageCount = scan.messageCount
            let toolBreakdown = scan.toolBreakdown
            let skillCounts = scan.skillCounts
```

그리고 96-149행의 private `scanAgentJSONL(at:)` 메서드 전체를 **삭제**한다 (SubagentScan으로 이동됨).

- [ ] **Step 3: 컴파일 통과 확인**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`. 동작 동일(순수 리팩터). Xcode 머신이면 기존 테스트 전부 PASS 유지.

- [ ] **Step 4: 커밋**

```bash
git add Sources/ClaudeCodeMonitor/DataLayer/SubagentScan.swift Sources/ClaudeCodeMonitor/DataLayer/SubagentLoader.swift
git commit -m "refactor: extract SubagentScan shared by Subagent/Workflow loaders"
```

---

### Task 5: SessionExpandedData에 workflows 필드 추가

**Files:**
- Modify: `Sources/ClaudeCodeMonitor/Models/SessionExpandedData.swift:3-48`
- Modify: `Tests/ClaudeCodeMonitorTests/ContextUsageRatioTests.swift:19-33` (makeExpanded 헬퍼)

- [ ] **Step 1: SessionExpandedData에 필드 추가**

`Sources/ClaudeCodeMonitor/Models/SessionExpandedData.swift`의 `let agents: [SubagentInfo]` (4행) 바로 다음에 삽입:

```swift
    /// Workflow runs detected for this session (running + recently completed).
    /// Empty for sessions that never ran a workflow. Sourced from
    /// `subagents/workflows/` and `workflows/{id}.json` via ``WorkflowLoader``.
    let workflows: [WorkflowInfo]
```

- [ ] **Step 2: ContextUsageRatioTests.makeExpanded 헬퍼 갱신**

`Tests/ClaudeCodeMonitorTests/ContextUsageRatioTests.swift`의 `SessionExpandedData(` 생성자 호출(19행)에서 `agents: [],` 다음 줄에 삽입:

```swift
            workflows: [],
```

- [ ] **Step 3: 컴파일 통과 확인**

Run: `swift build 2>&1 | tail -5`
Expected: 에러. `ClaudeDataStore.swift:331`의 `SessionExpandedData(` 호출에 `workflows:` 인자가 없어
`missing argument for parameter 'workflows'`. 이는 Task 6에서 채운다 — **이 Task는 컴파일 에러로
끝나는 게 정상**이며, Task 6과 한 묶음으로 진행한다. (또는 Step 4에서 임시로 `workflows: []`를
ClaudeDataStore에 먼저 넣어 그린으로 만든 뒤 Task 6에서 실제 로딩으로 교체.)

- [ ] **Step 4: ClaudeDataStore 생성자에 임시 빈 배열 추가 (그린 유지)**

`Sources/ClaudeCodeMonitor/DataLayer/ClaudeDataStore.swift:332`의 `return SessionExpandedData(`
블록에서 `agents: agents,` 다음 줄에 삽입:

```swift
                workflows: workflows,
```

그리고 같은 `Task.detached` 블록 안, `let agents = SubagentLoader.loadAgents(...)` (270-274행) 다음에 임시로:

```swift
            let workflows = WorkflowLoader.loadWorkflows(
                sessionId: sessionId,
                projectPath: projectPath,
                previous: previousWorkflows
            )
```

`previousWorkflows`는 Task 6에서 정의하므로, 이 Step에서는 일단 `previous: nil`로 두고 Task 6에서 캐시 배선을 완성한다.

```swift
            let workflows = WorkflowLoader.loadWorkflows(
                sessionId: sessionId,
                projectPath: projectPath,
                previous: nil
            )
```

- [ ] **Step 5: 컴파일 통과 확인**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`.

- [ ] **Step 6: 커밋**

```bash
git add Sources/ClaudeCodeMonitor/Models/SessionExpandedData.swift Tests/ClaudeCodeMonitorTests/ContextUsageRatioTests.swift Sources/ClaudeCodeMonitor/DataLayer/ClaudeDataStore.swift
git commit -m "feat: thread workflows through SessionExpandedData"
```

---

### Task 6: ClaudeDataStore — mtime 캐시 배선 + hasRunningWorkflow

**Files:**
- Modify: `Sources/ClaudeCodeMonitor/DataLayer/ClaudeDataStore.swift` (loadSessionDetail 259-346, hasActiveGoal 356 인근, loadAgentDetail 362-395)

- [ ] **Step 1: previousWorkflows 캐시 입력 추가**

`loadSessionDetail`의 캐시 캡처부 (`let previousActiveGoal = …`, 267행) 다음에 삽입:

```swift
        let previousWorkflows = expandedSessionData[sessionId]?.workflows
```

- [ ] **Step 2: loadWorkflows가 previousWorkflows를 쓰도록 수정**

Task 5 Step 4에서 넣은 `previous: nil`을 다음으로 교체:

```swift
            let workflows = WorkflowLoader.loadWorkflows(
                sessionId: sessionId,
                projectPath: projectPath,
                previous: previousWorkflows
            )
```

- [ ] **Step 3: hasRunningWorkflow computed 추가**

`hasActiveGoal` computed (356-360행) 바로 다음에 삽입:

```swift
    /// `true` when at least one active session has a workflow currently
    /// running. Drives the menu-bar count tint (workflow purple). Parallel
    /// to ``hasActiveGoal`` — goal tint takes priority when both are active
    /// (see ClaudeCodeMonitorApp), so a running goal is never masked.
    var hasRunningWorkflow: Bool {
        activeSessions.contains { session in
            expandedSessionData[session.id]?.workflows.contains { $0.isRunning } == true
        }
    }
```

- [ ] **Step 4: loadAgentDetail에 workflowId 파라미터 추가**

`loadAgentDetail` 시그니처(362행)를 교체:

```swift
    func loadAgentDetail(sessionId: String, agentHash: String, projectPath: String, workflowId: String? = nil, forceRefresh: Bool = false) async {
```

캐시 키(363행)를 교체 (워크플로우 에이전트가 같은 해시여도 충돌하지 않도록):

```swift
        let key = workflowId.map { "\(sessionId)/\($0)/\(agentHash)" } ?? "\(sessionId)/\(agentHash)"
```

`cachedBreakdown`/`cachedSkills` 조회(367-370행)를 워크플로우면 워크플로우 에이전트에서 찾도록 교체:

```swift
        // Get full tool & skill breakdowns from already-loaded SubagentInfo
        // (flat agent or workflow-phase agent).
        let sourceAgents: [SubagentInfo]
        if let workflowId {
            sourceAgents = expandedSessionData[sessionId]?.workflows
                .first { $0.id == workflowId }?
                .phases.flatMap { $0.agents } ?? []
        } else {
            sourceAgents = expandedSessionData[sessionId]?.agents ?? []
        }
        let cachedBreakdown = sourceAgents.first { $0.id == agentHash }?.toolBreakdown ?? [:]
        let cachedSkills = sourceAgents.first { $0.id == agentHash }?.skillCounts ?? [:]
```

agent JSONL 경로(376-381행 `Task.detached` 내부)를 워크플로우면 nested 경로로 교체:

```swift
        let result = await Task.detached {
            var agentDir = projectsDir
                .appendingPathComponent(encodedPath)
                .appendingPathComponent(sessionId)
                .appendingPathComponent("subagents")
            if let workflowId {
                agentDir = agentDir
                    .appendingPathComponent("workflows")
                    .appendingPathComponent(workflowId)
            }
            let agentPath = agentDir.appendingPathComponent("agent-\(agentHash).jsonl")

            let messages = JSONLParser.parseRecentMessages(at: agentPath)
            let fileChanges = JSONLParser.extractFileChanges(at: agentPath)

            return AgentDetailData(
                recentMessages: messages,
                fileChanges: fileChanges,
                toolBreakdown: cachedBreakdown,
                skillBreakdown: cachedSkills
            )
        }.value

        agentDetailData[key] = result
```

- [ ] **Step 5: 컴파일 통과 확인**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`. (`AgentRow`의 기존 `loadAgentDetail` 호출은 `workflowId` 기본값 nil로 무변경 동작.)

- [ ] **Step 6: 커밋**

```bash
git add Sources/ClaudeCodeMonitor/DataLayer/ClaudeDataStore.swift
git commit -m "feat: wire workflow cache + hasRunningWorkflow + nested agent detail path"
```

---

### Task 7: AgentRow에 workflowId 전달 지원

**Files:**
- Modify: `Sources/ClaudeCodeMonitor/Views/AgentRow.swift:6-22`

- [ ] **Step 1: AgentRow에 workflowId 프로퍼티 추가**

`Sources/ClaudeCodeMonitor/Views/AgentRow.swift`의 프로퍼티 선언부(5-8행)를 교체:

```swift
    @Environment(ClaudeDataStore.self) private var dataStore
    let agent: SubagentInfo
    let sessionId: String
    let projectPath: String
    /// When non-nil, this agent lives under `subagents/workflows/{id}/` and
    /// detail loading must use the nested path. nil for flat subagents.
    var workflowId: String? = nil
    @State private var isExpanded = false
```

`loadAgentDetail` 호출(16-21행)에 `workflowId` 전달:

```swift
                    Task {
                        await dataStore.loadAgentDetail(
                            sessionId: sessionId,
                            agentHash: agent.id,
                            projectPath: projectPath,
                            workflowId: workflowId
                        )
                    }
```

확장 detail 조회의 캐시 키(76행)도 동일 규칙으로 교체:

```swift
            if isExpanded {
                let key = workflowId.map { "\(sessionId)/\($0)/\(agent.id)" } ?? "\(sessionId)/\(agent.id)"
```

- [ ] **Step 2: 컴파일 통과 확인**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`. 기존 3개 `AgentRow(...)` 호출(SessionDetailView)은 `workflowId` 기본값으로 무변경.

- [ ] **Step 3: 커밋**

```bash
git add Sources/ClaudeCodeMonitor/Views/AgentRow.swift
git commit -m "feat: AgentRow accepts optional workflowId for nested detail path"
```

---

### Task 8: WorkflowSection 뷰

**Files:**
- Create: `Sources/ClaudeCodeMonitor/Views/WorkflowSection.swift`

- [ ] **Step 1: WorkflowSection 작성**

`Sources/ClaudeCodeMonitor/Views/WorkflowSection.swift`:

```swift
import SwiftUI

/// "Workflows" section shown at the top of SessionDetailView when a session
/// has one or more workflow runs. Running workflows are always expanded with
/// their phase tree; completed workflows collapse to a one-line summary.
///
/// Color/chevron conventions (app-design-conventions): completed uses
/// `.secondary` (never green — green = active only); chevron is
/// right (collapsed) / down (expanded); tinted surface uses opacity 0.08 +
/// continuous corner radius (macOS sidebar-selection tone).
struct WorkflowSection: View {
    let workflows: [WorkflowInfo]
    let sessionId: String
    let projectPath: String

    /// Workflow accent (purple) — distinct from goal's accentColor (blue).
    static let workflowColor = Color(red: 94/255, green: 92/255, blue: 230/255)

    var body: some View {
        if !workflows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    if workflows.contains(where: { $0.isRunning }) {
                        ProgressView().controlSize(.mini)
                    }
                    Text("Workflows")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                ForEach(workflows) { workflow in
                    WorkflowRow(
                        workflow: workflow,
                        sessionId: sessionId,
                        projectPath: projectPath
                    )
                }
            }
        }
    }
}

/// One workflow run. Running = always expanded; completed = collapsible.
private struct WorkflowRow: View {
    let workflow: WorkflowInfo
    let sessionId: String
    let projectPath: String

    @State private var isExpanded: Bool

    init(workflow: WorkflowInfo, sessionId: String, projectPath: String) {
        self.workflow = workflow
        self.sessionId = sessionId
        self.projectPath = projectPath
        // Running workflows start expanded; completed start collapsed.
        _isExpanded = State(initialValue: workflow.isRunning)
    }

    private var tint: Color {
        workflow.isRunning ? WorkflowSection.workflowColor : .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            if isExpanded {
                ForEach(workflow.phases) { phase in
                    phaseView(phase)
                }
            }
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(workflow.isRunning
                      ? WorkflowSection.workflowColor.opacity(0.08)
                      : Color.secondary.opacity(0.06))
        )
        .overlay(alignment: .leading) {
            // Left accent rule.
            Rectangle().fill(tint).frame(width: 2)
        }
        .animation(.easeInOut(duration: 0.15), value: isExpanded)
    }

    @ViewBuilder private var header: some View {
        Button {
            // Only completed workflows toggle; running stays expanded (dead
            // tap target avoided — chevron hidden when running).
            if !workflow.isRunning { isExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                if !workflow.isRunning {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                Text(workflow.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(workflow.isRunning ? WorkflowSection.workflowColor : .primary)
                Spacer()
                Text(summaryLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(workflow.isRunning)

        if workflow.isRunning && !workflow.phases.isEmpty {
            ProgressView(value: progressFraction)
                .tint(WorkflowSection.workflowColor)
                .scaleEffect(x: 1, y: 0.6, anchor: .center)
        }
    }

    private var summaryLine: String {
        let phaseCount = workflow.phases.count
        var parts: [String] = []
        if workflow.isRunning {
            parts.append("실행 중")
        } else {
            parts.append("완료")
        }
        if phaseCount > 0 {
            parts.append("페이즈 \(workflow.completedPhaseCount)/\(phaseCount)")
        }
        parts.append("\(workflow.agentCount) 에이전트")
        parts.append(TokenFormatter.compact(workflow.totalTokens.total) + " tok")
        return parts.joined(separator: " · ")
    }

    private var progressFraction: Double {
        guard workflow.agentCount > 0 else { return 0 }
        return min(1.0, Double(workflow.completedAgentCount) / Double(workflow.agentCount))
    }

    @ViewBuilder private func phaseView(_ phase: WorkflowPhase) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                if phase.isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)   // not green: completed tone
                } else {
                    ProgressView().controlSize(.mini)
                }
                Text(phase.title)
                    .font(.system(size: 9, weight: .medium))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 3)

            ForEach(phase.agents) { agent in
                AgentRow(
                    agent: agent,
                    sessionId: sessionId,
                    projectPath: projectPath,
                    workflowId: workflow.id
                )
                .padding(.leading, 6)
            }
        }
    }
}
```

- [ ] **Step 2: 컴파일 통과 확인**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`. (아직 SessionDetailView에서 호출 안 함.)

- [ ] **Step 3: 커밋**

```bash
git add Sources/ClaudeCodeMonitor/Views/WorkflowSection.swift
git commit -m "feat: add WorkflowSection view with phase tree"
```

---

### Task 9: SessionDetailView에 WorkflowSection 삽입

**Files:**
- Modify: `Sources/ClaudeCodeMonitor/Views/SessionDetailView.swift:20-22` (body 시작부)

- [ ] **Step 1: WorkflowSection 삽입**

`Sources/ClaudeCodeMonitor/Views/SessionDetailView.swift`의 `body`에서 `VStack(alignment: .leading, spacing: 8) {` (20행) 바로 다음, `// Token summary` 주석 앞에 삽입:

```swift
            // Workflow runs (running + recently completed) — shown above the
            // flat agent list so the phase structure stays prominent.
            WorkflowSection(
                workflows: data.workflows,
                sessionId: sessionId,
                projectPath: projectPath
            )
```

- [ ] **Step 2: 컴파일 통과 확인**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`.

- [ ] **Step 3: 앱 번들 빌드 + 실제 워크플로우 세션으로 육안 확인**

Run: `bash scripts/build-app.sh 2>&1 | tail -3 && open ClaudeCodeMonitor.app`
Expected: `==> Done!`. 메뉴바 앱에서 roguelikes-demo 또는 워크플로우를 돌린 세션을 펼치면 상단에
"Workflows" 섹션 + 페이즈 트리(에이전트 라벨)가 보임. 완료 워크플로우는 접힌 한 줄, 클릭 시 펼침.
에이전트 클릭 시 상세(최근 메시지/파일/도구)까지 펼쳐짐.

- [ ] **Step 4: 커밋**

```bash
git add Sources/ClaudeCodeMonitor/Views/SessionDetailView.swift
git commit -m "feat: render WorkflowSection at top of session detail"
```

---

### Task 10: 메뉴바 세션 수 보라 틴트

**Files:**
- Modify: `Sources/ClaudeCodeMonitor/App/ClaudeCodeMonitorApp.swift:28-35`

- [ ] **Step 1: 세션 수 Text의 틴트 로직 교체**

`Sources/ClaudeCodeMonitor/App/ClaudeCodeMonitorApp.swift`의 `Text("\(dataStore.activeSessions.count)")` 블록(28-35행)을 교체:

```swift
                    // Goal/workflow indicator folded into the count color.
                    // Priority: goal (blue accent) > running workflow (purple)
                    // > normal. Goal wins so an explicit /goal is never masked
                    // by a workflow tint. Pulse when either signal is active.
                    Text("\(dataStore.activeSessions.count)")
                        .font(.caption2)
                        .foregroundStyle(countTint)
                        .opacity(pulse && shouldPulse ? 0.4 : 1.0)
                        .animation(shouldPulse
                                   ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
                                   : .default,
                                   value: pulse)
                        .onAppear { pulse = true }
                        .accessibilityLabel(accessibilityText)
```

- [ ] **Step 2: 헬퍼 computed + 펄스 상태 추가**

`ClaudeCodeMonitorApp` struct 안 (body 위, `@State private var dataStore` 다음, 5행 인근)에 추가:

```swift
    /// Drives the count-tint pulse animation.
    @State private var pulse = false
```

그리고 struct 맨 아래(`menuBarIcon` 다음, 56행 인근)에 computed 추가:

```swift
    /// Workflow accent purple — matches WorkflowSection.workflowColor.
    private var workflowPurple: Color {
        Color(red: 94/255, green: 92/255, blue: 230/255)
    }

    /// Count color priority: goal (blue) > running workflow (purple) > normal.
    private var countTint: Color {
        if dataStore.hasActiveGoal { return .accentColor }
        if dataStore.hasRunningWorkflow { return workflowPurple }
        return .primary
    }

    /// Pulse when either a goal or a workflow is active.
    private var shouldPulse: Bool {
        dataStore.hasActiveGoal || dataStore.hasRunningWorkflow
    }

    private var accessibilityText: String {
        let n = dataStore.activeSessions.count
        if dataStore.hasActiveGoal { return "\(n) sessions, goal in progress" }
        if dataStore.hasRunningWorkflow { return "\(n) sessions, workflow running" }
        return "\(n) sessions"
    }
```

- [ ] **Step 3: 컴파일 통과 확인**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`.

- [ ] **Step 4: 앱 번들 빌드 + 육안 확인**

Run: `bash scripts/build-app.sh 2>&1 | tail -3 && open ClaudeCodeMonitor.app`
Expected: `==> Done!`. 워크플로우가 실행 중인 세션이 있으면 메뉴바 세션 수가 보라색으로 은은히 펄스.
(없으면 평소처럼 primary 색. goal과 동시면 파랑 우선.)

- [ ] **Step 5: 커밋**

```bash
git add Sources/ClaudeCodeMonitor/App/ClaudeCodeMonitorApp.swift
git commit -m "feat: tint menu-bar session count purple when a workflow is running"
```

---

### Task 11: 버전 0.6.0 bump + CHANGELOG

**Files:**
- Modify: `Info.plist:13-16`
- Modify: `CHANGELOG.md:8` (`## [Unreleased]` 아래)

- [ ] **Step 1: Info.plist 버전 갱신**

`Info.plist:14` `<string>8</string>` → `<string>9</string>`
`Info.plist:16` `<string>0.5.0</string>` → `<string>0.6.0</string>`

- [ ] **Step 2: CHANGELOG 항목 추가**

`CHANGELOG.md`의 `## [Unreleased]`(8행) 아래에 삽입:

```markdown
## [0.6.0] - 2026-05-30

### Added
- **워크플로우 가시성.** dynamic workflow(에이전트 fan-out) 실행이 이제
  세션 확장 뷰 상단의 "Workflows" 섹션에 페이즈별 에이전트 트리로 표시됨.
  기존에는 워크플로우 에이전트가 `subagents/workflows/{id}/`(한 단계 깊은
  경로)에 기록되어 `SubagentLoader`가 전혀 보지 못했음. 실행 중 워크플로우는
  페이즈 트리가 펼쳐지고 진행률 바·누적 토큰을 표시하며, 완료된 워크플로우는
  접힌 요약으로 보여줌. 메뉴바 세션 수는 워크플로우 실행 중일 때 보라색으로
  은은히 펄스(`/goal` 진행 시에는 파랑 우선). 실행 중 판정은 `journal.jsonl`의
  미완료 `started` 이벤트로 감지(`workflows/{id}.json`은 완료 시점에만 기록되므로).
```

- [ ] **Step 3: 버전 확인**

Run: `grep -A1 -E 'CFBundle(Version|ShortVersionString)' Info.plist`
Expected: `CFBundleVersion` = `9`, `CFBundleShortVersionString` = `0.6.0`.

- [ ] **Step 4: 앱 번들 빌드 (버전 반영 확인)**

Run: `bash scripts/build-app.sh 2>&1 | tail -3`
Expected: `==> Done!`.

- [ ] **Step 5: 커밋 (rebuilt 번들 포함 — 기존 릴리스 관행)**

```bash
git add Info.plist CHANGELOG.md ClaudeCodeMonitor.app/Contents/Info.plist ClaudeCodeMonitor.app/Contents/MacOS/ClaudeCodeMonitor
git commit -m "release: v0.6.0 — workflow visibility"
```

---

### Task 12: 최종 검증

- [ ] **Step 1: 전체 빌드 클린 확인**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`.

- [ ] **Step 2: 실제 워크플로우 세션 육안 확인 (강력 권장)**

Run: `open ClaudeCodeMonitor.app`
Expected:
- 워크플로우 실행 이력이 있는 세션(roguelikes-demo, geo-builder 등)을 펼치면 상단 "Workflows" 섹션.
- 완료 워크플로우: 접힌 한 줄 요약 → 클릭 시 페이즈 트리(✓ 완료 페이즈는 회색 체크, 에이전트 점 없음).
- 일반 에이전트가 같이 있는 세션(geo-builder)은 Workflows 아래에 기존 Active/Completed 목록 그대로.
- 에이전트 클릭 → 상세(최근 메시지/수정 파일/도구) 펼쳐짐.

- [ ] **Step 3: git 상태 정리 확인**

Run: `git log --oneline -13 && git status`
Expected: Task 1-11의 커밋들, working tree 깨끗(추적 안 되는 .zip/.mov 제외).

---

## 변경하지 않는 것 (확인 완료, 무변경)

- `JSONLParser` / `parseRecentMessages` / `extractFileChanges` — 워크플로우 에이전트 JSONL도 동일 포맷, 그대로 재사용.
- `AgentDetailView` — `AgentDetailData`만 소비, 무변경.
- `TaskLoader` — 무관.
- `MenuBarDotState` / `MenuBarDot` — 상태점 우선순위 스택 무변경 (틴트는 세션 수 텍스트에만).
- `SubagentLoader`의 외부 동작 — Task 4는 순수 리팩터(scan 추출), 결과 동일.

## 실행 순서 주의

Task 간 의존성: **1 → 2 → 4 → 3 → 5 → 6 → 7 → 8 → 9 → 10 → 11 → 12**.
(Task 4의 `SubagentScan` 추출이 Task 3의 `WorkflowLoader.loadAgents`가 의존하는 `SubagentScan.scan`을
제공하므로 4를 3보다 먼저 실행.)

## 작업 후 후속 (계획 외)

- 메모리 `workflow_visibility_project.md` 갱신 (배포 완료 표기).
- v0.6.0 릴리스 메모 추가.
- `app_design_conventions.md`에 "워크플로우 보라(#5e5ce6) = workflow 신호색" 팔레트 항목 추가 검토.
