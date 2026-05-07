import Foundation

/// Reads `~/.claude/settings.json` to determine model configuration, specifically
/// whether the user has configured a 1M-context variant via `[1m]` suffix in env vars.
///
/// The JSONL API response only contains short model IDs (e.g., `claude-opus-4-6`),
/// which lack the `[1m]` suffix. The global settings file is the source of truth for
/// whether the user is running a 1M-context variant.
///
/// Reading is lazy and cached — the file is parsed once per app launch.
enum ClaudeSettingsReader {

    // MARK: - Public API

    /// Returns `true` if the user's `~/.claude/settings.json` indicates that the given
    /// short model name corresponds to a 1M-context variant.
    ///
    /// Matching logic:
    /// - Extract the model family-version key from `shortModel` (e.g., `opus-4-6` from
    ///   `claude-opus-4-6-20260101` or `claude-opus-4-6`).
    /// - Check if any ANTHROPIC_*MODEL* env var in settings contains both that key AND `[1m]`.
    ///
    /// - Parameter shortModel: The raw model string from JSONL (e.g., `claude-opus-4-6`).
    /// - Returns: `true` if settings.json maps this model to a 1M variant; `false` otherwise.
    static func isOneMillionContext(for shortModel: String) -> Bool {
        guard let envVars = cachedEnvVars else { return false }
        let lower = shortModel.lowercased()

        // Extract the family-version key: "opus-4-6", "sonnet-4-6", etc.
        // The JSONL model field looks like "claude-opus-4-6-20260101" or "claude-opus-4-6".
        guard let modelKey = extractModelKey(from: lower) else { return false }

        // Check if any relevant env var contains both the model key and [1m].
        for value in envVars {
            let valueLower = value.lowercased()
            if valueLower.contains(modelKey) && valueLower.contains("[1m]") {
                return true
            }
        }
        return false
    }

    // MARK: - Private

    /// Cached environment variable values from settings.json.
    /// `nil` means the file could not be read or parsed (graceful fallback).
    private static let cachedEnvVars: [String]? = loadEnvVars()

    /// Env var keys in settings.json that may contain model identifiers with [1m] suffix.
    private static let modelEnvKeys: Set<String> = [
        "ANTHROPIC_MODEL",
        "ANTHROPIC_DEFAULT_OPUS_MODEL",
        "ANTHROPIC_DEFAULT_SONNET_MODEL",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL",
    ]

    /// Reads and parses `~/.claude/settings.json`, returning the values of model-related
    /// env vars. Returns `nil` on any failure (missing file, parse error, unexpected structure).
    private static func loadEnvVars() -> [String]? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let settingsURL = homeDir.appendingPathComponent(".claude/settings.json")

        guard let data = try? Data(contentsOf: settingsURL) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let env = json["env"] as? [String: String] else { return nil }

        var values: [String] = []
        for (key, value) in env {
            if modelEnvKeys.contains(key) {
                values.append(value)
            }
        }
        return values.isEmpty ? nil : values
    }

    /// Extracts the model family-version key from a JSONL model string.
    ///
    /// Examples:
    /// - `"claude-opus-4-6-20260101"` → `"opus-4-6"`
    /// - `"claude-opus-4-6"` → `"opus-4-6"`
    /// - `"claude-sonnet-4-7-20260315"` → `"sonnet-4-7"`
    ///
    /// Pattern: look for `(opus|sonnet|haiku)-\d+-\d+` within the string.
    private static func extractModelKey(from model: String) -> String? {
        // Match family name followed by version digits: e.g., "opus-4-6", "sonnet-4-7"
        let families = ["opus", "sonnet", "haiku"]
        for family in families {
            guard let familyRange = model.range(of: family) else { continue }
            let afterFamily = model[familyRange.upperBound...]
            // Expect "-X-Y" pattern (major-minor version)
            // Use simple character scanning instead of regex for performance
            if let match = extractVersionSuffix(from: String(afterFamily)) {
                return "\(family)\(match)"
            }
        }
        return nil
    }

    /// Given a string starting after the family name (e.g., "-4-6-20260101"),
    /// extracts the version part ("-4-6").
    private static func extractVersionSuffix(from str: String) -> String? {
        // Expected format: "-{major}-{minor}..." where major/minor are digits
        guard str.hasPrefix("-") else { return nil }
        let chars = Array(str)
        var idx = 1 // skip leading "-"

        // Parse major version digits
        let majorStart = idx
        while idx < chars.count && chars[idx].isNumber { idx += 1 }
        guard idx > majorStart else { return nil }

        // Expect "-" separator
        guard idx < chars.count && chars[idx] == "-" else { return nil }
        idx += 1

        // Parse minor version digits
        let minorStart = idx
        while idx < chars.count && chars[idx].isNumber { idx += 1 }
        guard idx > minorStart else { return nil }

        // Build the version suffix: "-4-6"
        let versionEnd = idx
        return String(chars[0..<versionEnd])
    }
}
