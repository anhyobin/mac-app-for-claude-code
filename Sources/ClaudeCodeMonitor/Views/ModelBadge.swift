import SwiftUI

/// Compact capsule badge indicating the model family driving a session.
///
/// Sized to sit beside ``TokenBadge`` and the agent chevron without stealing
/// visual weight from the project name. Hidden when the raw model string is
/// missing or classifies as ``ModelFamily/unknown`` — we'd rather show nothing
/// than mislabel a future model as a known tier.
///
/// Color tint comes from ``ModelFamily/accentColor`` (Opus=orange,
/// Sonnet=blue, Haiku=green), so a row's family is recognizable at a glance
/// without reading the text.
struct ModelBadge: View {
    let rawModel: String?

    var body: some View {
        if let raw = rawModel {
            let family = ModelNameFormatter.family(from: raw)
            if family != .unknown {
                Text(verbatim: ModelNameFormatter.displayName(from: raw))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(family.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(family.accentColor.opacity(0.15))
                    .clipShape(Capsule())
                    .lineLimit(1)
            }
        }
    }
}
