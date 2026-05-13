# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-05-13

### Added
- **`/goal` monitoring.** Claude Code CLI's `/goal <condition>` command
  installs a Stop hook that makes Claude keep taking turns until the
  condition is judged met; previously there was no signal outside the
  terminal that a session was under this mode. The app now surfaces
  active goals in two places:
  - **Menu-bar count tint** — the active-session count next to the
    status dot shifts to the system accent color whenever at least one
    active session has an in-progress goal. A separate glyph was
    rejected because a third 8pt mark beside the icon and status dot
    was too easily misread as a second status indicator; folding the
    signal into the count keeps the menu bar uncluttered. Separate
    from the status dot's priority stack (error/warning/active) so
    goal state reads as a parallel signal, not a replacement for
    health.
  - **Goal banner** inside each session row (between the context gauge
    and the expanded detail block) showing the condition text and
    elapsed time since the goal was installed. Collapsed view
    truncates the condition to 2 lines; clicking
    the banner expands it into a scrollable region (up to 180pt tall)
    so multi-paragraph acceptance specs stay fully readable. The
    expand chevron and clickable surface hide for short single-line
    conditions so the collapsed row stays uncluttered and there is no
    dead tap target. Active goals use an accent tint; achieved goals
    step down to a neutral secondary tint with a "· Done" suffix —
    intentionally NOT green, so the dot's green-means-active semantic
    stays unambiguous.
- **`GoalStatus` model** — snapshot of a session's most recent goal:
  `condition`, `startedAt`, `achievedAt` (nil while active),
  `turnsElapsed`, with derived `isActive` and `elapsed` properties.
  `elapsed` freezes at `achievedAt` for achieved goals so the
  "time taken" figure does not creep upward forever after completion.
- **`GoalBanner` view** — compact SwiftUI row with intrinsic height so
  `MenuBarExtra(.window) + ScrollView` stays stable. Uses a
  banner-local `formatElapsed` helper (buckets `<60s` → "just now",
  `<60m` → "Nm", `≥1h` → "Hh Mm") to avoid the shared
  `RelativeTimeFormatter` rounding sub-minute intervals up to "1m",
  which would misread a just-installed goal as a full minute elapsed.
- **`GoalStatusParsingTests`** — six tests covering no-goal, active
  goal turn counting, achieved-goal turn-freeze, most-recent-goal
  override, multiline Korean condition preservation, and truncated
  file fallback, plus an opt-in fixture check against a real JSONL
  containing a goal event.

### Changed
- **`JSONLParser.scanTokensAndThinking`** now also tracks
  `goal_status` attachment events in a single pass. Cheap string
  guards (`"goal_status"` substring) keep JSON decoding off the hot
  path for unrelated attachment rows. Parsing rules:
  - `met: false, sentinel: true` is the start marker — captures
    `condition` and timestamps when the goal was installed. A new
    start always resets the tracker so the surfaced goal is the
    most recent one (stale achievements for prior goals are dropped).
  - `met: true` after a start marker is the achievement marker —
    freezes `turnsElapsed` at the achievement turn.
  - Orphan `met: true` with no prior start is ignored.
- **`SessionQuickStats` / `SessionExpandedData`** gain an `activeGoal:
  GoalStatus?` field. `nil` is a valid cached value (session has no
  goal history, or file was truncated).
- **`ClaudeDataStore.loadSessionDetail`** — mtime cache path now
  includes `activeGoal` so goal state is refreshed at the same
  cadence as tokens/thinking/skill counts, with no extra parse passes.
- **`ClaudeDataStore.hasActiveGoal`** — new computed property that
  returns true iff at least one active session has an in-progress
  goal. Drives the menu-bar target indicator. Intentionally separate
  from `menuBarDotState`'s priority stack.
- `Info.plist` bundle version bumped to `0.4.0` (build `6`).

### Notes
- The `met: true` schema for achievements is a hypothesis based on
  symmetry with the start marker and was exercised via tests. At the
  time of release, no production JSONL with a `met: true` record has
  been observed in the author's data; once one surfaces, the schema
  may need a minor parser adjustment. The UI is designed to degrade
  gracefully — an achievement that never arrives keeps the banner in
  its active state, which is still useful.
- Binary size grew +5.3% (1,220,912 → 1,285,488 bytes) vs v0.3.2.
  `.app` bundle unchanged at 1.3 MB.

## [0.3.2] - 2026-05-11

### Fixed
- **Mid-session `/model` swaps now reflected in the UI.** The JSONL parser
  previously captured the `model` field from only the *first* assistant
  message in a session, so switching models with `/model` mid-session (e.g.
  Opus → Sonnet) left the session row, model badge, context gauge, and
  menu-bar dot warning threshold stuck on the original model. Both the
  full-summary and fast-path parsers now overwrite `model` on every
  assistant turn, matching the existing last-turn rule used by
  `mainLastTurnUsage`. Context-window ratio and limit are now evaluated
  against the model that actually served the last turn.

### Changed
- **`(1M)` label rule extended to the 4.7 generation.** Previously 4.7
  models suppressed the `(1M)` suffix on the assumption that 1M was
  implicit for that generation. That was incorrect — 4.7 goes through the
  same `ANTHROPIC_*MODEL` env-var `[1m]` mapping as 4.6. The special-case
  has been removed, so `claude-opus-4-7` (and sonnet/haiku 4.7) now
  display `Opus 4.7 (1M)` when `~/.claude/settings.json` maps the model
  with a `[1m]` suffix, and `Opus 4.7` otherwise. Same rule as 4.6, no
  generation-specific exceptions.

## [0.3.1] - 2026-05-07

### Fixed
- **Context gauge 1M detection** — models configured as 1M-context variants
  (e.g., `us.anthropic.claude-opus-4-6-v1[1m]`) were incorrectly shown with a
  200K limit because the JSONL API response only contains short model IDs
  (`claude-opus-4-6`) without the `[1m]` suffix. The fix cross-references
  `~/.claude/settings.json` env vars (`ANTHROPIC_MODEL`, etc.) to detect the
  `[1m]` suffix and correctly report a 1M context window.

### Added
- **`ClaudeSettingsReader`** utility — reads `~/.claude/settings.json` once at
  app launch to determine model context-window configuration. Cached per session.
- **"(1M)" badge suffix** on model badges for non-4.7 models running with 1M
  context (e.g., "Opus 4.6 (1M)"), so users can confirm their variant at a
  glance.

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

[Unreleased]: https://github.com/anhyobin/mac-app-for-claude-code/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/anhyobin/mac-app-for-claude-code/compare/v0.3.2...v0.4.0
[0.3.2]: https://github.com/anhyobin/mac-app-for-claude-code/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/anhyobin/mac-app-for-claude-code/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/anhyobin/mac-app-for-claude-code/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/anhyobin/mac-app-for-claude-code/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/anhyobin/mac-app-for-claude-code/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/anhyobin/mac-app-for-claude-code/releases/tag/v0.1.0
