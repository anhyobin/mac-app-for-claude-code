# 워크플로우 가시성 — 설계 (Claude Code Monitor)

**작성일:** 2026-05-30
**상태:** 승인 대기
**브랜치 베이스:** `feat/opus-4-8-support` (또는 main 분기 후 신규 브랜치)

## 1. 배경 / 문제

Claude Code의 dynamic workflow(예: ultracode effort, `/workflows`)가 실행되면 다수의 서브에이전트가
페이즈 단위로 병렬 실행되며 상당한 토큰을 소비한다. 그러나 Claude Code Monitor 앱은 이 활동을
**전혀 표시하지 못한다**. 워크플로우가 12개 에이전트를 띄우고 250K 토큰을 태워도 메뉴바·드롭다운
모두 깜깜이다.

근본 원인은 디스크 레이아웃 차이다. 앱의 `SubagentLoader`는 평면 경로
`subagents/agent-*.jsonl`만 스캔하는데, 워크플로우 에이전트는 **한 단계 더 깊은**
`subagents/workflows/{wf_id}/agent-*.jsonl`에 기록된다. `SubagentLoader`는 `subagents/`를
나열해 `workflows/` 하위 디렉토리만 발견하고(`agent-*` 매칭 0개) 빈 배열을 반환한다.

## 2. 확인된 사실 (디스크 실측, 2026-05-30)

| 항목 | 값 | 근거 |
|---|---|---|
| 워크플로우 런 상태 파일 | `~/.claude/projects/{enc}/{sessionId}/workflows/{wf_id}.json` | 디렉토리 직접 탐색 |
| 워크플로우 스크립트 | `…/{sessionId}/workflows/scripts/{name}-{wf_id}.js` | 파일명에 워크플로우 이름 인코딩 |
| 워크플로우 에이전트 트랜스크립트 | `…/{sessionId}/subagents/workflows/{wf_id}/agent-{hash}.jsonl` (+ `.meta.json`) | 일반 subagent와 동일 JSONL 포맷 |
| 워크플로우 저널 | `…/subagents/workflows/{wf_id}/journal.jsonl` — `started`/`result` 이벤트만 | 실측: started 6 = result 6 |
| `.json` 기록 시점 | **완료 시점에만 최종 기록.** `startTime + durationMs == timestamp`가 정확히 일치 | 실측 (모든 `.json`이 `status:"completed"`) |
| `.json` 주요 필드 | `runId, workflowName, status, agentCount, totalTokens, totalToolCalls, durationMs, phases[], workflowProgress[], defaultModel` | 스키마 덤프 |
| `workflowProgress[]` | `workflow_phase`(index, title) + `workflow_agent`(index, label, phaseIndex, phaseTitle, agentId, agentType, model) | 에이전트→페이즈 완전 매핑 |
| 한 세션 = 일반 + 워크플로우 공존 가능 | 실측: geo-builder 세션 = flat agent 10 + workflow 1 | 디렉토리 카운트 |
| journal 매칭 키 | `agentId`로 started↔result 매칭 (1:1) | 실측 |

### 핵심 함의 — "실행 중" 감지

`.json`은 **완료 시점 스냅샷**이라 `status` 필드만으로는 *실행 중*을 절대 잡을 수 없다.
실행 중 워크플로우는 `.json`이 아직 없거나 `status`가 미완일 수 있다. 따라서 라이브 신호는
**`journal.jsonl`** 에서 와야 한다: `started` 이벤트 중 매칭되는 `result`가 없는 `agentId` =
지금 실행 중인 에이전트.

## 3. 설계 결정 (사용자 승인 완료, 시각적 브레인스토밍)

1. **표시 깊이: 전체.** 페이즈별 에이전트 트리. (옵션 A/B/C 중 C)
2. **배치: 별도 "Workflow" 섹션.** 세션 확장 뷰 **맨 위** 독립 블록. 일반 Active/Completed 에이전트 목록은 그 아래 기존 그대로. 두 데이터 모델(페이즈+라벨 vs 타입)을 섞지 않는다.
3. **메뉴바 신호: 세션 수 보라색(#5e5ce6) 틴트 + 은은한 펄스.** `/goal`의 accent-틴트 패턴 재사용. 새 글리프 없음. 상태점의 error/warning 우선순위 스택은 건드리지 않음.
4. **완료 워크플로우: 실행 중 + 최근 완료 모두 표시.** 완료는 접힌 한 줄 요약, 클릭 시 페이즈 트리 펼침.
5. **에이전트 상세 포함.** 워크플로우 에이전트도 클릭 시 기존 `AgentDetailView`(최근 메시지·수정 파일·도구 분석)로 펼침.

## 4. 데이터 모델 (Models/)

```swift
// WorkflowInfo.swift
struct WorkflowInfo: Identifiable, Sendable {
    let id: String              // wf_id
    let name: String            // .json의 workflowName 우선, 없으면 scripts/*.js 파일명에서 파싱
    let status: WorkflowRunStatus
    let phases: [WorkflowPhase]
    let totalTokens: TokenUsage
    let totalToolCalls: Int
    let agentCount: Int
    let durationMs: Int?
    let lastActivity: Date?     // workflows/{id} 디렉토리 또는 journal mtime
    var isRunning: Bool { status == .running }
}

enum WorkflowRunStatus: Sendable, Equatable { case running, completed }

// WorkflowPhase.swift
struct WorkflowPhase: Identifiable, Sendable {
    let id: Int                 // phaseIndex
    let title: String
    let agents: [SubagentInfo]  // 기존 타입 재사용
    let isComplete: Bool        // 이 페이즈의 모든 에이전트가 result를 가짐
}
```

**`SubagentInfo` 재사용.** 워크플로우 에이전트는 일반 subagent와 동일한 JSONL 포맷이므로
토큰·도구·스킬 파싱(`scanAgentJSONL`)을 그대로 쓴다. 워크플로우 라벨(`game-design-balance`)은
현재 비어 있는 `description` 필드에 담아 추가 필드 없이 해결한다. `agentType`은 meta.json의
값(대개 `general-purpose`)을 그대로 사용한다.

`SessionExpandedData`에 `let workflows: [WorkflowInfo]` 한 필드 추가.

## 5. 로더 (DataLayer/WorkflowLoader.swift)

`SubagentLoader`의 형제. mtime 캐시 패턴 동일하게 적용.

```swift
enum WorkflowLoader {
    static func loadWorkflows(sessionId: String, projectPath: String,
                              previous: [WorkflowInfo]? = nil) -> [WorkflowInfo]
}
```

**알고리즘:**
1. `subagents/workflows/` 디렉토리 나열 → `wf_*` 하위 디렉토리 목록 = 후보 워크플로우.
   (디렉토리 없으면 `[]` 반환 — 워크플로우 없는 세션은 비용 0.)
2. 각 `wf_id`에 대해:
   - `workflows/{wf_id}.json`이 있으면 파싱 → `workflowName`, `phases`, `totalTokens` 등.
   - 없거나 status 미완이면 → `scripts/{name}-{wf_id}.js` 파일명에서 `name` 파싱.
   - `subagents/workflows/{wf_id}/journal.jsonl` 파싱 → `started` set, `result` set 구축.
     - `started − result ≠ ∅` 또는 디렉토리 mtime < 60s → `status = .running`, 아니면 `.completed`.
   - `subagents/workflows/{wf_id}/agent-*.jsonl`를 `scanAgentJSONL`로 파싱 → `SubagentInfo[]`.
   - `.json`의 `workflowProgress[]`로 에이전트→페이즈 매핑(`phaseIndex`/`agentId`/`label`).
     `.json`이 없으면(실행 중 초기) 단일 "(running)" 페이즈에 전부 넣는 fallback.
3. mtime 캐시: `previous`에 같은 `wf_id`가 있고 디렉토리 mtime 불변이면 재파싱 스킵.

**정렬:** 실행 중(running) 먼저, 그다음 `lastActivity` 최신순.

## 6. 뷰 (Views/)

### 6.1 WorkflowSection.swift (신규)
`SessionDetailView`의 토큰 요약 직후, Active 섹션 **앞**에 삽입:

```
[스피너 또는 정적] Workflows
  ┌─ {name}                          (실행 중: 보라 / 완료: 회색)
  │  {status} · 페이즈 {n}/{m} · {agentCount} 에이전트 · {tokens}
  │  [진행률 바]                       (완료 에이전트 수 / 전체 에이전트 수)
  │  ✓ {완료 페이즈 제목}
  │     • {label}  [token][›]         ← AgentRow 재사용 (클릭 시 상세)
  │  ⟳ {진행 페이즈 제목}
  │     • {label} · 실행중 [token][›]
  └─ (완료 워크플로우는 접힘: "{name} ✓ 완료 · N 에이전트 · 6m 57s", 클릭 시 펼침)
```

- 실행 중 워크플로우: 항상 펼침. 진행률 바 = `result를 가진 에이전트 수 / agentCount`
  (에이전트 단위가 페이즈 단위보다 부드럽게 차오르고, journal에서 직접 계산 가능). 텍스트의
  "페이즈 {n}/{m}"는 완료 페이즈 수 표기로 별도 — 바와 텍스트는 다른 단위임을 의도.
- 완료 워크플로우: 기본 접힘(한 줄 요약), `@State` 토글로 펼침. (기존 completed-agents 패턴과 동일)
- 에이전트 행: **기존 `AgentRow` 재사용.** 단 워크플로우 에이전트는 nested 경로가 필요하므로 §6.3.

### 6.2 페이즈 상태 아이콘 (앱 색 컨벤션 준수 — `app-design-conventions` 메모리)
- **완료 페이즈: `checkmark` — `.secondary` 색** (초록 아님). `.green`은 "active"에만 쓰는 규칙;
  완료/acknowledged 상태에 green을 쓰면 "세션 active"와 시각 충돌 (v0.4.0에서 확정된 피드백).
- 진행 페이즈: 작은 `ProgressView`(스피너).
- **에이전트 점: 기존 `AgentRow`의 `isActive` 규칙 그대로 재사용 — active(mtime<60s)=초록 점,
  완료=점 없음.** 별도 색(주황 등) 추가하지 않음. 실행 중 워크플로우에서 현재 쓰이는 에이전트는
  jsonl mtime이 fresh하므로 `isActive=true`→초록 점이 자동으로 맞고, 완료 에이전트는 점 없음.
- **chevron: collapsed=`chevron.right`, expanded=`chevron.down`** (앱 전역 규칙. `up/down` 금지).
- **워크플로우 box 톤:** 실행 중 = `Color(보라 #5e5ce6).opacity(0.08)` + `cornerRadius(6, .continuous)`
  (macOS sidebar-selection 관행, GoalBanner 표준). 완료 = `.secondary.opacity(0.06)` (inert 톤).

### 6.3 AgentRow / 상세 로더 — nested 경로 지원
현재 `loadAgentDetail`은 경로를 `subagents/agent-{hash}.jsonl`로 하드코딩한다(`ClaudeDataStore.swift:377-381`).
워크플로우 에이전트는 `subagents/workflows/{wf_id}/agent-{hash}.jsonl`이므로, `loadAgentDetail`과
`AgentRow`에 **옵셔널 `workflowId: String?`** 파라미터를 추가한다. `workflowId`가 있으면 경로에
`workflows/{wf_id}/`를 끼워 넣고, `agentDetailData` 캐시 키도 `"{sessionId}/{wf_id}/{hash}"`로
충돌을 피한다. 일반 에이전트는 `workflowId: nil`로 기존 동작 유지(무변경).

## 7. ClaudeDataStore 통합

- `loadSessionDetail`의 `Task.detached` 블록 안, `SubagentLoader.loadAgents` 호출 옆에
  `WorkflowLoader.loadWorkflows(...)` 추가. mtime 캐시 입력(`previous`)은 기존 `previousAgents`와
  동일하게 `expandedSessionData[sessionId]?.workflows`에서 가져온다.
- `SessionExpandedData(...)` 생성자에 `workflows:` 인자 추가.
- **메뉴바 틴트:** `hasActiveGoal`(`ClaudeDataStore.swift:356`)과 형제인 computed 추가:
  ```swift
  var hasRunningWorkflow: Bool {
      activeSessions.contains { session in
          expandedSessionData[session.id]?.workflows.contains { $0.isRunning } == true
      }
  }
  ```
- `ClaudeCodeMonitorApp.swift`의 세션 수 `Text`: 틴트 우선순위를 정의한다 —
  **goal과 workflow가 동시 활성이면?** 색은 하나만 가능하므로 규칙: `hasActiveGoal` 우선(파랑),
  아니면 `hasRunningWorkflow`(보라). 펄스는 둘 중 하나라도 활성이면 적용.
  (이유: goal은 사용자가 명시적으로 건 종료 조건이라 더 강한 신호. 둘 다일 때 보라가 파랑을
  덮으면 goal 신호가 사라지는 역행이 됨.)

## 8. 테스트 (회귀 가드)

이 머신은 Command Line Tools만 있어 `swift test`(XCTest) 실행 불가 — 기존 테스트 파일 관행대로
**작성하되** 검증은 `swift build`(컴파일) + 코드 인스펙션으로 하고 XCTest 실행은 Xcode 머신에서.

순수 함수 위주로 가드:
1. **journal 파싱 → running 판정:** `started` 3 / `result` 2인 fixture → `status == .running`.
   `started` N / `result` N → `.completed`.
2. **이름 파싱:** `.json` 있을 때 `workflowName` 사용. 없을 때 `game-design-synthesis-wf_x.js` →
   `"game-design-synthesis"` 추출 (뒤 `-wf_…` 제거).
3. **페이즈 매핑:** `workflowProgress[]` fixture → `phaseIndex`별 `SubagentInfo` 그룹화, `label`이
   `description`에 들어감.
4. **빈 디렉토리:** `subagents/workflows/` 없음 → `[]`, 크래시 없음.
5. **경로 안전:** 공백 포함 cwd에서도 `PathDecoder.encodedProjectPath` 경유 (v0.4.1 버그 계승 가드).

테스트 fixture는 디스크 실측 데이터(roguelikes-demo `wf_b9155143-fd4`)를 축약해 사용.

## 9. 무변경 확인 (모델-불문 / 기존 로직)

- `SubagentLoader` — 평면 `agent-*`만 책임. `workflows/` 하위 디렉토리는 무시(현 동작 유지). 무변경.
- `JSONLParser` / `scanAgentJSONL` — 워크플로우 에이전트 JSONL도 동일 포맷이라 그대로 재사용.
- `AgentDetailView` — 입력 `AgentDetailData`만 받으므로 무변경. 경로 차이는 로더가 흡수.
- `TaskLoader` — 무관.
- `MenuBarDotState` — 상태점 우선순위 스택 건드리지 않음(틴트는 세션 수에만).

## 10. 리스크

1. **(최우선) `.json`이 완료 스냅샷이라 실행 중 감지가 journal 의존.** journal 포맷이 바뀌거나
   `started`/`result`가 비대칭으로 깨지면 실행 중 판정이 흔들림. → mtime 60s fallback으로 이중화.
2. **mtime 갱신 빈도.** 워크플로우 에이전트가 장시간 한 에이전트만 돌면 디렉토리 mtime이 60s를
   넘겨 "완료"로 오판될 수 있음. → journal의 unmatched `started`가 1차 신호, mtime은 보조.
3. **드롭다운 길이.** 큰 워크플로우(22 에이전트)는 페이즈 트리가 길어짐. → 완료 워크플로우 접힘 +
   페이즈당 에이전트도 기존 completed-agents의 "5개 + Show all" 패턴 적용 고려(구현 시 판단).
4. **새 모델/필드의 미래 변동.** `workflowProgress` 스키마는 비공식. `.json` 없을 때의 fallback
   (단일 running 페이즈)이 안전망.

## 11. Non-Goals

- 워크플로우 스크립트 내용(`.js`) 표시 — 코드 본문은 모니터 범위 밖.
- 워크플로우 결과(`result.synth` 등) 렌더링 — 텍스트 산문이라 드롭다운에 부적합.
- 완료 워크플로우의 영구 히스토리 — "최근"만 (세션 확장 시점에 존재하는 것).
- 워크플로우 취소/제어 — 모니터는 읽기 전용.
- `journal.jsonl`의 개별 이벤트 타임라인 — 집계만, 이벤트 스트림은 과함.
```
