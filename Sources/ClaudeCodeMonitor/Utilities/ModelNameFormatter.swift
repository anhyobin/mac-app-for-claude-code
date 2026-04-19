import Foundation
import SwiftUI

/// Coarse model family classification used for UI accent colors and badge grouping.
///
/// The family is derived from the raw model string via ``ModelNameFormatter/family(from:)``.
/// ``unknown`` is returned when the raw string does not match any known family keyword.
enum ModelFamily: Sendable, Equatable {
    case opus
    case sonnet
    case haiku
    case unknown

    /// Accent color used by SessionRow and related views to visually distinguish model families.
    ///
    /// - Opus: orange (highest capability tier)
    /// - Sonnet: blue (balanced tier)
    /// - Haiku: green (fastest tier)
    /// - Unknown: gray (fallback, avoids misrepresenting an unrecognized model as a known tier)
    var accentColor: Color {
        switch self {
        case .opus: return .orange
        case .sonnet: return .blue
        case .haiku: return .green
        case .unknown: return .gray
        }
    }
}

enum ModelNameFormatter {
    // Order matters: longer/more-specific patterns must come before shorter ones
    // so that "opus-4-7" is not shadowed by a future "opus-4" entry. The 4-7
    // generation is listed first because it is the current flagship.
    private static let knownModels: [(pattern: String, display: String)] = [
        ("opus-4-7", "Opus 4.7"),
        ("sonnet-4-7", "Sonnet 4.7"),
        ("haiku-4-7", "Haiku 4.7"),
        ("opus-4-6", "Opus 4.6"),
        ("opus-4-5", "Opus 4.5"),
        ("sonnet-4-6", "Sonnet 4.6"),
        ("sonnet-4-5", "Sonnet 4.5"),
        ("sonnet-3-5", "Sonnet 3.5"),
        ("haiku-4-6", "Haiku 4.6"),
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

    /// Classifies the raw model string into a coarse family for UI coloring.
    ///
    /// This is intentionally keyword-based — as long as the raw model contains
    /// "opus", "sonnet", or "haiku" (case-insensitive), it maps to that family.
    /// Unknown strings map to ``ModelFamily/unknown`` rather than raising, so
    /// SessionRow can still render without crashing on a new model.
    static func family(from rawModel: String) -> ModelFamily {
        let lower = rawModel.lowercased()
        if lower.contains("opus") { return .opus }
        if lower.contains("sonnet") { return .sonnet }
        if lower.contains("haiku") { return .haiku }
        return .unknown
    }
}
