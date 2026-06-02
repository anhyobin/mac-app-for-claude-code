# Workflow Live Visibility — Implementation Plan

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax. TDD via the standalone harness (XCTest unavailable on this CLT-only machine — compile real sources with `xcrun --sdk macosx swiftc`).

**Goal:** Show honest, data-backed progress for a workflow *while it runs* — the phase plan (names/order) plus a "M/N agents done" aggregate — and make the running→completed numbers consistent.

**Architecture:** Three data realities, established empirically against `~/.claude/projects/*/*/workflows/`:
1. **Per-agent phase attribution is impossible mid-run** (measured 5% recoverable; only 4/44 `agent()` call-sites have static prompts, the rest are loop-interpolated). So we do NOT attribute agents to phases while running.
2. **`meta.phases` IS reliably parseable** from `workflows/scripts/{name}-{id}.js` (17/17 match vs ground truth), and that script is written ~2–4 ms after `startTime` → available the whole run. → phase **skeleton** (titles/order only).
3. **`journal.jsonl`** gives live `started`/`result` counts → accurate aggregate "M/N done".
   On completion, `workflows/{id}.json` carries authoritative pre-computed `agentCount`/`totalTokens`/`totalToolCalls` (the logical-agent totals, excluding retries/nested), which we trust instead of re-summing all on-disk agent files (188 files vs 87 logical for the deep run).

**Tech Stack:** Swift + SwiftUI; `NSRegularExpression`; existing `WorkflowJournal`, `WorkflowLoader`, `WorkflowSection`.

---

## Re-review of the earlier (this-session) fix — KEEP

The completed-path fix (phase `isComplete` from per-agent `state` instead of mtime; empty/skipped phase inherits workflow status) is **correct** — verified 23/23 real completed workflows show accurate `n/n`, and the mtime-stuck-cache bug is gone. **Keep it.** It is, however, **incomplete**: it only touched the completed path. It also surfaced a third bug (token/agent over-counting from retry + nested files) folded into Task 4 below.

---

## File Structure

- `Sources/.../DataLayer/WorkflowJournal.swift` — add `finishedCount`/`startedCount` to `Summary`.
- `Sources/.../DataLayer/WorkflowLoader.swift` — add `phaseTitles(fromScript:)`; build skeleton phases when running; use journal counts (running) and state aggregates (completed).
- `Sources/.../Models/WorkflowInfo.swift` — `totalTokens: TokenUsage` → `Int`; add `agents: [SubagentInfo]` + `doneAgentCount: Int`; remove mtime-based `completedAgentCount`.
- `Sources/.../Views/WorkflowSection.swift` — running = phase-plan breadcrumb + aggregate + flat agents; completed = phase tree (unchanged).
- `Tests/.../WorkflowLoaderTests.swift` — add `phaseTitles` parsing tests.

---

## Task 1: Journal exposes started/finished counts

**Files:** Modify `Sources/ClaudeCodeMonitor/DataLayer/WorkflowJournal.swift`; harness test.

- [ ] **Step 1: Failing test** (add to harness `main.swift`)

```swift
do {
    let s = WorkflowJournal.parse(text: """
    {"type":"started","agentId":"a1"}
    {"type":"started","agentId":"a2"}
    {"type":"started","agentId":"a3"}
    {"type":"result","agentId":"a1"}
    {"type":"result","agentId":"a2"}
    """)
    check(s.startedCount == 3, "startedCount counts distinct started")
    check(s.finishedCount == 2, "finishedCount counts started-and-resulted")
}
```

- [ ] **Step 2: Run harness → FAIL** (`startedCount`/`finishedCount` undefined).

- [ ] **Step 3: Implement** — add to `Summary`:

```swift
var startedCount: Int { startedAgentIds.count }
var finishedCount: Int { startedAgentIds.count - unfinishedAgentIds.count }
```

- [ ] **Step 4: Run harness → PASS.**
- [ ] **Step 5: Commit** `feat: WorkflowJournal exposes started/finished counts`

---

## Task 2: Parse `meta.phases` titles from the script

**Files:** Modify `WorkflowLoader.swift`; tests in `WorkflowLoaderTests.swift` + harness.

- [ ] **Step 1: Failing tests**

```swift
// XCTest
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
func testPhaseTitlesNoMetaReturnsEmpty() {
    XCTAssertEqual(WorkflowLoader.phaseTitles(fromScript: "const a = 1"), [])
}
```

- [ ] **Step 2: Run → FAIL** (method undefined).

- [ ] **Step 3: Implement** in `WorkflowLoader` (bracket-balanced scan + regex, robust to `]` inside detail strings):

```swift
/// Extract phase titles from a workflow script's `meta.phases` literal.
/// Returns [] if absent/unparseable (caller falls back to no skeleton).
static func phaseTitles(fromScript js: String) -> [String] {
    // Anchor at the meta block when present so a schema property named
    // "phases" elsewhere can't be picked up first.
    let searchStart = js.range(of: "export const meta")?.upperBound ?? js.startIndex
    guard let phasesKw = js.range(of: "phases", range: searchStart..<js.endIndex),
          let open = js.range(of: "[", range: phasesKw.upperBound..<js.endIndex)
    else { return [] }

    // Walk to the matching ']'.
    var depth = 0
    var endIdx: String.Index?
    var i = open.lowerBound
    while i < js.endIndex {
        switch js[i] {
        case "[": depth += 1
        case "]":
            depth -= 1
            if depth == 0 { endIdx = i }
        default: break
        }
        if endIdx != nil { break }
        i = js.index(after: i)
    }
    guard let end = endIdx else { return [] }
    let literal = String(js[open.lowerBound...end])

    guard let re = try? NSRegularExpression(
        pattern: "title\\s*:\\s*['\"]([^'\"]+)['\"]") else { return [] }
    let ns = literal as NSString
    return re.matches(in: literal, range: NSRange(location: 0, length: ns.length))
        .compactMap { m in m.numberOfRanges > 1 ? ns.substring(with: m.range(at: 1)) : nil }
}
```

- [ ] **Step 4: Run → PASS.** Also re-run the real-disk parse check (expect 17/17).
- [ ] **Step 5: Commit** `feat: parse meta.phases titles from workflow script`

---

## Task 3: WorkflowInfo model — Int tokens, flat agents, stored done count

**Files:** Modify `Models/WorkflowInfo.swift`.

- [ ] **Step 1:** Update the struct:

```swift
struct WorkflowInfo: Identifiable, Sendable {
    let id: String
    let name: String
    let status: WorkflowRunStatus
    let phases: [WorkflowPhase]      // running: skeleton (titles, empty agents); completed: full tree
    let agents: [SubagentInfo]       // flat list (all referenced/known agents), for the running view
    let totalTokens: Int             // was TokenUsage; view only ever needs the total
    let totalToolCalls: Int
    let agentCount: Int              // denominator
    let doneAgentCount: Int          // numerator (running: journal results; completed: == agentCount)
    let durationMs: Int?
    let lastActivity: Date?

    var isRunning: Bool { status == .running }

    /// Phases fully complete — meaningful only once completed (running skeleton = 0).
    var completedPhaseCount: Int { phases.filter { $0.isComplete }.count }
}
```

(Removes the mtime-based `completedAgentCount`.)

- [ ] **Step 2:** `swift build` will fail at the loader + view call sites — fixed in Tasks 4–5. No commit until green.

---

## Task 4: Loader builds running skeleton + consistent aggregates

**Files:** Modify `WorkflowLoader.loadWorkflows` + add `scriptContents` helper.

- [ ] **Step 1:** Add a script-reading helper next to `scriptName`:

```swift
private static func scriptContents(in scriptsDir: URL, wfId: String, fm: FileManager) -> String? {
    guard let files = try? fm.contentsOfDirectory(atPath: scriptsDir.path),
          let match = files.first(where: { $0.contains(wfId) && $0.hasSuffix(".js") })
    else { return nil }
    return try? String(contentsOf: scriptsDir.appendingPathComponent(match), encoding: .utf8)
}
```

- [ ] **Step 2:** Replace the phases/aggregate block (current lines ~163–214) with:

```swift
            // Authoritative aggregates: trust the completed state JSON when
            // present (its totals are the logical-agent figures, excluding
            // retry/nested files that inflate a raw file sweep). While running,
            // sum what's on disk.
            var fileTokens = 0, fileToolCalls = 0
            for agent in agentsById.values {
                fileTokens += agent.tokens.total
                fileToolCalls += agent.toolUseCount
            }
            let totalTokens = (state?["totalTokens"] as? Int) ?? fileTokens
            let totalToolCalls = (state?["totalToolCalls"] as? Int) ?? fileToolCalls

            // Flat agent list (sorted most-recent-first) for the running view.
            let flatAgents = Array(agentsById.values)
                .sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }

            let progress = state?["workflowProgress"] as? [[String: Any]] ?? []
            let phases: [WorkflowPhase]
            let agentCount: Int
            let doneAgentCount: Int

            if isRunning {
                // Skeleton from the script's meta.phases (titles only — agents
                // can't be attributed to phases mid-run).
                let titles = scriptContents(in: wfScriptsDir, wfId: wfId, fm: fm)
                    .map { phaseTitles(fromScript: $0) } ?? []
                phases = titles.enumerated().map { idx, title in
                    WorkflowPhase(id: idx, title: title, agents: [], isComplete: false)
                }
                // Live aggregate from the journal; fall back to file count.
                agentCount = journal.startedCount > 0 ? journal.startedCount : flatAgents.count
                doneAgentCount = journal.finishedCount
            } else {
                phases = progress.isEmpty
                    ? []
                    : mapAgentsToPhases(progress: progress, agentsById: agentsById, workflowCompleted: true)
                agentCount = (state?["agentCount"] as? Int) ?? flatAgents.count
                doneAgentCount = agentCount   // completed → all done
            }

            workflows.append(WorkflowInfo(
                id: wfId,
                name: name,
                status: isRunning ? .running : .completed,
                phases: phases,
                agents: flatAgents,
                totalTokens: totalTokens,
                totalToolCalls: totalToolCalls,
                agentCount: agentCount,
                doneAgentCount: doneAgentCount,
                durationMs: state?["durationMs"] as? Int,
                lastActivity: dirMtime
            ))
```

- [ ] **Step 3:** Run the real-disk harness — expect completed runs still `n/n` (0 mismatch) AND token totals now equal `state.totalTokens` (no retry inflation).
- [ ] **Step 4: Commit** `fix: running skeleton phases + state-authoritative aggregates`

---

## Task 5: View — running breadcrumb + aggregate + flat agents

**Files:** Modify `Views/WorkflowSection.swift`.

- [ ] **Step 1:** `summaryLine` — agents-done for running, phase-count for completed:

```swift
private var summaryLine: String {
    var parts: [String] = []
    if workflow.isRunning {
        parts.append("running")
        parts.append("\(workflow.doneAgentCount)/\(workflow.agentCount) agents")
    } else {
        parts.append("completed")
        if !workflow.phases.isEmpty {
            parts.append("phase \(workflow.completedPhaseCount)/\(workflow.phases.count)")
        }
        parts.append("\(workflow.agentCount) agents")
    }
    parts.append(TokenFormatter.compact(workflow.totalTokens) + " tok")
    return parts.joined(separator: " · ")
}

private var progressFraction: Double {
    guard workflow.agentCount > 0 else { return 0 }
    return min(1.0, Double(workflow.doneAgentCount) / Double(workflow.agentCount))
}
```

- [ ] **Step 2:** `body` — branch running vs completed:

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 4) {
        header
        if workflow.isRunning {
            if workflow.phases.count > 1 { phasePlanView }
            ForEach(workflow.agents) { agent in
                AgentRow(agent: agent, sessionId: sessionId,
                         projectPath: projectPath, workflowId: workflow.id)
                    .padding(.leading, 6)
            }
        } else if isExpanded {
            ForEach(workflow.phases) { phase in phaseView(phase) }
        }
    }
    .padding(7)
    .background( /* unchanged */ )
    .overlay(alignment: .leading) { Rectangle().fill(tint).frame(width: 2) }
    .animation(.easeInOut(duration: 0.15), value: isExpanded)
}

/// Honest "we know the plan, not the per-phase attribution" breadcrumb.
private var phasePlanView: some View {
    HStack(spacing: 4) {
        Image(systemName: "list.bullet.indent").font(.system(size: 8)).foregroundStyle(.tertiary)
        Text(workflow.phases.map(\.title).joined(separator: " → "))
            .font(.caption2).foregroundStyle(.secondary)
            .lineLimit(1).truncationMode(.tail)
    }
    .padding(.leading, 2)
}
```

- [ ] **Step 3:** `swift build` → clean.
- [ ] **Step 4: Commit** `feat: running workflow shows phase plan + agent aggregate`

---

## Self-Review

- **Spec coverage:** live phase skeleton (Task 2+4+5), live aggregate (Task 1+4+5), nested/retry count consistency (Task 4 state-authoritative aggregates), keep completed fix (Tasks unchanged from this session). ✓
- **Type consistency:** `totalTokens: Int` flows loader→model→view (`TokenFormatter.compact(_:Int)` ✓). `doneAgentCount`/`agents` defined in Task 3, produced in Task 4, consumed in Task 5. ✓
- **No placeholders:** all steps carry real code. ✓
