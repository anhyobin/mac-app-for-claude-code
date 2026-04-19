# 아키텍처

## 시스템 개요

Claude Code Monitor는 Claude Code CLI가 로컬 파일시스템에 기록하는 세션/프로젝트/태스크 데이터를 읽어 macOS 메뉴바에 표시하는 읽기 전용(read-only) 모니터링 앱입니다. 외부 네트워크 통신 없이, `~/.claude/` 디렉토리의 파일만 참조합니다.

## 아키텍처 다이어그램

```
┌─────────────────────────────────────────────────────────┐
│                    SwiftUI Views                        │
│  MenuBarContentView → SessionRow → SessionDetailView    │
│                        AgentRow → AgentDetailView       │
│                        RecentSessionsSection            │
└──────────────┬──────────────────────────────────────────┘
               │ @Observable 바인딩
┌──────────────▼──────────────────────────────────────────┐
│                   ClaudeDataStore                       │
│  - activeSessions: [ActiveSession]                      │
│  - recentSessions: [SessionLog]                         │
│  - expandedSessionData: [String: SessionExpandedData]   │
│  - agentDetailData: [String: AgentDetailData]           │
│  + startMonitoring() — 5초 타이머 + FSEvents            │
│  + loadSessionDetail() — 에이전트/태스크/토큰 로딩      │
│  + loadAgentDetail() — 메시지/파일변경/도구분석 로딩    │
└──────┬──────────┬──────────┬───────────┬────────────────┘
       │          │          │           │
┌──────▼───┐ ┌───▼──────┐ ┌▼────────┐ ┌▼──────────┐
│SessionFile│ │  JSONL   │ │Subagent │ │  Task     │
│ Reader   │ │ Parser   │ │ Loader  │ │  Loader   │
└──────┬───┘ └───┬──────┘ └┬────────┘ └┬──────────┘
       │         │         │           │
┌──────▼─────────▼─────────▼───────────▼──────────────────┐
│                 ~/.claude/ (로컬 파일시스템)              │
│  sessions/*.json    — 활성 세션 목록                     │
│  projects/*/*.jsonl — 세션 대화 로그                     │
│  projects/*/subagents/agent-*.jsonl — 에이전트 로그      │
│  tasks/*/*.json     — 태스크 목록                        │
└─────────────────────────────────────────────────────────┘
```

## 레이어 구조

### 1. App Layer (`App/`)

`ClaudeCodeMonitorApp`이 앱 엔트리포인트입니다. `MenuBarExtra(.window)` 스타일로 메뉴바에 팝오버 윈도우를 표시하며, `LSUIElement = true`로 Dock에는 나타나지 않습니다. `ClaudeDataStore`를 `@State`로 생성하고 `.environment()`를 통해 전체 뷰 트리에 주입합니다.

### 2. Views Layer (`Views/`)

SwiftUI 뷰 계층은 다음과 같습니다:

```
MenuBarContentView
├── ActiveSessionsSection
│   └── SessionRow (확장 가능)
│       └── SessionDetailView
│           ├── 토큰 요약 (In/Out/Cache)
│           ├── Active 에이전트 목록
│           │   └── AgentRow (확장 가능)
│           │       └── AgentDetailView (도구/파일/메시지)
│           ├── Completed 에이전트 목록 (접을 수 있음, 5개 제한 + "Show all")
│           └── 태스크 목록
└── RecentSessionsSection
    └── RecentSessionRow (모델명, 소요시간, 토큰)
```

60초마다 `TimelineView`로 상대 시간 표시를 갱신합니다.

### 3. DataLayer (`DataLayer/`)

| 컴포넌트 | 역할 | 데이터 소스 |
|----------|------|-------------|
| `ClaudeDataStore` | 중앙 데이터 저장소, 모니터링 루프 관리 | 다른 DataLayer 컴포넌트 조합 |
| `SessionFileReader` | 활성 세션 목록 읽기 | `~/.claude/sessions/*.json` |
| `JSONLParser` | JSONL 파일에서 토큰/메시지/파일변경 추출 | `~/.claude/projects/*/*.jsonl` |
| `SubagentLoader` | 서브에이전트 JSONL + 메타 파일 로딩 | `projects/*/subagents/agent-*.{jsonl,meta.json}` |
| `TaskLoader` | 태스크 JSON 로딩 (세션별 + 팀별) | `~/.claude/tasks/*/*.json` |
| `FileWatcher` | FSEvents 래퍼, 파일 변경 콜백 | `sessions/` 디렉토리 감시 |
| `PIDValidator` | `kill(pid, 0)` 기반 프로세스 생존 확인 | OS 커널 |

### 4. Models (`Models/`)

순수 데이터 구조체(struct)로 구성됩니다. 모두 `Sendable`을 준수하며, 뷰와 DataLayer 간 안전하게 전달됩니다.

### 5. Utilities (`Utilities/`)

| 유틸리티 | 역할 |
|----------|------|
| `TokenFormatter` | 토큰 수를 K/M 단위로 포맷 (예: `1234` -> `1.2K`) |
| `RelativeTimeFormatter` | 경과 시간을 사람이 읽기 쉬운 형태로 포맷 (예: `3h 42m`) |
| `ModelNameFormatter` | Claude 모델 전체 이름을 축약형으로 변환 (예: `Opus 4.6`) |
| `PathDecoder` | 프로젝트 경로에서 이름 추출 및 Claude CLI 경로 인코딩 규칙 적용 |

## 데이터 흐름

### 활성 세션 감지

1. `ClaudeDataStore.startMonitoring()` 호출 시 5초 주기 폴링 타이머 시작
2. `FileWatcher`가 `~/.claude/sessions/` 디렉토리를 FSEvents로 감시, 변경 시 즉시 콜백
3. `SessionFileReader`가 모든 `*.json` 파일을 읽고, `PIDValidator`로 해당 프로세스 생존 여부 확인
4. 살아있는 프로세스의 세션만 `activeSessions`에 반영

### 세션 상세 로딩 (Lazy)

1. 사용자가 세션 행을 클릭하여 확장하면 `loadSessionDetail()` 호출
2. `Task.detached`에서 `SubagentLoader`, `TaskLoader`, `JSONLParser.scanTokensAndThinking()` 병렬 수행
3. 결과를 `expandedSessionData[sessionId]`에 캐싱
4. 활성 세션은 5초마다 자동 리프레시 (`refreshExpandedActiveSessions`)

### 최근 세션 스캔

1. 30초마다 `refreshRecentSessions()` 호출
2. `Task.detached` (백그라운드)에서 `projects/` 하위 모든 JSONL 파일의 mtime 확인
3. mtime 기준 상위 20개 후보에서 활성 세션을 제외하고 10개 선택
4. `JSONLParser.scanSessionSummary()`로 각 파일의 요약 정보 파싱

## 성능 최적화

### FSEvents 감시 범위 제한

`sessions/` 디렉토리만 감시합니다. 초기 버전에서 `projects/`도 감시했으나, 에이전트 팀 작업 중 초당 수백 건의 JSONL 쓰기가 발생하여 CPU 스파이크가 생겼습니다. `projects/` 변경은 30초 타이머로 충분합니다.

### mtime 기반 캐싱

`SubagentLoader`와 `ClaudeDataStore`는 파일의 mtime(수정 시간)을 캐싱하여, 변경되지 않은 파일은 재파싱하지 않습니다. 에이전트가 10개 이상일 때 I/O를 약 90% 절감합니다.

### 글로벌 디렉토리 스킵

`~/.claude/projects/` 아래의 `-` 디렉토리(글로벌 컨텍스트)에는 6000개 이상의 파일이 존재할 수 있습니다. `scanRecentSessions()`에서 1글자 이하 디렉토리를 건너뛰어 불필요한 순회를 방지합니다.

### Completed 에이전트 스킵

`refreshExpandedActiveSessions()`에서 활성(active) 에이전트의 상세 정보만 리프레시하고, 완료(completed) 에이전트는 캐시된 데이터를 유지합니다.

### JSONL 파일 크기 제한

50MB 이상의 JSONL 파일은 읽지 않습니다. 비정상적으로 큰 로그 파일이 메모리를 과도하게 사용하는 것을 방지합니다.

## 주요 결정 사항

| 결정 | 이유 | 대안 검토 |
|------|------|----------|
| MenuBarExtra(.window) 사용 | 네이티브 메뉴바 팝오버 지원, macOS 14+ API | NSPopover 직접 구현 (보일러플레이트 많음) |
| SPM 전용 빌드 | Xcode 프로젝트 관리 불필요, CI 친화적 | Xcode project (오버헤드) |
| FSEvents로 sessions/ only 감시 | CPU 스파이크 방지 (projects/ 감시 시 발생) | 전체 ~/.claude/ 감시 (성능 문제) |
| @Observable (Swift 5.9+) | SwiftUI 통합이 간결, ObservableObject 대비 boilerplate 감소 | ObservableObject + @Published |
| PID kill(0) 검증 | 가장 가벼운 프로세스 확인 방법 | /proc 파싱 (macOS 미지원) |
| ad-hoc 서명 | 개인 배포용으로 충분, 개발자 인증서 불필요 | Developer ID 서명 (App Store 배포 시 필요) |
| 경로 인코딩: `/` -> `-`, `.` -> `-` | Claude CLI의 기존 인코딩 규칙을 그대로 따름 | lossy하지만 역디코딩이 필요 없는 구조 |

## 보안 고려사항

- **읽기 전용**: 앱은 `~/.claude/` 디렉토리를 읽기만 하며, 어떤 파일도 수정하지 않습니다
- **네트워크 없음**: 외부 서버와 통신하지 않습니다. 모든 데이터는 로컬 파일에서만 가져옵니다
- **파일 크기 제한**: 50MB 초과 파일은 무시하여 메모리 과다 사용을 방지합니다
- **PID 검증**: 세션 파일이 남아있더라도 해당 프로세스가 종료되었으면 활성 세션으로 표시하지 않습니다
