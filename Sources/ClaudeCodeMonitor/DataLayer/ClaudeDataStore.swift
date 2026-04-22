import Foundation
import SwiftUI

@MainActor
@Observable
final class ClaudeDataStore {
    var activeSessions: [ActiveSession] = []
    var recentSessions: [SessionLog] = []
    var expandedSessionData: [String: SessionExpandedData] = [:]
    var agentDetailData: [String: AgentDetailData] = [:]

    private var isMonitoring = false
    private var fileWatcher: FileWatcher?
    private var recentRefreshCounter = 0
    private var pendingRecentRefresh = false
    private var lastRecentRefreshTime: Date = .distantPast

    private static let projectsDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }()

    private static let sessionsDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions")
    }()

    init() {
        startMonitoring()
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        refreshActiveSessions()
        refreshRecentSessions()
        startFileWatcher()

        Task {
            while isMonitoring {
                try? await Task.sleep(for: .seconds(5))
                refreshActiveSessions()
                recentRefreshCounter += 1
                if recentRefreshCounter >= 6 { // 30s = 6 * 5s
                    recentRefreshCounter = 0
                    refreshRecentSessions()
                }
                // Auto-refresh expanded active sessions (agents + tasks update in real-time)
                await refreshExpandedActiveSessions()
            }
        }
    }

    func forceRefresh() {
        refreshActiveSessions()
        refreshRecentSessions()
        agentDetailData.removeAll()
        Task { await refreshExpandedActiveSessions() }
    }

    func stopMonitoring() {
        isMonitoring = false
        fileWatcher?.stop()
        fileWatcher = nil
    }

    private func startFileWatcher() {
        let sessionsPath = Self.sessionsDirectory.path

        // Only watch sessions/ directory — projects/ changes are picked up by the 30s timer.
        // Watching projects/ caused CPU spikes during agent team work (hundreds of JSONL writes/sec).
        fileWatcher = FileWatcher(paths: [sessionsPath]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isMonitoring else { return }
                self.refreshActiveSessions()
            }
        }
        fileWatcher?.start()
    }

    private func refreshActiveSessions() {
        activeSessions = SessionFileReader.readActiveSessions()
        evictStaleCache()

        // Eagerly load session details for all active sessions (for token badge display)
        for session in activeSessions where expandedSessionData[session.id] == nil {
            Task {
                await loadSessionDetail(sessionId: session.id, projectPath: session.cwd)
            }
        }
    }

    private func refreshExpandedActiveSessions() async {
        let activeIds = Set(activeSessions.map(\.id))
        for sessionId in expandedSessionData.keys where activeIds.contains(sessionId) {
            guard let session = activeSessions.first(where: { $0.id == sessionId }) else { continue }
            await loadSessionDetail(sessionId: sessionId, projectPath: session.cwd, forceRefresh: true)

            // Only refresh detail for agents that are still active
            for key in agentDetailData.keys where key.hasPrefix(sessionId + "/") {
                let agentHash = String(key.dropFirst(sessionId.count + 1))
                if let agents = expandedSessionData[sessionId]?.agents,
                   let agent = agents.first(where: { $0.id == agentHash }),
                   agent.isActive {
                    await loadAgentDetail(sessionId: sessionId, agentHash: agentHash, projectPath: session.cwd, forceRefresh: true)
                }
            }
        }
    }

    private func evictStaleCache() {
        let activeIds = Set(activeSessions.map(\.id))
        let recentIds = Set(recentSessions.map(\.id))
        let validIds = activeIds.union(recentIds)

        for key in expandedSessionData.keys where !validIds.contains(key) {
            expandedSessionData.removeValue(forKey: key)
        }

        for key in agentDetailData.keys {
            let sessionId = String(key.prefix(while: { $0 != "/" }))
            if !validIds.contains(sessionId) {
                agentDetailData.removeValue(forKey: key)
            }
        }
    }

    private func refreshRecentSessions() {
        let activeSessionIds = Set(activeSessions.map(\.id))
        Task {
            let results = await Task.detached {
                Self.scanRecentSessions(excluding: activeSessionIds)
            }.value
            self.recentSessions = results
        }
    }

    private nonisolated static func scanRecentSessions(excluding activeIds: Set<String>) -> [SessionLog] {
        let fm = FileManager.default
        let projDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        let projectsDir = projDir.path

        guard fm.fileExists(atPath: projectsDir) else { return [] }

        guard let projectDirs = try? fm.contentsOfDirectory(atPath: projectsDir) else {
            print("[ClaudeDataStore] Failed to list projects directory")
            return []
        }

        var jsonlFiles: [(url: URL, mtime: Date)] = []

        for dir in projectDirs {
            guard dir.count > 1 else { continue } // Skip global "-" directory
            let projectDir = projDir.appendingPathComponent(dir)
            guard let files = try? fm.contentsOfDirectory(atPath: projectDir.path) else { continue }

            for file in files where file.hasSuffix(".jsonl") {
                let fileURL = projectDir.appendingPathComponent(file)
                guard let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
                      let mtime = attrs[.modificationDate] as? Date else { continue }
                jsonlFiles.append((url: fileURL, mtime: mtime))
            }
        }

        // Sort by modification time, most recent first, take top 10
        jsonlFiles.sort { $0.mtime > $1.mtime }
        let candidates = jsonlFiles.prefix(20) // scan more to find 10 non-active

        var results: [SessionLog] = []
        for file in candidates {
            guard results.count < 10 else { break }
            guard let log = JSONLParser.scanSessionSummary(at: file.url) else { continue }
            if activeIds.contains(log.id) { continue }
            results.append(log)
        }

        return results
    }

    // MARK: - Menu Bar Dot State

    /// Aggregate status for the menu-bar dot across all active sessions.
    ///
    /// Priority stack (highest first): error > warning > processing > active
    /// > inactive > hidden. Only one state is surfaced; if one session is
    /// in warning and another is only inactive, the dot shows warning.
    ///
    /// v0.2 scope:
    /// - `processing` is NOT computed — detecting "tool_use without a matching
    ///   tool_result" would require an extra JSONL pass per 5s refresh per
    ///   session. Revisit after the view is wired up. See TODO(v0.3) inline.
    /// - `error` is raised when the main session JSONL is truncated (exceeds
    ///   the 50MB parser cap). Parser / filesystem failures that return
    ///   `truncated: true` otherwise also surface here.
    var menuBarDotState: MenuBarDotState {
        guard !activeSessions.isEmpty else { return .hidden }

        let activityWindow: TimeInterval = 60
        let warningThreshold: Double = 0.95
        let now = Date()

        var highest: MenuBarDotState = .inactive

        for session in activeSessions {
            let expanded = expandedSessionData[session.id]

            // Error: main session JSONL couldn't be parsed (oversize / read
            // failure). A truncated session is exactly the case where the
            // window is most likely full, so surface it above warning.
            if expanded?.mainTruncated == true,
               MenuBarDotState.error.priority > highest.priority {
                highest = .error
                continue
            }

            // Warning: context window ≥ 95% full. Needs both expanded data
            // (for the last-turn snapshot) AND a known model (for the limit).
            // Sessions that haven't been expanded yet, or whose model we
            // can't identify, can't trigger warning — they fall through.
            if let expanded,
               let model = expanded.mainModel,
               let ratio = expanded.contextUsageRatio(model: model),
               ratio >= warningThreshold,
               MenuBarDotState.warning.priority > highest.priority {
                highest = .warning
                continue
            }

            // TODO(v0.3): processing state — detect unmatched tool_use blocks
            // via a lightweight tail-scan of the main session JSONL. Skipped
            // in v0.2 because the scan would run per-refresh per-session.

            // Active vs. inactive: use the main JSONL's mtime as a proxy for
            // "last assistant turn". Active sessions are eagerly expanded so
            // mainJSONLMtime should be populated for anything beyond its very
            // first refresh cycle; before that the session stays at inactive.
            // NOTE: `session.lastActivity` is currently always nil (see
            // SessionFileReader), so the fallback is effectively dead. Kept as
            // a no-op so a future SessionFileReader enhancement that populates
            // lastActivity would wire through automatically.
            let lastActivity = expanded?.mainJSONLMtime ?? session.lastActivity
            if let lastActivity, now.timeIntervalSince(lastActivity) < activityWindow {
                if MenuBarDotState.active.priority > highest.priority {
                    highest = .active
                }
            }
            // Otherwise `highest` stays at its current value (the loop's
            // initial `.inactive`, or a stronger state from a prior session).
        }

        return highest
    }

    func loadSessionDetail(sessionId: String, projectPath: String, forceRefresh: Bool = false) async {
        // Return cached data if available (unless force refresh)
        if !forceRefresh, expandedSessionData[sessionId] != nil { return }

        let previousAgents = expandedSessionData[sessionId]?.agents
        let previousMtime = expandedSessionData[sessionId]?.mainJSONLMtime
        let previousMainTokens = expandedSessionData[sessionId]?.mainTokens
        let previousThinking = expandedSessionData[sessionId]?.mainThinkingBlockCount
        let previousModel = expandedSessionData[sessionId]?.mainModel
        let previousLastTurn = expandedSessionData[sessionId]?.mainLastTurnUsage
        let previousTruncated = expandedSessionData[sessionId]?.mainTruncated ?? false
        let previousMainSkillCounts = expandedSessionData[sessionId]?.mainSkillCounts

        let result = await Task.detached {
            let agents = SubagentLoader.loadAgents(
                sessionId: sessionId,
                projectPath: projectPath,
                previousAgents: previousAgents
            )
            let tasks = TaskLoader.loadTasks(for: sessionId)

            // Parse main session JSONL for tokens (with mtime caching)
            let encodedPath = PathDecoder.encodedProjectPath(from: projectPath)
            let mainJSONLPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/projects")
                .appendingPathComponent(encodedPath)
                .appendingPathComponent("\(sessionId).jsonl")

            let currentMtime: Date? = {
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: mainJSONLPath.path) else { return nil }
                return attrs[.modificationDate] as? Date
            }()

            // Reuse cached main-session stats when mtime is unchanged —
            // parsing a large JSONL per refresh is the hottest operation in
            // the app, so all derived values share the same cache gate.
            let mainTokens: TokenUsage
            let mainThinkingBlockCount: Int
            let mainModel: String?
            let mainLastTurnUsage: TokenUsage?
            let mainTruncated: Bool
            let mainSkillCounts: [String: Int]
            if let prevMtime = previousMtime,
               let curMtime = currentMtime,
               prevMtime == curMtime,
               let cachedTokens = previousMainTokens,
               let cachedThinking = previousThinking,
               let cachedSkills = previousMainSkillCounts {
                mainTokens = cachedTokens
                mainThinkingBlockCount = cachedThinking
                mainModel = previousModel
                mainLastTurnUsage = previousLastTurn
                mainTruncated = previousTruncated
                mainSkillCounts = cachedSkills
            } else {
                let stats = JSONLParser.scanTokensAndThinking(at: mainJSONLPath)
                mainTokens = stats.tokens
                mainThinkingBlockCount = stats.thinkingBlockCount
                mainModel = stats.model
                mainLastTurnUsage = stats.lastTurnUsage
                mainTruncated = stats.truncated
                mainSkillCounts = stats.skillCounts
            }

            // Total = main session tokens + all subagent tokens
            var totalTokens = mainTokens
            for agent in agents {
                totalTokens.add(agent.tokens)
            }

            return SessionExpandedData(
                agents: agents,
                tasks: tasks,
                mainTokens: mainTokens,
                totalTokens: totalTokens,
                mainJSONLMtime: currentMtime,
                mainThinkingBlockCount: mainThinkingBlockCount,
                mainModel: mainModel,
                mainLastTurnUsage: mainLastTurnUsage,
                mainTruncated: mainTruncated,
                mainSkillCounts: mainSkillCounts
            )
        }.value

        expandedSessionData[sessionId] = result
    }

    func loadAgentDetail(sessionId: String, agentHash: String, projectPath: String, forceRefresh: Bool = false) async {
        let key = "\(sessionId)/\(agentHash)"
        if !forceRefresh, agentDetailData[key] != nil { return }

        // Get full tool & skill breakdowns from already-loaded SubagentInfo
        let cachedBreakdown = expandedSessionData[sessionId]?
            .agents.first { $0.id == agentHash }?.toolBreakdown ?? [:]
        let cachedSkills = expandedSessionData[sessionId]?
            .agents.first { $0.id == agentHash }?.skillCounts ?? [:]

        let encodedPath = PathDecoder.encodedProjectPath(from: projectPath)
        let projectsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")

        let result = await Task.detached {
            let agentPath = projectsDir
                .appendingPathComponent(encodedPath)
                .appendingPathComponent(sessionId)
                .appendingPathComponent("subagents")
                .appendingPathComponent("agent-\(agentHash).jsonl")

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
    }
}
