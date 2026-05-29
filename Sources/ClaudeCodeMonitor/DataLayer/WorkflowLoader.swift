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
