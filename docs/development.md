# 개발 가이드

## 개발 환경 설정

### 필수 도구

- **macOS**: 14.0 (Sonoma) 이상
- **Xcode Command Line Tools**: Swift 6.0 컴파일러 포함

```bash
xcode-select --install
swift --version  # Swift version 6.0 이상 확인
```

### 환경 변수

별도의 환경 변수 설정이 필요하지 않습니다. 앱은 현재 사용자의 `~/.claude/` 디렉토리만 참조합니다.

### 데이터 디렉토리 구조

앱이 읽는 Claude Code CLI의 로컬 데이터 구조:

```
~/.claude/
├── sessions/                       # 활성 세션 (JSON)
│   └── {random}.json               # {"pid", "sessionId", "cwd", "startedAt", "kind", ...}
├── projects/                       # 프로젝트별 세션 로그
│   ├── {encoded-path}/             # /Users/foo/bar -> -Users-foo-bar
│   │   ├── {sessionId}.jsonl       # 메인 세션 대화 로그
│   │   └── {sessionId}/
│   │       └── subagents/
│   │           ├── agent-{hash}.jsonl      # 서브에이전트 대화 로그
│   │           └── agent-{hash}.meta.json  # 서브에이전트 메타 정보
│   └── -/                          # 글로벌 컨텍스트 (스킵됨)
└── tasks/                          # 태스크 목록
    ├── {sessionId}/                # 세션별 태스크
    │   └── {taskId}.json
    └── {teamName}/                 # 팀별 태스크 (최근 1시간만 탐색)
        └── {taskId}.json
```

## 코드 컨벤션

### 디렉토리 구조

```
Sources/ClaudeCodeMonitor/
├── App/           # 앱 엔트리포인트 (1개 파일)
├── Models/        # 순수 데이터 구조체 (Sendable)
├── DataLayer/     # 파일 I/O, 파싱, 감시 로직
├── Views/         # SwiftUI 뷰
├── Utilities/     # 포맷터, 경로 처리
└── Resources/     # 이미지 리소스 (SPM .copy)
```

### Swift Concurrency 규칙

- `ClaudeDataStore`는 `@MainActor`에서 동작합니다
- 파일 I/O가 포함된 무거운 작업은 `Task.detached`로 백그라운드 실행합니다
- 모든 모델(Model)은 `Sendable`을 준수합니다
- DataLayer의 정적 메서드 중 파일 I/O를 수행하는 것들은 `nonisolated`입니다

### 네이밍 규칙

| 대상 | 패턴 | 예시 |
|------|------|------|
| 데이터 로더 | `{Domain}Loader` / `{Domain}Reader` | `SubagentLoader`, `SessionFileReader` |
| 파서 | `{Format}Parser` | `JSONLParser` |
| 포맷터 | `{Domain}Formatter` | `TokenFormatter`, `ModelNameFormatter` |
| 뷰 | `{역할}View` / `{역할}Section` / `{역할}Row` | `SessionDetailView`, `AgentRow` |

## 로컬 개발

### 디버그 빌드

```bash
swift build
```

디버그 바이너리는 `.build/arm64-apple-macosx/debug/ClaudeCodeMonitor`에 생성됩니다. 직접 실행하면 메뉴바에 아이콘이 나타납니다.

```bash
.build/arm64-apple-macosx/debug/ClaudeCodeMonitor
```

### 릴리스 빌드 (.app 번들)

```bash
bash scripts/build-app.sh
```

이 스크립트는 다음을 수행합니다:
1. `swift build -c release` 로 릴리스 바이너리 빌드
2. `.app` 번들 디렉토리 구조 생성
3. 바이너리, `Info.plist`, 리소스 복사
4. `codesign --force --sign -` 으로 ad-hoc 서명
5. 최종 앱 크기 출력

### 앱 실행

```bash
open ClaudeCodeMonitor.app
```

### 앱 종료

메뉴바 팝오버 하단의 "Quit" 버튼을 클릭하거나, Activity Monitor에서 프로세스를 종료합니다.

## 테스트

```bash
swift test
```

<!-- TODO: 현재 테스트 디렉토리가 비어있습니다. 유닛 테스트 추가가 필요합니다 -->

## 디버깅

### 데이터가 표시되지 않을 때

1. Claude Code CLI가 실행 중인지 확인합니다:
   ```bash
   ls ~/.claude/sessions/
   ```
   활성 세션이 있으면 `*.json` 파일이 보여야 합니다.

2. 프로젝트 로그 파일이 존재하는지 확인합니다:
   ```bash
   ls ~/.claude/projects/
   ```

3. 콘솔에서 로그를 확인합니다. 앱은 `print()`로 에러를 출력합니다:
   ```bash
   .build/arm64-apple-macosx/debug/ClaudeCodeMonitor 2>&1 | grep "\[.*\]"
   ```
   로그 접두사 예시: `[SessionFileReader]`, `[JSONLParser]`, `[SubagentLoader]`, `[TaskLoader]`

### FSEvents가 작동하지 않을 때

`FileWatcher`는 `kFSEventStreamCreateFlagFileEvents`를 사용합니다. macOS의 파일 이벤트 지연은 최대 1초(`latency: 1.0`)로 설정되어 있습니다. 파일 변경이 감지되지 않으면 5초 폴링 타이머가 백업으로 작동합니다.

### 메모리 사용량이 높을 때

- 50MB 이상의 JSONL 파일이 있는지 확인합니다 (앱에서 자동으로 무시하지만, 해당 세션 데이터는 표시되지 않습니다)
- 활성 에이전트가 매우 많은 경우(20+), 5초마다 모든 활성 에이전트 JSONL을 리프레시합니다

## 빌드 구성

### Package.swift 주요 설정

- **swift-tools-version**: 6.0
- **platforms**: macOS 14+
- **리소스**: `Sources/ClaudeCodeMonitor/Resources/`를 `.copy()`로 번들에 포함
- **외부 의존성**: 없음

### Info.plist 주요 설정

| 키 | 값 | 설명 |
|----|-----|------|
| `CFBundleIdentifier` | `com.anhyobin.ClaudeCodeMonitor` | 앱 번들 ID |
| `CFBundleShortVersionString` | `0.2.0` | 앱 버전 |
| `LSUIElement` | `true` | Dock에 아이콘 표시하지 않음 |
| `LSMinimumSystemVersion` | `14.0` | 최소 macOS 버전 |
