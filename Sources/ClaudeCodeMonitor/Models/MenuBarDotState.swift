import Foundation

/// Aggregate visual state for the menu-bar status dot.
///
/// The view layer renders this as a small colored dot beside the menu-bar
/// icon; this enum only decides *which* state the dot should be in. The
/// priority order — higher variants win — is:
///
///     error > warning > processing > active > inactive > hidden
///
/// See ``ClaudeDataStore/menuBarDotState`` for the authoritative computation.
enum MenuBarDotState: Sendable, Equatable {
    /// No active sessions. Dot should be hidden entirely.
    case hidden
    /// At least one active session, but none have produced an assistant
    /// message in the last 60 seconds. The user is "attached" but idle.
    case inactive
    /// At least one active session produced an assistant message within
    /// the last 60 seconds.
    case active
    /// At least one active session is mid-turn — a tool_use has been emitted
    /// without a matching tool_result yet. Not computed in v0.2 (see TODO in
    /// ``ClaudeDataStore/menuBarDotState``).
    case processing
    /// At least one active session has crossed 95% of its model's context
    /// window. The user likely needs to compact or start a new session soon.
    case warning
    /// Reserved for future use (parse errors, inaccessible ~/.claude, etc.).
    case error

    /// Priority rank, higher = more important. Used when multiple active
    /// sessions resolve to different states — the dot shows the max rank.
    var priority: Int {
        switch self {
        case .hidden: return 0
        case .inactive: return 1
        case .active: return 2
        case .processing: return 3
        case .warning: return 4
        case .error: return 5
        }
    }
}
