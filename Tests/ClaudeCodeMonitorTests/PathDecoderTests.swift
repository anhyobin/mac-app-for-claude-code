import XCTest
@testable import ClaudeCodeMonitor

/// Verifies `PathDecoder.encodedProjectPath` produces the same directory name
/// that Claude CLI writes under `~/.claude/projects/`.
///
/// CLI rule: `/`, `.`, and ` ` (space) in the cwd path are all replaced with
/// `-`. Missing the space-replacement caused v0.4.0 to fail to locate the
/// main JSONL for cwd paths containing spaces (e.g.
/// `/Users/anhyobin/Documents/Solutions Arhitect/Public Events/Claude Webinar`),
/// surfacing only the per-session task data.
final class PathDecoderTests: XCTestCase {

    /// v0.4.1 bug: cwd contained spaces and the encoder left them as-is, so
    /// the resulting directory name never matched the on-disk
    /// `~/.claude/projects/-Users-...-Claude-Webinar` directory.
    func testSpacesInPathReplacedWithDash() {
        let cwd = "/Users/anhyobin/Documents/Solutions Arhitect/Public Events/Claude Webinar"
        let encoded = PathDecoder.encodedProjectPath(from: cwd)
        XCTAssertEqual(
            encoded,
            "-Users-anhyobin-Documents-Solutions-Arhitect-Public-Events-Claude-Webinar"
        )
    }

    /// Regression guard: paths without spaces must encode exactly as before
    /// so existing sessions keep resolving.
    func testPathWithoutSpacesUnchanged() {
        let cwd = "/Users/anhyobin/dev/mac-app-for-claude"
        let encoded = PathDecoder.encodedProjectPath(from: cwd)
        XCTAssertEqual(encoded, "-Users-anhyobin-dev-mac-app-for-claude")
    }

    /// Dots in path components (e.g. `bar.baz`) are also flattened to `-`,
    /// matching the CLI's directory-naming convention.
    func testDotsInPathReplacedWithDash() {
        let cwd = "/foo/bar.baz"
        let encoded = PathDecoder.encodedProjectPath(from: cwd)
        XCTAssertEqual(encoded, "-foo-bar-baz")
    }
}
