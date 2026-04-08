import SwiftUI

struct StatusIndicator: View {
    var isActive: Bool = true

    var body: some View {
        Circle()
            .fill(isActive ? Color.green : Color.gray)
            .frame(width: 8, height: 8)
    }
}
