# Opus 4.8 Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Claude Code Monitor가 `claude-opus-4-8` 세션을 "Opus 4.8" 라벨 + 1M 컨텍스트 게이지로 정확히 표시하도록 하고, 앱 버전을 0.5.0으로 올린다.

**Architecture:** 모델 ID→라벨 매핑 테이블에 4.8 항목 1개 추가, 컨텍스트 한도 함수의 inherent-1M 분기에 4.8 추가, Info.plist 버전 bump, 회귀 테스트 추가. 파서·배지·settings 리더는 모델-불문 로직이라 무변경.

**Tech Stack:** Swift 6 / SwiftUI, SwiftPM (`swift build`), XCTest. **빌드 환경 주의: 이 머신은 Xcode.app 없이 Command Line Tools만 있어 `swift test`(XCTest) 실행 불가. 검증은 `swift build`(컴파일) + 코드 인스펙션으로 하고, XCTest 실행은 Xcode 보유 머신에서.**

---

### Task 1: ModelContextLimits에 4.8 inherent-1M 추가 + 테스트

**Files:**
- Modify: `Sources/ClaudeCodeMonitor/Utilities/ModelContextLimits.swift:39` (및 doc 코멘트 9-13, 26)
- Test: `Tests/ClaudeCodeMonitorTests/ContextUsageRatioTests.swift` (`ModelContextLimitsTests` 클래스, 109-151행)

- [ ] **Step 1: 회귀 테스트 추가 (먼저 작성)**

`Tests/ClaudeCodeMonitorTests/ContextUsageRatioTests.swift`의 `ModelContextLimitsTests` 클래스 안, `testSonnet47IsOneMillion()` (115-116행) 바로 다음에 삽입:

```swift
    /// Opus 4.8 ships with a 1M context window as the API default (no [1m]
    /// setting required), same as 4.7. This MUST hold without any
    /// ~/.claude/settings.json [1m] mapping — the JSONL model field never
    /// carries [1m], so if this fell through to the broad "opus" branch it
    /// would wrongly report 200K and over-report gauge fullness by 5x.
    /// (This is the exact failure mode that bit Opus 4.7 in CC 2.1.117.)
    func testOpus48IsOneMillion() {
        XCTAssertEqual(ModelContextLimits.maxContext(for: "claude-opus-4-8"), 1_000_000)
        XCTAssertEqual(ModelContextLimits.maxContext(for: "us.anthropic.claude-opus-4-8"), 1_000_000)
    }
```

- [ ] **Step 2: 테스트가 실패함을 확인 (코드 인스펙션 — XCTest 실행 불가 환경)**

현재 `maxContext`는 `opus-4-8`을 인식하지 못해 `lower.contains("opus")` 분기(42행)로 떨어져 `200_000`을 반환 → `testOpus48IsOneMillion`은 실패할 것. (Xcode 머신이라면 `swift test --filter ModelContextLimitsTests/testOpus48IsOneMillion` 으로 FAIL 확인.)

- [ ] **Step 3: 최소 구현 — inherent-1M 분기에 4.8 추가**

`ModelContextLimits.swift:39`를 다음으로 교체:

```swift
        if lower.contains("opus-4-8") || lower.contains("opus-4-7") || lower.contains("sonnet-4-7") {
            return 1_000_000
        }
```

같은 파일 doc 코멘트도 갱신 — 9행 `/// Values as of 2026-04:` → `/// Values as of 2026-05:`; 12행 `/// - Opus 4.7 / Sonnet 4.7: 1M context (inherent, no settings needed)` → `/// - Opus 4.8 / Opus 4.7 / Sonnet 4.7: 1M context (inherent, no settings needed)`; 26행 `///    2. The 4.7 generation — inherently 1M without needing the suffix.` → `///    2. The 4.8 / 4.7 generation — inherently 1M without needing the suffix.`

- [ ] **Step 4: 컴파일 통과 확인**

Run: `swift build 2>&1 | tail -5`
Expected: 에러 없이 빌드 완료 (`Compiling`/`Build complete`). Xcode 머신이면 추가로 `swift test --filter ModelContextLimitsTests` → PASS.

- [ ] **Step 5: 커밋**

```bash
git add Sources/ClaudeCodeMonitor/Utilities/ModelContextLimits.swift Tests/ClaudeCodeMonitorTests/ContextUsageRatioTests.swift
git commit -m "feat: treat Opus 4.8 as inherent 1M context"
```

---

### Task 2: ModelNameFormatter에 "Opus 4.8" 라벨 추가 + 테스트

**Files:**
- Modify: `Sources/ClaudeCodeMonitor/Utilities/ModelNameFormatter.swift:34-46` (`knownModels` 배열)
- Test: `Tests/ClaudeCodeMonitorTests/ContextUsageRatioTests.swift` (`ModelFamilyTests` 클래스, 178-232행)

- [ ] **Step 1: 라벨/순서/family 회귀 테스트 추가 (먼저 작성)**

`ModelFamilyTests` 클래스 안, `testUnknown()` (191-193행) 다음에 삽입:

```swift
    func testOpus48Family() {
        XCTAssertEqual(ModelNameFormatter.family(from: "claude-opus-4-8"), .opus)
    }

    /// 4.8 is the current flagship and must resolve to "Opus 4.8".
    /// Provider-prefixed Bedrock/Vertex ids must also resolve. The "(1M)"
    /// suffix is settings-dependent (same rule as 4.7), so only assert the
    /// version number here.
    func testOpus48DisplayName() {
        let bare = ModelNameFormatter.displayName(from: "claude-opus-4-8")
        XCTAssertTrue(bare == "Opus 4.8" || bare == "Opus 4.8 (1M)")
        let prefixed = ModelNameFormatter.displayName(from: "us.anthropic.claude-opus-4-8")
        XCTAssertTrue(prefixed == "Opus 4.8" || prefixed == "Opus 4.8 (1M)")
    }

    /// Ordering guard: opus-4-8 must not be shadowed by opus-4-7 / opus-4-6.
    /// They don't substring-overlap, but knownModels mandates newest-first,
    /// so a 4.8 string must never resolve to a "4.7" or "4.6" display.
    func testOpus48NotShadowed() {
        let d = ModelNameFormatter.displayName(from: "claude-opus-4-8")
        XCTAssertFalse(d.contains("4.7"))
        XCTAssertFalse(d.contains("4.6"))
    }
```

- [ ] **Step 2: 테스트가 실패함을 확인 (코드 인스펙션)**

현재 `knownModels`에 `opus-4-8` 항목이 없으므로 `displayName("claude-opus-4-8")`은 fallback(66행 `if lower.contains("opus")`)으로 떨어져 `"Opus"`(또는 `"Opus (1M)"`)를 반환 → `testOpus48DisplayName` 실패. `family`는 이미 `.opus`라 `testOpus48Family`/`testOpus48NotShadowed`는 통과(무해). (Xcode 머신: `swift test --filter ModelFamilyTests/testOpus48DisplayName` → FAIL.)

- [ ] **Step 3: 최소 구현 — knownModels 맨 앞에 4.8 추가**

`ModelNameFormatter.swift:34-35`의 배열 시작부를 다음으로 교체:

```swift
    private static let knownModels: [(pattern: String, display: String)] = [
        ("opus-4-8", "Opus 4.8"),
        ("opus-4-7", "Opus 4.7"),
```

(33행 코멘트 "The 4-7 generation is listed first because it is the current flagship." → "The 4-8 generation is listed first because it is the current flagship." 로 갱신.)

- [ ] **Step 4: 컴파일 통과 확인**

Run: `swift build 2>&1 | tail -5`
Expected: 에러 없이 빌드 완료. Xcode 머신이면 `swift test --filter ModelFamilyTests` → PASS.

- [ ] **Step 5: 커밋**

```bash
git add Sources/ClaudeCodeMonitor/Utilities/ModelNameFormatter.swift Tests/ClaudeCodeMonitorTests/ContextUsageRatioTests.swift
git commit -m "feat: add Opus 4.8 display label"
```

---

### Task 3: 버전 0.5.0 bump + CHANGELOG

**Files:**
- Modify: `Info.plist:14,16`
- Modify: `CHANGELOG.md` (7행 `## [Unreleased]` 아래)

- [ ] **Step 1: Info.plist 버전 갱신**

`Info.plist:14` `<string>7</string>` → `<string>8</string>`
`Info.plist:16` `<string>0.4.1</string>` → `<string>0.5.0</string>`

- [ ] **Step 2: CHANGELOG 항목 추가**

`CHANGELOG.md`의 `## [Unreleased]`(7행) 아래에 삽입:

```markdown
## [0.5.0] - 2026-05-29

### Added
- **Opus 4.8 지원.** Claude Code `2.1.154`에서 도입된 `claude-opus-4-8`을
  "Opus 4.8" 라벨로 인식. 4.8은 1M 컨텍스트가 API 표준(beta 헤더·`[1m]`
  설정 불필요)이므로 4.7과 동일하게 settings.json 참조 없이 항상 1M로
  컨텍스트 게이지를 계산 (`ModelContextLimits` inherent-1M 분기).
```

- [ ] **Step 3: 버전이 올바른지 확인**

Run: `grep -A1 -E 'CFBundle(Version|ShortVersionString)' Info.plist`
Expected: `CFBundleVersion` = `8`, `CFBundleShortVersionString` = `0.5.0`.

- [ ] **Step 4: 앱 번들 빌드 (런타임 버전 반영 확인)**

Run: `bash scripts/build-app.sh 2>&1 | tail -3`
Expected: `==> Done! ClaudeCodeMonitor.app (...)`. (build-app.sh가 루트 `Info.plist`를 번들로 복사하므로 0.5.0이 반영됨.)

- [ ] **Step 5: 커밋**

```bash
git add Info.plist CHANGELOG.md
git commit -m "release: v0.5.0 — Opus 4.8 support"
```

---

### Task 4: 최종 검증

- [ ] **Step 1: 전체 빌드 클린 확인**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!` (또는 경고 없이 컴파일 완료).

- [ ] **Step 2: 실제 transcript로 동작 확인 (선택, 강력 권장)**

사용자 머신에는 이미 `claude-opus-4-8` 세션이 존재(실측 2479회). 앱을 실행해 해당 세션 행이 "Opus 4.8" 배지(orange) + 컨텍스트 게이지가 1M 기준으로 표시되는지 육안 확인:

Run: `open ClaudeCodeMonitor.app`
Expected: 4.8 세션이 "Opus 4.8"로 표기, 게이지가 200K가 아닌 1M 기준(낮은 fullness)으로 표시.

- [ ] **Step 3: git 상태 정리 확인**

Run: `git log --oneline -4 && git status`
Expected: Task 1-3의 3개 커밋, working tree 깨끗.

---

## 변경하지 않는 것 (확인 완료, 무변경)

- `ClaudeSettingsReader.swift` — `extractModelKey`가 `(opus|sonnet|haiku)-{major}-{minor}` 일반 스캔 → `opus-4-8` 자동 매칭.
- `JSONLParser.swift` — last-turn-wins, 스왑 자동 반영.
- `ModelBadge.swift` / `SessionRow.swift` / `ContextGauge.swift` — `family()`/`displayName()` 소비자, 자동 동작.

## 작업 후 후속 (계획 외, 별도)

- 메모리 `model_47_context_default.md` 정정: 오늘 공식 문서 기준 4.6/4.7/4.8 모두 1M이 표준이라는 사실 반영.
- 메모리에 `usage.speed` 필드(fast mode 노출 경로) 기록 + v0.5.0 릴리스 메모.
