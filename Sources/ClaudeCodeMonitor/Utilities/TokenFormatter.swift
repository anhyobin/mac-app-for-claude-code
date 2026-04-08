import Foundation

enum TokenFormatter {
    static func compact(_ count: Int) -> String {
        if count < 1000 {
            return "\(count)"
        } else if count < 1_000_000 {
            let k = Double(count) / 1000.0
            return k >= 100 ? "\(Int(k))K" : String(format: "%.1fK", k)
        } else {
            let m = Double(count) / 1_000_000.0
            return m >= 100 ? "\(Int(m))M" : String(format: "%.1fM", m)
        }
    }
}
