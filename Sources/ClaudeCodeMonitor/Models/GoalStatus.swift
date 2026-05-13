import Foundation

/// Snapshot of an active or recently-achieved `/goal` condition for a session.
///
/// Claude Code's `/goal <condition>` command installs a Stop hook on the
/// session that makes Claude keep taking turns until the condition is judged
/// met. The evaluator's per-turn verdicts are NOT written to JSONL — only two
/// markers show up as `attachment` entries with `attachment.type == "goal_status"`:
///
///   - Start marker: `met: false, sentinel: true` carries the `condition` text
///     and timestamps when the goal was installed.
///   - Achievement marker: `met: true` (observed schema is a hypothesis — same
///     attachment envelope, just `met` flipped). Its timestamp is when Claude
///     judged the condition satisfied.
///
/// Because turn-by-turn judgements aren't persisted, `turnsElapsed` is computed
/// as "number of assistant messages after the latest start marker" — this is
/// the user-visible proxy for "how hard Claude has been pushing on this goal".
///
/// A session can install a new `/goal` after achieving an earlier one; the
/// parser always surfaces only the MOST RECENT start marker (plus any matching
/// achievement that came after it). Stale achievements from prior goals are
/// not exposed.
struct GoalStatus: Sendable, Equatable {
    /// Full `condition` string from the start marker. May contain newlines
    /// and multi-language text (e.g. Korean). Callers are responsible for
    /// truncation / line-limit in the UI.
    let condition: String
    /// Timestamp on the `met: false, sentinel: true` start marker.
    let startedAt: Date
    /// Timestamp on a subsequent `met: true` marker, or `nil` when the goal
    /// is still active. `isActive` is the preferred predicate for the UI.
    let achievedAt: Date?
    /// Assistant message count observed AFTER the start marker (up to the
    /// achievement marker when one exists, otherwise end-of-file).
    ///
    /// NOT currently surfaced in the UI as of v0.4.0 — the figure conflated
    /// tool_use roundtrips with user-perceived turns (one user prompt that
    /// triggers several tool calls still produces several assistant messages),
    /// so "100 turns" was more noise than signal. The field is kept because
    /// the parser and tests already validate it, and a future release may
    /// re-expose it under a clearer label (e.g. "Claude responses since
    /// goal start").
    let turnsElapsed: Int

    /// `true` when the goal is still being worked on (no achievement marker
    /// observed yet after the latest start).
    var isActive: Bool { achievedAt == nil }

    /// Duration from install to now (active) or install to achievement
    /// (achieved). Freezing at `achievedAt` keeps the UI's "소요 시간" figure
    /// stable after the goal is met instead of creeping upward forever.
    var elapsed: TimeInterval {
        let endTime = achievedAt ?? Date()
        return endTime.timeIntervalSince(startedAt)
    }
}
