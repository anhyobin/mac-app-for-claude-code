# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-04-22

### Added
- **Skill tool usage visualization** — extracts per-skill invocation counts
  from both the main session JSONL and every subagent JSONL, keyed by the
  full skill name (plugin namespaces like `oh-my-claudecode:hud` preserved).
  Surfaced in two places:
  - **Session detail** (expanded view): a one-line `🧩 Skills:` summary
    below the thinking-block row, sorted by count DESC / name ASC. Shows
    top 4 entries joined by ` · `; overflow is `+N more`. Bound to
    `totalSkillCounts` (main + all subagents, active and completed) so
    skill calls remain visible after subagents drop off the active list.
  - **Agent detail** (expanded agent row): a purple-tinted chip section
    using `FlowLayout`, placed between the existing Tools and Files
    sections. Count shown only when > 1.
- **Skill counter badge** (`🧩 N`) on collapsed active-session and
  recent-session rows, matching the existing thinking-counter (`🧠 N`)
  pattern. Hidden when zero. Active rows use the session-wide total
  (main + subagents); recent rows use main-session counts only (subagent
  data is not loaded for recent sessions).

## [0.2.0] - 2026-04-20

### Added
- **Model badge** on active and recent session rows, surfacing the model in
  use (e.g. "Opus 4.7") with a family accent color — Opus=orange,
  Sonnet=blue, Haiku=green. Active sessions previously showed no model at
  all; recent sessions showed only a plain text name.
- **Opus 4.7** recognition in `ModelNameFormatter`. Sonnet and Haiku 4.7
  patterns are pre-registered for when those models ship; today only Opus
  4.7 is released. The 4.7 generation is matched before 4.6 to avoid
  prefix shadowing. Also filled in the missing `haiku-4-6` entry for
  family matrix completeness.
- **Extended-thinking block counter** (`🧠 N`) on every session row, parsed
  from `content[].type == "thinking"` blocks in the session JSONL. Hidden
  when zero so rows without thinking stay uncluttered. Expanded detail view
  shows the full label "Thinking: N blocks" under the Context line for
  first-time discoverability.
- **Context-window gauge** — a 2pt hairline bar at the bottom of each
  active session row showing `lastTurn usage / model max`. Secondary below
  80%, orange at 80–94%, red at 95%+. Expanded detail view adds a
  tabular-num readout like `312K / 1M (31%)`. Backed by a new
  `ModelContextLimits` table (1M for 4.7-generation models, 200K for
  earlier generations) and a `contextUsageRatio` that uses only the last
  assistant turn's usage snapshot — not a cumulative sum — to avoid
  per-turn cache_read over-counting.
- **Menu-bar status dot** — an 8pt overlay on the menu-bar icon driven by
  a priority stack: error (red) > warning (orange, context ≥ 95%) >
  processing (blue, pulsing — reserved for v0.3) > active (green) >
  inactive (gray) > hidden. Green is static, following Apple's convention
  of reserving pulse for in-transition states only.

### Changed
- `JSONLParser.scanTokensOnly` removed; callers use the new
  `scanTokensAndThinking` which returns tokens, thinking count, model, and
  the last-turn usage snapshot in a single pass.
- `Info.plist` bundle version bumped to `0.2.0` (build `2`).

### Notes
- Opus 4.7 uses a new tokenizer — token counts may read 1.0~1.35× higher
  than Opus 4.6 for the same work. No action needed; mixed-model
  comparisons may look inflated for Opus 4.7 sessions.

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

[Unreleased]: https://github.com/anhyobin/mac-app-for-claude-code/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/anhyobin/mac-app-for-claude-code/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/anhyobin/mac-app-for-claude-code/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/anhyobin/mac-app-for-claude-code/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/anhyobin/mac-app-for-claude-code/releases/tag/v0.1.0
