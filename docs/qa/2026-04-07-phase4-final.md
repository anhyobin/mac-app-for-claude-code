# QA 리포트: Phase 4 (최종) — 에이전트 상세 + 폴리시

**날짜**: 2026-04-07 22:15
**마일스톤**: Phase 4 — AgentDetailView + UI 폴리시 + 전체 통합
**상태**: FAIL
**프로젝트 유형**: macOS Native (Swift + SwiftUI)

## 평가 점수

| 평가 축 | 점수 | 기준 | 판정 |
|---------|------|------|------|
| Functionality (기능 완성도) | 4/5 | >= 4 | PASS |
| Spec Fidelity (스펙 충실도) | 3/5 | >= 4 | FAIL |
| User Experience (사용자 경험) | 3/5 | >= 4 | FAIL |
| Edge Cases (경계 조건) | 3/5 | >= 3 | PASS |
| Design Quality (디자인 품질) | N/A | N/A | N/A |

## 요약

| 카테고리 | 테스트 | 성공 | 실패 |
|----------|--------|------|------|
| 빌드 검증 | 3 | 3 | 0 |
| parseRecentMessages | 5 | 5 | 0 |
| extractFileChanges | 4 | 4 | 0 |
| AgentDetailView 구조 | 4 | 4 | 0 |
| UI 폴리시 | 6 | 6 | 0 |
| 코드 구조 | 4 | 4 | 0 |
| 스펙 충실도 | 5 | 4 | 1 |
| 통합 플로우 | 7 | 6 | 1 |
| **합계** | **38** | **36** | **2** |

## 빌드 검증

| # | 테스트 | 결과 | 비고 |
|---|--------|------|------|
| 1 | `swift build` (debug) | PASS | Build complete (0.12s), Swift 6 경고 0건 |
| 2 | `swift build -c release` | PASS | Build complete (0.13s) |
| 3 | `bash scripts/build-app.sh` | PASS | ClaudeCodeMonitor.app 824K, codesign 유효 |

## parseRecentMessages 검증 (실제 데이터)

**대상**: agent-a4a07ddb8634754fc.jsonl (1,080,145 bytes, 492 messages)

| # | 검증 항목 | 결과 | 비고 |
|---|----------|------|------|
| 1 | 마지막 10개 메시지 추출 | PASS | `entries.suffix(count)` 정확 |
| 2 | user/assistant 역할 구분 | PASS | role 필드 정확 |
| 3 | contentPreview 추출 | PASS | text/thinking 블록에서 100자 제한 |
| 4 | toolUses 추출 | PASS | tool_use 블록에서 name 추출 |
| 5 | isMeta 필터링 | PASS | meta user 메시지 제외 |

### 실제 출력
```
[assistant] (empty) | tools: Bash
[user] (empty)
[assistant] 31 Swift source files total across all 4 phases.
[assistant] (empty) | tools: TaskUpdate
[assistant] (empty) | tools: SendMessage
[user] (empty)
[user] (empty)
[assistant] Phase 4 is complete. All 4 phases implemented across 31 Swif
[user] <teammate-message teammate_id="team-lead" ...
[assistant] Task #12 is already completed. All 6 items implemented: 1
```

## extractFileChanges 검증 (실제 데이터)

| # | 검증 항목 | 결과 | 비고 |
|---|----------|------|------|
| 1 | Edit/Write/NotebookEdit 필터링 | PASS | fileTools Set 매칭 |
| 2 | file_path 추출 (`input.file_path`) | PASS | 실제 경로 정확 추출 |
| 3 | 중복 제거 (경로별 최신) | PASS | 32 entries, 32 unique |
| 4 | 타임스탬프 기준 정렬 | PASS | 최신 순 |

### 실제 출력 (상위 10개)
```
[Write] MenuBarContentView.swift
[Write] SessionRow.swift
[Write] SessionDetailView.swift
[Write] AgentRow.swift
[Write] AgentDetailView.swift
[Edit]  ClaudeDataStore.swift
[Edit]  JSONLParser.swift
[Write] AgentDetailData.swift
[Write] FileChange.swift
[Write] ConversationEntry.swift
```

## AgentDetailView 구조 검증

| # | 섹션 | 존재 | 검증 |
|---|------|------|------|
| 1 | Tool Breakdown (FlowLayout) | PASS | sortedTools + 캡슐 뱃지 |
| 2 | Files Modified | PASS | doc.fill 아이콘 + shortPath (head truncation) |
| 3 | Recent Messages | PASS | user(person.fill)/assistant(cpu) + preview + tool tags |
| 4 | Empty State | PASS | "No activity data" 메시지 |

### FlowLayout 커스텀 레이아웃
- `Layout` 프로토콜 준수: PASS
- `sizeThatFits` + `placeSubviews` 구현: PASS
- 줄바꿈 로직 (maxWidth 초과 시): PASS

## UI 폴리시 검증

| # | 항목 | 구현 | 비고 |
|---|------|------|------|
| 1 | 애니메이션 | PASS | `.animation(.easeInOut(duration: 0.2))` — SessionRow, AgentRow |
| 2 | 로딩 상태 | PASS | `ProgressView().controlSize(.small)` — SessionRow, AgentRow |
| 3 | 빈 상태 | PASS | 5개 빈 상태 메시지 (active/recent/agents/tasks/activity) |
| 4 | 버전 표시 | PASS | "v0.1.0" 좌측 하단 |
| 5 | Background 로딩 | PASS | `Task.detached` — loadSessionDetail, loadAgentDetail |
| 6 | 캐시 정리 | PASS | `evictStaleCache()` — 활성/최근에 없는 세션 캐시 제거 |

## 코드 구조 검증

**소스 파일 수**: 31개 (Sources/ 하위) — Phase 4에서 4개 신규 추가

### Phase 4 신규 파일 (4개)
| # | 파일 | 존재 | 역할 |
|---|------|------|------|
| 1 | Models/ConversationEntry.swift | PASS | 대화 메시지 모델 |
| 2 | Models/FileChange.swift | PASS | 파일 변경 모델 |
| 3 | Models/AgentDetailData.swift | PASS | 에이전트 상세 데이터 번들 |
| 4 | Views/AgentDetailView.swift | PASS | 3섹션 상세 뷰 + FlowLayout |

## 스펙 충실도 체크리스트

| # | 요구사항 (Phase 4 plan) | 구현 여부 | 동작 확인 | 비고 |
|---|------------------------|----------|----------|------|
| 1 | 에이전트 클릭 -> 최근 대화 | PASS | PASS | 마지막 10개 메시지 |
| 2 | 에이전트 클릭 -> 수정 파일 | PASS | PASS | 전체 스캔, 32개 파일 추출 |
| 3 | 에이전트 클릭 -> 도구 분석 | PASS | FAIL | **도구 분석이 최근 10개 메시지에서만 추출 — 전체 175개 중 3개만 표시 (1.7%)** |
| 4 | 다크 모드 마감 | PASS | PASS | SwiftUI 네이티브 자동 지원 |
| 5 | 애니메이션 + 에러 처리 | PASS | PASS | easeInOut 0.2s, guard/try 패턴 |

## 통합 플로우 (Phase 1-4)

| # | 플로우 단계 | 코드 경로 | 판정 |
|---|-----------|----------|------|
| 1 | 메뉴바 아이콘 + 세션 수 | ClaudeCodeMonitorApp -> MenuBarExtra | PASS |
| 2 | 활성 세션 목록 | ClaudeDataStore.activeSessions -> ActiveSessionsSection | PASS |
| 3 | 최근 세션 목록 | ClaudeDataStore.recentSessions -> RecentSessionsSection | PASS |
| 4 | 세션 확장 (에이전트/태스크) | SessionRow.isExpanded -> loadSessionDetail -> SessionDetailView | PASS |
| 5 | 에이전트 확장 (상세) | AgentRow.isExpanded -> loadAgentDetail -> AgentDetailView | PASS |
| 6 | 도구 분석 정확도 | AgentDetailView.toolBreakdown from 10 recent msgs only | FAIL |
| 7 | Quit 동작 | NSApplication.shared.terminate(nil) | PASS |

## 실패한 테스트

### 1. [MEDIUM] 도구 분석이 최근 10개 메시지에서만 추출

- **위치**: `ClaudeDataStore.swift:179-183` (loadAgentDetail)
- **입력**: agent-a4a07ddb8634754fc.jsonl (492 messages, 175 tool uses)
- **예상**: 전체 도구 분석 — Bash:46, Write:44, Read:29, Edit:22 등 9개 도구
- **실제**: 최근 10개 메시지에서 추출 — Bash:1, TaskUpdate:1, SendMessage:1 (3개 도구)
- **심각도**: MEDIUM
- **근거**: 사용자가 에이전트 행에서 "136 tools"를 보고 확장하면 "Tools" 섹션에 3개만 표시됨. "Tools" 라벨이 전체 분석을 암시하지만 실제로는 1.7%만 표시. 사용자가 정상 사용 중 즉시 인지할 수 있는 불일치.
- **수정 방향**: `loadAgentDetail`에서 `toolBreakdown`을 recent messages가 아닌 전체 JSONL에서 추출하거나, `SubagentLoader.scanAgentJSONL`이 이미 전체 파일을 스캔하므로 거기서 per-tool dictionary를 반환하도록 수정. 코드 변경 최소화를 위해 후자 추천:
  1. `SubagentInfo`에 `toolBreakdown: [String: Int]` 필드 추가
  2. `SubagentLoader.scanAgentJSONL`에서 tool name별 카운트 딕셔너리 반환
  3. `loadAgentDetail`에서 `SubagentInfo.toolBreakdown` 사용 (이미 캐시된 데이터)

## 검증 커맨드

```bash
# 빌드 + 앱 번들
cd /Users/anhyobin/dev/mac-app-for-claude && bash scripts/build-app.sh

# 앱 실행
open ClaudeCodeMonitor.app
```

## 결론

**권장사항**: FIX REQUIRED

빌드, 코드 구조, 파일 변경 추출, 최근 메시지 파싱은 모두 정확하다. 그러나 도구 분석(Tool Breakdown)이 전체 JSONL이 아닌 최근 10개 메시지에서만 추출되어, 실제 175개 도구 사용 중 3개만 표시하는 문제가 있다. 에이전트 행의 "136 tools" 표시와 상세 뷰의 "3 tools" 간 불일치는 사용자가 정상 사용 중 즉시 인지할 수 있는 MEDIUM 이슈이며, PROCEED 기준을 충족하지 못한다.
