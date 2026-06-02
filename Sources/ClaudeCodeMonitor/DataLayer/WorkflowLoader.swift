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

    /// Per-agent terminal states from `workflowProgress`. Once an agent reaches
    /// one of these it will not progress further, so its phase should read as
    /// complete regardless of file mtime.
    private static let terminalAgentStates: Set<String> = ["done", "error"]

    /// Extract phase titles from a workflow script's `meta.phases` literal.
    ///
    /// Mid-run there is no `workflows/{id}.json`, but the script
    /// (`scripts/{name}-{id}.js`, written at start) carries a pure-literal
    /// `meta.phases: [{title, detail}, …]`. This recovers just the ordered
    /// titles — agents cannot be attributed to phases while running, so the
    /// running view shows the plan skeleton only. Returns [] if absent.
    static func phaseTitles(fromScript js: String) -> [String] {
        // Anchor at the meta block so a schema property named "phases"
        // elsewhere in the script can't be matched first.
        let searchStart = js.range(of: "export const meta")?.upperBound ?? js.startIndex
        guard let phasesKw = js.range(of: "phases", range: searchStart..<js.endIndex),
              let open = js.range(of: "[", range: phasesKw.upperBound..<js.endIndex)
        else { return [] }

        // Walk to the matching ']' (bracket-balanced; tolerates ']' in strings
        // well enough for the literal-only meta block).
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

    /// Build phases from a `workflowProgress` array, attaching each agent's
    /// label as the SubagentInfo description. Phases come out in index order.
    ///
    /// Phase completeness is driven by each agent's authoritative `state`
    /// field ("done"/"error" = terminal) — NOT by `SubagentInfo.isActive`,
    /// which is a 60s mtime heuristic. Using mtime made a just-finished
    /// workflow read as "phase 0/n" until 60s elapsed, and the loader's
    /// mtime-cache then froze that wrong snapshot permanently. When a progress
    /// entry carries no `state` (older runs), completeness falls back to the
    /// mtime heuristic so nothing regresses for data without state.
    static func mapAgentsToPhases(
        progress: [[String: Any]],
        agentsById: [String: SubagentInfo],
        workflowCompleted: Bool = false
    ) -> [WorkflowPhase] {
        // Collect phase definitions, ordered by index.
        var phaseTitles: [(index: Int, title: String)] = []
        // phaseIndex -> [(orderIndex, labelledAgent, state)]
        var phaseAgents: [Int: [(order: Int, agent: SubagentInfo, state: String?)]] = [:]

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
                let state = item["state"] as? String
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
                    phaseAgents[phaseIndex, default: []].append((order, agent, state))
                }
            }
        }

        return phaseTitles
            .sorted { $0.index < $1.index }
            .map { phase in
                let entries = (phaseAgents[phase.index] ?? []).sorted { $0.order < $1.order }
                let agents = entries.map { $0.agent }
                // An empty declared phase ran no agents — either the workflow
                // conditionally skipped it (done) or it hasn't started yet
                // (pending). It mirrors the workflow's terminal status.
                // For non-empty phases, terminal `state` is authoritative;
                // absent state falls back to the mtime heuristic.
                let isComplete: Bool
                if entries.isEmpty {
                    isComplete = workflowCompleted
                } else {
                    isComplete = entries.allSatisfy { entry in
                        if let state = entry.state {
                            return terminalAgentStates.contains(state)
                        }
                        return !entry.agent.isActive
                    }
                }
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
               prev.status == .completed,
               let prevMtime = prev.lastActivity,
               let curMtime = dirMtime,
               prevMtime == curMtime {
                workflows.append(prev)
                continue
            }

            // Parse agent transcripts (reuse SubagentLoader's per-agent scan).
            let agentsById = loadAgents(in: agentDir)

            // Run-state JSON (written only at completion). Read first so a
            // completed-status file is a definitive "done" signal.
            let stateURL = wfStateDir.appendingPathComponent("\(wfId).json")
            let state = (try? Data(contentsOf: stateURL))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }

            // Running-detection. A present state JSON with status "completed"
            // is definitive (the file is only written at completion). Absent
            // that, an unfinished journal agent — or a freshly-touched dir —
            // means still running.
            let journal = WorkflowJournal.parse(
                fileAt: agentDir.appendingPathComponent("journal.jsonl"))
            let completedByState = (state?["status"] as? String) == "completed"
            let fresh = dirMtime.map { Date().timeIntervalSince($0) < activityWindow } ?? false
            let isRunning = !completedByState && (journal.hasUnfinishedAgents || fresh)

            // Name: json.workflowName → scripts filename → wfId.
            let name = (state?["workflowName"] as? String)
                ?? scriptName(in: wfScriptsDir, wfId: wfId, fm: fm)
                ?? wfId

            // Flat agent list (most-recent first) — the running view's rows,
            // and the file-sum fallback source for aggregates.
            let flatAgents = Array(agentsById.values)
                .sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }

            // Authoritative aggregates: trust the completion-time state JSON
            // (its totals are logical-agent figures, excluding the retry and
            // nested-subagent files that inflate a raw on-disk sweep — e.g.
            // 188 files vs 87 logical agents). While running, sum what's there.
            var fileTokens = 0, fileToolCalls = 0
            for agent in agentsById.values {
                fileTokens += agent.tokens.total
                fileToolCalls += agent.toolUseCount
            }
            let totalTokens = (state?["totalTokens"] as? Int) ?? fileTokens
            let totalToolCalls = (state?["totalToolCalls"] as? Int) ?? fileToolCalls

            let progress = state?["workflowProgress"] as? [[String: Any]] ?? []
            let phases: [WorkflowPhase]
            let agentCount: Int
            let doneAgentCount: Int

            if isRunning {
                // No agentId→phase mapping exists mid-run; show the plan
                // skeleton (titles only) from the script's meta.phases.
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

    /// Read the script JS for a wf_id (carries `meta.phases`, written at start).
    private static func scriptContents(in scriptsDir: URL, wfId: String, fm: FileManager) -> String? {
        guard let files = try? fm.contentsOfDirectory(atPath: scriptsDir.path),
              let match = files.first(where: { $0.contains(wfId) && $0.hasSuffix(".js") })
        else { return nil }
        return try? String(contentsOf: scriptsDir.appendingPathComponent(match), encoding: .utf8)
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
