# QA 리포트: 메인 세션 토큰 표시 기능

**날짜**: 2026-04-09
**마일스톤**: mainTokens 필드 추가 및 세션별 토큰 합산 표시
**상태**: PASS
**프로젝트 유형**: macOS Native (Swift + SwiftUI)

## 평가 점수

| 평가 축 | 점수 | 기준 | 판정 |
|---------|------|------|------|
| Functionality (기능 완성도) | 5/5 | >= 4 | PASS |
| Spec Fidelity (스펙 충실도) | 5/5 | >= 4 | PASS |
| User Experience (사용자 경험) | 4/5 | >= 4 | PASS |
| Edge Cases (경계 조건) | 4/5 | >= 3 | PASS |
| Design Quality (디자인 품질) | N/A | N/A | N/A (메뉴바 앱, UI 변경 미포함) |

## 요약

| 카테고리 | 테스트 | 성공 | 실패 |
|----------|--------|------|------|
| 빌드 검증 | 1 | 1 | 0 |
| 코드 무결성 | 8 | 8 | 0 |
| 회귀 검증 | 5 | 5 | 0 |
| 스펙 충실도 | 6 | 6 | 0 |
| **합계** | **20** | **20** | **0** |

## 스펙 충실도 체크리스트

| # | 요구사항 | 구현 여부 | 동작 확인 | 비고 |
|---|---------|----------|----------|------|
| 1 | `scanTokensOnly(at:)` — 기존 `scanSessionSummary`와 동일한 토큰 추출 로직 | PASS | PASS | 동일한 `readFileIfAllowed`, 동일한 pre-filter (`"type":"assistant"`), 동일한 usage 키 4개 추출 |
| 2 | `SessionExpandedData` — `mainTokens` 필드 추가 | PASS | PASS | `let mainTokens: TokenUsage` 올바르게 추가됨 |
| 3 | `loadSessionDetail()` — 메인 JSONL 경로 올바름 | PASS | PASS | `~/.claude/projects/{encodedPath}/{sessionId}.jsonl` 실제 디렉토리 구조와 일치 확인 |
| 4 | `refreshActiveSessions()` — eager loading이 이미 로드된 세션 건너뜀 | PASS | PASS | `where expandedSessionData[session.id] == nil` 조건 확인 |
| 5 | `SessionRow` — `expandedSessionData`에서 토큰 데이터를 올바르게 표시 | PASS | PASS | `expanded.totalTokens.total > 0` 조건 및 `TokenFormatter.compact()` 사용 |
| 6 | `SessionDetailView` — "Total" 라벨 조건 올바름 | PASS | PASS | `!data.agents.isEmpty && data.mainTokens.total > 0` 조건 정확 |

## 테스트 결과

### 1. 빌드 검증

**PASS** — `swift build -c release` 성공 (0.12s)

```
Building for production...
[0/2] Write swift-version--1AB21518FC5DEDBE.txt
Build complete! (0.12s)
```

### 2. 코드 무결성 검증

#### 2-1. `JSONLParser.scanTokensOnly(at:)` 토큰 추출 로직

**PASS** — `scanSessionSummary`와 동일한 패턴 사용

| 항목 | scanSessionSummary | scanTokensOnly | 일치 |
|------|-------------------|----------------|------|
| 파일 읽기 | `readFileIfAllowed(at:)` | `readFileIfAllowed(at:)` | PASS |
| pre-filter | `lineStr.contains("\"type\":\"assistant\"")` | `lineStr.contains("\"type\":\"assistant\"")` | PASS |
| JSON 파싱 | `JSONSerialization.jsonObject` | `JSONSerialization.jsonObject` | PASS |
| message 접근 | `entry["message"] as? [String: Any]` | `entry["message"] as? [String: Any]` | PASS |
| usage 접근 | `message["usage"] as? [String: Any]` | `message["usage"] as? [String: Any]` | PASS |
| input_tokens | `usage["input_tokens"] as? Int ?? 0` | 동일 | PASS |
| output_tokens | `usage["output_tokens"] as? Int ?? 0` | 동일 | PASS |
| cache_read | `usage["cache_read_input_tokens"] as? Int ?? 0` | 동일 | PASS |
| cache_write | `usage["cache_creation_input_tokens"] as? Int ?? 0` | 동일 | PASS |

`scanTokensOnly`는 `scanSessionSummary`에서 토큰 추출 부분만 정확하게 추출한 경량 버전. 불필요한 메타데이터(sessionId, cwd, slug, timestamp, toolCounts 등) 파싱을 스킵하여 성능 최적화.

#### 2-2. `SessionExpandedData` — `mainTokens` 필드

**PASS**

```swift
struct SessionExpandedData: Sendable {
    let agents: [SubagentInfo]
    let tasks: [TaskEntry]
    let mainTokens: TokenUsage    // NEW
    let totalTokens: TokenUsage   // NEW
}
```

- `Sendable` 프로토콜 준수 유지 (`TokenUsage`는 이미 `Sendable`)
- `let` (immutable) 적절히 사용
- 기존 `agents`, `tasks` 필드 변경 없음

#### 2-3. `ClaudeDataStore.loadSessionDetail()` — 메인 JSONL 경로

**PASS**

경로 인코딩 검증:
- 코드: `projectPath.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".", with: "-")`
- 입력: `/Users/anhyobin/dev/mac-app-for-claude`
- 기대 결과: `-Users-anhyobin-dev-mac-app-for-claude`
- 실제 디렉토리: `~/.claude/projects/-Users-anhyobin-dev-mac-app-for-claude/` -- 존재 확인됨
- JSONL 파일: `534a63c2-bffa-4e92-8528-6c71c20b0f2f.jsonl` -- 존재 확인됨

`SubagentLoader.loadAgents`와 동일한 인코딩 패턴 사용 (라인 14-16).

#### 2-4. `refreshActiveSessions()` — eager loading

**PASS**

```swift
for session in activeSessions where expandedSessionData[session.id] == nil {
    Task {
        await loadSessionDetail(sessionId: session.id, projectPath: session.cwd)
    }
}
```

- `expandedSessionData[session.id] == nil` 조건으로 이미 로드된 세션 건너뜀
- `loadSessionDetail` 내부에도 `if !forceRefresh, expandedSessionData[sessionId] != nil { return }` 이중 가드 존재
- 새 세션만 비동기 로드 처리

#### 2-5. `SessionRow` — 토큰 배지 표시

**PASS**

```swift
if let expanded = dataStore.expandedSessionData[session.id],
   expanded.totalTokens.total > 0 {
    Text(TokenFormatter.compact(expanded.totalTokens.total))
```

- `expandedSessionData` 옵셔널 바인딩으로 안전하게 접근
- `totalTokens.total > 0` 조건으로 토큰 없는 초기 상태 처리
- `TokenFormatter.compact()` 사용하여 "1.8M" 같은 컴팩트 포맷 표시

#### 2-6. `SessionDetailView` — "Total" 라벨 조건

**PASS**

```swift
if data.totalTokens.total > 0 {
    if !data.agents.isEmpty, data.mainTokens.total > 0 {
        Text("Total")
```

조건 분석:
- `data.totalTokens.total > 0`: 토큰 데이터가 있을 때만 토큰 섹션 표시
- `!data.agents.isEmpty && data.mainTokens.total > 0`: subagent가 있고 메인 세션에도 토큰이 있을 때만 "Total" 라벨 표시
  - 솔로 세션 (에이전트 없음): "Total" 라벨 없이 In/Out 배지만 표시 -- 적절
  - 에이전트 있는 세션: "Total" 라벨로 합산임을 명시 -- 적절
  - 에이전트 있지만 메인 토큰 0: "Total" 라벨 없음 -- 에이전트 토큰만 있을 때 혼란 방지

### 3. 회귀 검증

#### 3-1. `SessionExpandedData` 생성 사이트 검증

**PASS** — `SessionExpandedData(` 생성은 `ClaudeDataStore.swift:211` 한 곳에서만 발생

```swift
return SessionExpandedData(
    agents: agents,
    tasks: tasks,
    mainTokens: mainTokens,
    totalTokens: totalTokens
)
```

새 `mainTokens`와 `totalTokens` 파라미터 모두 올바르게 전달됨.

#### 3-2. 기존 In/Out 배지 표시 로직

**PASS** — `SessionDetailView`에서 기존 In/Out 배지 로직은 변경 없이 유지

```swift
tokenLabel("In", count: data.totalTokens.inputTokens, color: .blue)
tokenLabel("Out", count: data.totalTokens.outputTokens, color: .green)
```

- `tokenLabel` 함수 구현 변경 없음 (라인 180-194)
- 색상 (blue/green), 포맷 (TokenFormatter.compact) 동일
- Cache 표시 로직도 기존과 동일 (라인 34-38)

#### 3-3. Subagent 토큰 중복 계산 없음

**PASS** — 실제 데이터로 검증 완료

검증 결과:
- 메인 JSONL (`534a63c2...jsonl`): 44개 assistant 메시지, sessionId=`534a63c2...`
- Subagent JSONL 파일들 (4개): 각각 30-48개 assistant 메시지
- 메인 JSONL과 subagent JSONL은 **물리적으로 별도 파일** -- 동일 데이터 포함 안 됨

토큰 합산 로직:
```swift
var totalTokens = mainTokens  // 메인 JSONL에서만 추출
for agent in agents {
    totalTokens.add(agent.tokens)  // 각 subagent JSONL에서만 추출
}
```

각 파일에서 독립적으로 토큰을 추출한 후 합산 -- 중복 계산 발생 불가.

#### 3-4. `scanRecentSessions` 영향 없음

**PASS** — `scanRecentSessions`는 `scanSessionSummary`를 사용하며, 새 `scanTokensOnly`와 무관. 기존 로직 변경 없음.

#### 3-5. `AgentRow` 토큰 표시 영향 없음

**PASS** — `AgentRow`는 `agent.tokens.coreTokens`를 직접 사용. `SubagentInfo.tokens`는 `SubagentLoader.scanAgentJSONL`에서 독립적으로 파싱되므로 새 변경 영향 없음.

## 사용자 경험 평가

- **토큰 배지 접기 전 표시**: SessionRow에서 확장하지 않아도 compact 토큰 배지 (예: "1.8M") 확인 가능 -- 정보 접근성 향상
- **"Total" 라벨 조건**: 솔로 세션에서는 불필요한 라벨 없이 깔끔, 팀 세션에서는 합산임을 명시 -- 맥락에 맞는 정보 제공
- **Eager loading**: 세션 목록 표시 시점에 자동 로드하여 토큰 배지 즉시 표시 -- 사용자 대기 최소화
- **이미 로드된 데이터 재사용**: `nil` 체크로 불필요한 파싱 방지 -- 성능 최적화

## 디자인 품질 평가

N/A (macOS 메뉴바 앱 -- 코드 레벨 변경으로 UI 프레임워크 미변경, Playwright 대상 아님)

## 검증 커맨드

```bash
# 빌드 검증
cd /Users/anhyobin/dev/mac-app-for-claude && swift build -c release 2>&1

# 경로 인코딩 검증
ls ~/.claude/projects/-Users-anhyobin-dev-mac-app-for-claude/*.jsonl

# 토큰 데이터 검증 (Python)
python3 -c "
import json
tokens = {'input': 0, 'output': 0}
with open('$HOME/.claude/projects/-Users-anhyobin-dev-mac-app-for-claude/534a63c2-bffa-4e92-8528-6c71c20b0f2f.jsonl') as f:
    for line in f:
        if '\"type\":\"assistant\"' not in line: continue
        entry = json.loads(line)
        usage = entry.get('message', {}).get('usage', {})
        tokens['input'] += usage.get('input_tokens', 0)
        tokens['output'] += usage.get('output_tokens', 0)
print(tokens)
"
```

## 결론

Scores: Func 5/5 | Spec 5/5 | UX 4/5 | Edge 4/5 | Design N/A

**Status**: PASS
**권장사항**: PROCEED

전체 20개 테스트 항목 모두 통과. 주요 검증 결과:

1. `scanTokensOnly`는 `scanSessionSummary`와 동일한 토큰 추출 로직을 경량화하여 올바르게 구현
2. 메인 JSONL 경로 인코딩이 `SubagentLoader`와 일관되며 실제 파일시스템 구조와 일치
3. Eager loading의 `nil` 체크로 이미 로드된 세션 재파싱 방지
4. 메인 JSONL과 subagent JSONL이 물리적으로 분리되어 토큰 중복 계산 불가능
5. "Total" 라벨 조건이 솔로/팀 세션 맥락에 맞게 동작
6. 기존 기능 (RecentSessions, AgentRow, In/Out 배지) 회귀 없음
