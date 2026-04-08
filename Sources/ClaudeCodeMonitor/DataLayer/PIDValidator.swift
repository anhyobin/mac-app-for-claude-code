import Foundation

enum PIDValidator {
    static func isAlive(_ pid: Int32) -> Bool {
        let result = kill(pid, 0)
        if result == 0 { return true }
        if errno == EPERM { return true }
        return false
    }
}
