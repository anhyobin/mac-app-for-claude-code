import Foundation

enum ModelNameFormatter {
    private static let knownModels: [(pattern: String, display: String)] = [
        ("opus-4-6", "Opus 4.6"),
        ("opus-4-5", "Opus 4.5"),
        ("sonnet-4-6", "Sonnet 4.6"),
        ("sonnet-4-5", "Sonnet 4.5"),
        ("sonnet-3-5", "Sonnet 3.5"),
        ("haiku-4-5", "Haiku 4.5"),
        ("haiku-3-5", "Haiku 3.5"),
    ]

    static func displayName(from rawModel: String) -> String {
        let lower = rawModel.lowercased()

        for entry in knownModels {
            if lower.contains(entry.pattern) {
                return entry.display
            }
        }

        // Fallback for unrecognized patterns
        if lower.contains("opus") { return "Opus" }
        if lower.contains("sonnet") { return "Sonnet" }
        if lower.contains("haiku") { return "Haiku" }

        return rawModel
    }
}
