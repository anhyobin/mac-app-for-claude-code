import SwiftUI

/// Small puzzle-piece + count element that surfaces Skill tool usage for a
/// session. Sums every Skill invocation (across main session + all
/// subagents) — this is the session-level "how many skills did you use"
/// scannable signal.
///
/// Hidden when `count == 0` — a zero counter is noise, not signal, and we
/// want session rows without skill usage to stay uncluttered.
///
/// Uses SF Symbol `puzzlepiece.extension`, rendered at caption2 size to
/// visually match ``ThinkingCounter`` and ``TokenBadge``.
struct SkillCounter: View {
    let count: Int

    var body: some View {
        if count > 0 {
            HStack(spacing: 2) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 11))
                Text("\(count)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(count) skill invocations")
            .help("Skill tool invocations")
        }
    }
}
