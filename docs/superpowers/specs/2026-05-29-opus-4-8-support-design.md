# Opus 4.8 지원 — 설계 (Claude Code Monitor)

**작성일:** 2026-05-29
**상태:** 승인 대기

## 1. 배경

Opus 4.8이 출시되어 Claude Code(`2.1.154`+)에서 선택 가능하다. 이 앱은 `~/.claude/projects/**/*.jsonl` transcript의 `message.model` 필드를 읽어 모델 라벨·컨텍스트 게이지를 표시하므로, 새 모델 ID를 인식하도록 갱신해야 한다.

## 2. 확인된 사실 (공식 문서 + 실측 교차검증)

| 항목 | 값 | 근거 |
|---|---|---|
| API 모델 ID | `claude-opus-4-8` (dateless pinned snapshot, alias 없음) | platform.claude.com models/overview |
| Bedrock ID | `anthropic.claude-opus-4-8` (`-v1` 접미사 없음) | 동 문서 legacy/latest 표 |
| 컨텍스트 창 | **1M tokens (표준)** — beta 헤더 불필요. Microsoft Foundry만 200K | models/overview, context-windows 문서 |
| Max output | 128k tokens | models/overview |
| 가격 | $5 input / $25 output per MTok (4.7 동일, 200K 초과 프리미엄 없음) | models/overview |
| Claude Code | `2.1.154`에서 추가, `2.1.156` 버그픽스. effort 기본 `high` | CHANGELOG |
| **JSONL `model` 실측값** | 순수 `claude-opus-4-8` (실측 2479회). `[1m]`·provider 접두사 **없음** | 사용자 머신 transcript 직접 grep |

### fast mode / effort 노출 — 실측 조사 결과 (이번 범위에서 제외)

- **effort (high/xhigh):** JSONL에 구조화된 필드로 기록되지 **않음** (`effort`는 산문/시스템 텍스트에만 등장, `reasoning_effort` 키 없음). → 노출 불가.
- **fast mode:** `message.usage.speed` 필드 존재 (실측: `"standard"`만 관측, 4.7·4.8 모두). 일부 턴에는 필드 자체가 없음. 실제 fast 세션 샘플이 0개라 `"fast"`/`"faster"` 값 문자열을 **검증하지 못함**. → 근거 없는 추정에 코드를 걸지 않기 위해 이번엔 제외. `usage.speed` 경로는 메모리에 기록 후, 실제 fast 세션 값 확인되면 별도 작업.

## 3. 설계 결정 (사용자 승인 완료)

1. **컨텍스트 게이지: Inherent 1M.** `claude-opus-4-8`을 settings.json 무관 항상 1M으로 처리 — 현 코드의 4.7/Sonnet 4.7 분기와 동일. 라벨의 `(1M)` 접미사는 기존대로 settings.json에 `[1m]`이 있을 때만 표시(기존 동작 유지).
2. **버전: 0.5.0** (minor — 새 플래그십 모델 지원을 의미 있는 릴리스로 표기).
3. **범위: 순수 4.8 지원만.** fast mode/effort 미포함.

## 4. 변경 대상 (검증된 file:line 기준)

| # | 파일 | 변경 |
|---|---|---|
| 1 | `Sources/ClaudeCodeMonitor/Utilities/ModelNameFormatter.swift:34-46` | `knownModels` 배열 맨 앞(35행 위)에 `("opus-4-8", "Opus 4.8")` 삽입. newest-first 불변식 유지. `opus-4-8`/`opus-4-7`은 substring 겹침 없어 순서 안전 |
| 2 | `Sources/ClaudeCodeMonitor/Utilities/ModelContextLimits.swift:39` | inherent-1M 분기에 `lower.contains("opus-4-8")` 추가 |
| 3 | `Sources/ClaudeCodeMonitor/Utilities/ModelContextLimits.swift:9-13, 26` | doc 코멘트에 4.8 반영, "Values as of 2026-05" 갱신 |
| 4 | `Info.plist:14,16` | `CFBundleVersion` 7→8, `CFBundleShortVersionString` 0.4.1→0.5.0 |
| 5 | `Tests/ClaudeCodeMonitorTests/` | 4.8 회귀 테스트(아래) |
| 6 | `CHANGELOG.md` | `[0.5.0]` 섹션 추가 (Added: Opus 4.8 인식 + 1M 컨텍스트) |

### 무변경 확인 (모델-불문 로직)

- `ClaudeSettingsReader.swift` — `extractModelKey`가 `(opus|sonnet|haiku)-{major}-{minor}`를 일반 스캔 → `opus-4-8` 자동 매칭.
- `JSONLParser.swift` — last-turn-wins로 model 갱신, 스왑 자동 반영.
- `ModelBadge.swift` / `SessionRow.swift` / `ContextGauge.swift` — `family()`(→`.opus`→orange)·`displayName()` 소비자, 자동 동작.
- `ModelNameFormatter.family()` / `displayName()` fallback — "opus" 포함 문자열 자동 처리.

## 5. 테스트 (회귀 가드)

이 머신은 **Xcode.app 없이 Command Line Tools만** 있어 `swift test`(XCTest) 실행 불가 — 기존 테스트 파일도 이를 명시. 테스트는 **작성하되**, 검증은 `swift build`(컴파일 확인) + 코드 인스펙션으로 대체하고, XCTest 실행은 Xcode 보유 머신에서 수행한다고 명시.

추가 테스트:
1. `ModelContextLimits.maxContext(for: "claude-opus-4-8")` == `1_000_000` (settings.json `[1m]` 매핑 **없이**) — Change 2 회귀 가드. (4.7이 CC 2.1.117에서 200K로 오인된 그 실패 모드)
2. `ModelNameFormatter.displayName(from: "claude-opus-4-8")` == `"Opus 4.8"`, provider 접두사판 `"us.anthropic.claude-opus-4-8"`도 `"Opus 4.8"`.
3. `ModelNameFormatter.family(from: "claude-opus-4-8")` == `.opus`.
4. 순서 가드: 4.8이 4.7/4.6에 의해 shadow되지 않음.

## 6. 리스크

1. **(최우선) 1M이 게이지에 반영 안 되면 5배 과대보고.** JSONL `model`엔 `[1m]`이 없고 4.8은 1M이 기본이라 settings 참조로는 못 잡음 → Change 2(inherent 1M)가 이를 닫는 load-bearing 변경. 없으면 모든 4.8 세션이 200K로 오인.
2. **메모리 충돌.** `model_47_context_default.md`("4.7=1M은 틀림")는 오늘 공식 문서(4.6/4.7/4.8 모두 1M 표준)와 어긋남. 작업 후 메모리 정정 필요.
3. **`(1M)` 라벨 비대칭(기존 결함 계승).** settings에 `[1m]` 있는 4.8은 "Opus 4.8 (1M)", 없으면 "Opus 4.8" — 둘 다 1M인데 라벨이 다름. 4.7부터 있던 cosmetic 이슈, 이번 범위 밖.

## 7. Non-Goals

- fast mode 인디케이터 (데이터는 있으나 값 미검증 → 다음 작업)
- effort(high/xhigh) 노출 (JSONL에 데이터 없음)
- 가격 표시 (앱이 현재 미표시, 4.8 가격은 4.7과 동일해 델타 없음)
