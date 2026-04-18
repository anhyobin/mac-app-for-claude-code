import SwiftUI

/// Small brain-icon + count element that surfaces extended-thinking activity
/// for a session.
///
/// Hidden when `count == 0` — a zero counter is noise, not signal, and we
/// want session rows without thinking blocks to stay uncluttered.
///
/// Uses SF Symbol `brain` (available macOS 11+), rendered at caption2 size to
/// visually match ``TokenBadge`` without dominating the row.
struct ThinkingCounter: View {
    let count: Int

    var body: some View {
        if count > 0 {
            HStack(spacing: 2) {
                Image(systemName: "brain")
                    .font(.system(size: 11))
                Text("\(count)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(count) thinking blocks")
        }
    }
}
