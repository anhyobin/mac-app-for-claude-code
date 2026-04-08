# QA 리포트: 성능 최적화 (SubagentLoader mtime 캐싱) 사전 검증

**날짜**: 2026-04-07
**마일스톤**: SubagentLoader mtime 캐싱 구현 + 전체 5/5 달성
**상태**: FAIL -- 미구현
**프로젝트 유형**: macOS Native (Swift + SwiftUI)

## 평가 점수

| 평가 축 | 점수 | 기준 | 판정 |
|---------|------|------|------|
| Functionality (기능 완성도) | 4/5 | >= 4 | PASS |
| Spec Fidelity (스펙 충실도) | 3/5 | >= 4 | FAIL |
| User Experience (사용자 경험) | 4/5 | >= 4 | PASS |
| Edge Cases (경계 조건) | 3/5 | >= 3 | PASS |
| Design Quality (디자인 품질) | N/A | N/A | N/A |

## 요약

| 카테고리 | 테스트 | 성공 | 실패 |
|----------|--------|------|------|
| 빌드 검증 | 3 | 3 | 0 |
| mtime 캐싱 구현 여부 | 3 | 0 | 3 |
| Phase 4 수정 검증 | 2 | 2 | 0 |
| 코드 품질 점검 | 5 | 4 | 1 |
| **합계** | **13** | **9** | **4** |

## 빌드 검증

| # | 테스트 | 결과 | 비고 |
|---|--------|------|------|
| 1 | `swift build` (debug) | PASS | Build complete (0.14s), 에러 0건 |
| 2 | `swift build -c release` | PASS | Build complete (0.15s) |
| 3 | `bash scripts/build-app.sh` | PASS | ClaudeCodeMonitor.app 996K, codesign 유효 |

## mtime 캐싱 검증 -- 핵심 검증 항목

### 1. [CRITICAL] SubagentLoader.loadAgents에 previousAgents 파라미터 부재

- **위치**: `Sources/ClaudeCodeMonitor/DataLayer/SubagentLoader.swift:9`
- **현재**: `static func loadAgents(sessionId: String, projectPath: String) -> [SubagentInfo]`
- **예상**: `static func loadAgents(sessionId: String, projectPath: String, previousAgents: [SubagentInfo]) -> [SubagentInfo]`
- **실제**: `previousAgents` 파라미터 없음. mtime 비교 로직 없음.
- **심각도**: CRITICAL -- 이번 마일스톤의 핵심 요구사항 미구현

### 2. [CRITICAL] mtime 비교를 통한 JSONL 재파싱 스킵 로직 부재

- **위치**: `Sources/ClaudeCodeMonitor/DataLayer/SubagentLoader.swift:33-68`
- **예상**: 각 agent JSONL의 mtime을 previousAgents의 lastActivity와 비교, 변경 없으면 이전 결과 재사용
- **실제**: 매 호출마다 모든 JSONL 파일을 무조건 전체 파싱 (`scanAgentJSONL`)
- **심각도**: CRITICAL -- 성능 최적화 로직 미구현

### 3. [CRITICAL] ClaudeDataStore에서 previousAgents 전달 부재

- **위치**: `Sources/ClaudeCodeMonitor/DataLayer/ClaudeDataStore.swift:179`
- **현재**: `SubagentLoader.loadAgents(sessionId: sessionId, projectPath: projectPath)`
- **예상**: `SubagentLoader.loadAgents(sessionId: sessionId, projectPath: projectPath, previousAgents: existingData?.agents ?? [])`
- **실제**: previousAgents를 전달하지 않음
- **심각도**: CRITICAL -- 캐싱 데이터 전달 경로 미구현

## Phase 4 수정 검증 (이전 라운드 이슈)

| # | 이전 이슈 | 상태 | 검증 |
|---|----------|------|------|
| 1 | toolBreakdown이 최근 10개 메시지에서만 추출 | FIXED | `ClaudeDataStore.swift:202-203`에서 `expandedSessionData`의 `SubagentInfo.toolBreakdown` 재사용. `SubagentLoader.scanAgentJSONL`이 전체 JSONL 스캔하여 정확한 데이터 제공 |
| 2 | 완료된 에이전트 5초 갱신 | PARTIALLY FIXED | `refreshExpandedActiveSessions`에서 `agent.isActive` 체크 존재 (line 98). 단, `loadSessionDetail` 자체가 전체 re-parse — mtime 캐싱으로 해결 예정 |

## 코드 품질 점검

| # | 항목 | 결과 | 비고 |
|---|------|------|------|
| 1 | Swift 6 concurrency | PASS | `@MainActor`, `Sendable`, `Task.detached` 올바르게 사용 |
| 2 | FileWatcher 메모리 관리 | PASS | `Unmanaged` retain/release 쌍 정확 |
| 3 | 50MB 파일 크기 제한 | PASS | `JSONLParser.maxFileSize`, `SubagentLoader.scanAgentJSONL` 모두 적용 |
| 4 | 캐시 eviction | PASS | `evictStaleCache()` 활성/최근 세션 아닌 데이터 제거 |
| 5 | 불필요한 반복 파싱 | FAIL | `loadSessionDetail(forceRefresh: true)` 호출 시 모든 agent JSONL 전체 재파싱 — mtime 캐싱 부재로 5초마다 수 MB 파일 반복 읽기 |

## 스펙 충실도 체크리스트

| # | 요구사항 | 구현 여부 | 동작 확인 | 비고 |
|---|---------|----------|----------|------|
| 1 | SubagentLoader에 previousAgents 파라미터 추가 | 미구현 | N/A | loadAgents 시그니처 변경 필요 |
| 2 | mtime 비교로 변경 없는 파일 스킵 | 미구현 | N/A | scanAgentJSONL 조건부 호출 필요 |
| 3 | ClaudeDataStore에서 previousAgents 전달 | 미구현 | N/A | expandedSessionData에서 기존 agents 추출 전달 |
| 4 | 전체 앱 5/5 달성 | 미달성 | N/A | 위 3건 미구현으로 Spec Fidelity 3/5 |

## Pre-Verdict Self-Check

1. 전문적 명성을 걸 수 있는가? -- Yes (미구현 사실 명확)
2. 사용자가 발견할 이슈를 놓쳤나? -- No
3. 심각도 판정에 망설임이 있었나? -- No (핵심 기능 미구현은 CRITICAL)
4. "but overall..." 쓰고 싶은가? -- No
5. 금지 문구 사용 여부? -- No

## 결론

**권장사항**: FIX REQUIRED

SubagentLoader mtime 캐싱은 이번 마일스톤의 핵심 요구사항이나, 현재 코드에 전혀 구현되어 있지 않다.

- `loadAgents` 시그니처에 `previousAgents` 파라미터 없음
- mtime 비교를 통한 재파싱 스킵 로직 없음
- `ClaudeDataStore`에서 기존 에이전트 데이터 전달 경로 없음

현재 코드는 5초마다 활성 세션의 모든 agent JSONL을 전체 재파싱한다. 에이전트 팀 작업 시 (10+ agents, 각 수 MB JSONL) 불필요한 I/O 부하가 발생한다. 기존 기능은 모두 정상이나, 이번 최적화 미구현으로 Spec Fidelity가 기준 미달이다.

### 수정 필요 항목 (dev 에이전트 수정용)

1. **[CRITICAL] SubagentLoader.loadAgents 시그니처 변경**
   - 위치: `SubagentLoader.swift:9`
   - 수정: `previousAgents: [SubagentInfo] = []` 파라미터 추가

2. **[CRITICAL] mtime 비교 + 캐시 재사용 로직 추가**
   - 위치: `SubagentLoader.swift:33-68` (for jsonlFile loop 내부)
   - 수정 방향:
     ```swift
     // mtime 확인
     let mtime = ... (현재 코드와 동일)
     // previousAgents에서 동일 hash의 agent를 찾고, lastActivity == mtime이면 재사용
     if let prev = previousAgents.first(where: { $0.id == hash }),
        prev.lastActivity == mtime {
         agents.append(prev)
         continue
     }
     // 변경된 경우에만 scanAgentJSONL 호출
     ```

3. **[CRITICAL] ClaudeDataStore에서 previousAgents 전달**
   - 위치: `ClaudeDataStore.swift:178-179`
   - 수정:
     ```swift
     let existingAgents = await MainActor.run {
         self.expandedSessionData[sessionId]?.agents ?? []
     }
     let agents = SubagentLoader.loadAgents(
         sessionId: sessionId,
         projectPath: projectPath,
         previousAgents: existingAgents
     )
     ```

### 검증 커맨드

```bash
# 빌드 확인
cd /Users/anhyobin/dev/mac-app-for-claude && swift build

# previousAgents 파라미터 존재 확인
grep "previousAgents" Sources/ClaudeCodeMonitor/DataLayer/SubagentLoader.swift

# mtime 비교 로직 확인
grep -n "lastActivity" Sources/ClaudeCodeMonitor/DataLayer/SubagentLoader.swift
```
