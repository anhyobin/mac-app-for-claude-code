import SwiftUI

/// Compact banner surfacing a session's `/goal` state inside the dropdown row.
///
/// Rendered between the ContextGauge and the expanded detail block so that
/// the goal — "what Claude is trying to accomplish right now" — is visible
/// without the user needing to expand the session.
///
/// Click to expand: the collapsed banner truncates long conditions to 2 lines
/// so the row stays scannable; expanding reveals the full text inside a
/// scrollable region. This matters because a well-written goal condition is
/// often a multi-paragraph acceptance spec — clipping it defeats the point.
///
/// Two visual variants:
/// - Active: accent-tinted background, "Goal" label, condition + elapsed.
/// - Achieved: green-tinted background, checkmark, "Done" label.
struct GoalBanner: View {
    let goal: GoalStatus

    @State private var isExpanded = false

    /// Max height for the expanded condition block. Keeps very long goals
    /// from pushing the row past the dropdown viewport — anything beyond
    /// scrolls within the banner itself.
    private let expandedMaxHeight: CGFloat = 180

    var body: some View {
        // Short goals are rendered as a plain surface — the banner is never
        // interactive, so there's no click affordance to mismatch. Longer
        // goals wrap the same content in a Button so the chevron has a real
        // target and the whole card is tappable.
        if isTruncatable {
            Button { isExpanded.toggle() } label: { content }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.2), value: isExpanded)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: iconName)
                .font(.caption)
                .foregroundStyle(accentColor)
                .frame(width: 12)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(headerText)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(headerColor)

                    Spacer(minLength: 0)

                    // Meta cluster — elapsed time stays right-aligned so the
                    // condition text on the left has full breathing room.
                    // Turn count was intentionally removed: the underlying
                    // figure (assistant-message count since the goal started)
                    // conflates tool_use roundtrips with user-perceived turns,
                    // so "100 turns" was misleading more than informative.
                    HStack(spacing: 6) {
                        Text(Self.formatElapsed(goal.elapsed))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()

                        if isTruncatable {
                            // Matches SessionRow/AgentRow/SessionDetailView:
                            // collapsed points right, expanded points down.
                            // Keeps the "click-to-reveal" affordance uniform
                            // across every expandable surface in the app.
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                if isExpanded {
                    // Scrollable so multi-paragraph goals stay readable
                    // without stealing the whole dropdown viewport.
                    ScrollView {
                        Text(goal.condition)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: expandedMaxHeight)
                } else {
                    Text(goal.condition)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
    }

    // MARK: - Visual variants

    private var isAchieved: Bool { !goal.isActive }

    private var iconName: String {
        isAchieved ? "checkmark.circle.fill" : "target"
    }

    private var headerText: String {
        isAchieved ? "Goal · Done" : "Goal"
    }

    /// Rough estimate of "would this text visibly truncate at 2 lines?".
    /// We don't know the actual render width, so fall back to a character
    /// heuristic that's conservative enough to hide the chevron on short,
    /// single-line conditions. 80 chars covers the ~350pt banner width at
    /// .caption for most condition text; multi-line content always qualifies.
    private var isTruncatable: Bool {
        goal.condition.count > 80 || goal.condition.contains("\n")
    }

    /// Icon tint. Active goals use `.accentColor` so the banner and the
    /// menu-bar count (also accent-tinted when a goal is active) read as
    /// the same signal. Achieved goals step down to `.secondary` —
    /// deliberately NOT green, because the menu-bar dot already uses
    /// green to mean "session active" and reusing it for "goal achieved"
    /// was ambiguous. A muted tint reads as "past state, acknowledged".
    private var accentColor: Color {
        isAchieved ? .secondary : .accentColor
    }

    /// Header text tint. Kept in sync with `accentColor` for active goals
    /// so the "Goal" label feels like part of the icon cluster; achieved
    /// goals demote the header to `.secondary` so the completed banner
    /// recedes rather than competing with live session metadata.
    private var headerColor: Color {
        isAchieved ? .secondary : .accentColor
    }

    /// Banner background. Active keeps the familiar accent tint at 8%
    /// opacity (macOS sidebar-selection convention). Achieved uses a
    /// neutral gray surface at 6% so the banner stays visible but reads
    /// as "inert" — the goal is done, this row doesn't need attention.
    private var surfaceColor: Color {
        isAchieved
            ? Color.secondary.opacity(0.06)
            : Color.accentColor.opacity(0.08)
    }

    // MARK: - Elapsed formatter (banner-local)

    /// Goal-local elapsed formatter. Distinct from ``RelativeTimeFormatter``
    /// because that helper rounds sub-minute intervals up to "1m", which
    /// misreads a just-installed goal as if a full minute had passed. Kept
    /// private so other views keep their existing formatting.
    /// Buckets: `< 60s` → "just now", `< 60m` → "Nm", `>= 1h` → "Hh Mm"
    /// (or "Hh" when the minute remainder is zero).
    static func formatElapsed(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        guard total >= 0 else { return "just now" }
        if total < 60 {
            return "just now"
        }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours == 0 {
            return "\(minutes)m"
        }
        return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
    }
}
