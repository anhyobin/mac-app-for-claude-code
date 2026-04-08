import SwiftUI

struct TokenBadge: View {
    let count: Int

    var body: some View {
        Text(TokenFormatter.compact(count))
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary)
            .clipShape(Capsule())
    }
}
