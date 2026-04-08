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

    func loadSessionDetail(sessionId: String, projectPath: String, forceRefresh: Bool = false) async {
        // Return cached data if available (unless force refresh)
        if !forceRefresh, expandedSessionData[sessionId] != nil { return }

        let previousAgents = expandedSessionData[sessionId]?.agents
        let previousMtime = expandedSessionData[sessionId]?.mainJSONLMtime
        let previousMainTokens = expandedSessionData[sessionId]?.mainTokens

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

            // Reuse cached mainTokens if mtime unchanged (skip expensive re-parse)
            let mainTokens: TokenUsage
            if let prevMtime = previousMtime,
               let curMtime = currentMtime,
               prevMtime == curMtime,
               let cached = previousMainTokens {
                mainTokens = cached
            } else {
                mainTokens = JSONLParser.scanTokensOnly(at: mainJSONLPath)
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
                mainJSONLMtime: currentMtime
            )
        }.value

        expandedSessionData[sessionId] = result
    }

    func loadAgentDetail(sessionId: String, agentHash: String, projectPath: String, forceRefresh: Bool = false) async {
        let key = "\(sessionId)/\(agentHash)"
        if !forceRefresh, agentDetailData[key] != nil { return }

        // Get full tool breakdown from already-loaded SubagentInfo
        let cachedBreakdown = expandedSessionData[sessionId]?
            .agents.first { $0.id == agentHash }?.toolBreakdown ?? [:]

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
                toolBreakdown: cachedBreakdown
            )
        }.value

        agentDetailData[key] = result
    }
}
