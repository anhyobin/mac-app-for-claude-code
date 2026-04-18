# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - Unreleased

### Added
- Recognition for the Opus / Sonnet / Haiku 4.7 generation, with a model family
  accent color (Opus=orange, Sonnet=blue, Haiku=green) used by session rows.
- Per-session extended-thinking block counter, parsed from the session JSONL
  and surfaced on the active session row.
- Context-window usage ratio per session, derived from a new
  `ModelContextLimits` table (1M tokens for Opus/Sonnet 4.7, 200K for
  earlier generations). Powers the upcoming context gauge.
- `MenuBarDotState` with a priority stack (error > warning > processing >
  active > inactive > hidden) exposed from `ClaudeDataStore` for the
  menu-bar status dot.

### Notes
- Opus 4.7 uses a new tokenizer — token counts may read 1.0~1.35× higher
  than Opus 4.6 for the same work.

## [0.1.1] - 2026-04-18

### Fixed
- Menu bar dropdown collapsed to ~70pt, hiding the session list and recent
  sessions between the header and the footer. `MenuBarExtra(style: .window)`
  sizes its window from the content's ideal size, and the inner `ScrollView`
  reports an ideal height of 0. Pinning a fixed height (`.frame(height:)`)
  instead of a maximum (`.frame(maxHeight:)`) now allows the scroll view to
  fill the window. Observed on macOS 26.4; unclear which older versions are
  affected.

### Changed
- Extracted the menu bar dropdown width and height into a `private enum Layout`
  in `MenuBarContentView.swift` so the values live in one place.

## [0.1.0] - 2026-04-09

Initial public release.

### Added
- Live session tracking with 5-second refresh via FSEvents and PID validation.
- Agent team overview with per-agent status, token usage, and tool call counts.
- Aggregated token usage across the main session and all subagents.
- Per-session and per-agent task board with status tracking.
- Agent detail view: recent messages, modified files, and tool usage breakdown.
- Session history with model name, duration, and token summary.
- Self-contained `.app` bundle build via Swift Package Manager (no Xcode
  project, ~1.0 MB, arm64, ad-hoc signed).

[Unreleased]: https://github.com/anhyobin/mac-app-for-claude-code/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/anhyobin/mac-app-for-claude-code/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/anhyobin/mac-app-for-claude-code/releases/tag/v0.1.0
