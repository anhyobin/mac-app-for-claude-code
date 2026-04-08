# Claude Code Monitor

macOS 메뉴바에서 Claude Code 세션과 에이전트를 실시간으로 모니터링하는 네이티브 앱

## 개요

Claude Code CLI를 사용할 때 터미널 외부에서 세션 상태를 파악하기 어렵습니다. Claude Code Monitor는 macOS 메뉴바에 상주하며, 활성 세션 수, 에이전트 팀 구성, 토큰 사용량, 태스크 진행 상황을 한눈에 보여줍니다.

기존 웹 대시보드(claude-code-local-monitor)의 외부 의존성 문제를 해결하기 위해, 의존성 없는 순수 Swift/SwiftUI로 구현했습니다.

![메뉴바 스크린샷](img/claudecode.png)

## 주요 기능

- **실시간 세션 모니터링**: 활성 세션을 5초 주기로 감지, FSEvents 기반 즉시 반응
- **에이전트 팀 추적**: 서브에이전트(dev, qa, review 등)의 활성/완료 상태, 토큰 사용량, 도구 호출 횟수 표시
- **토큰 사용량 집계**: 메인 세션 + 전체 서브에이전트의 input/output/cache 토큰 합산
- **태스크 보드**: 세션별, 팀별 태스크 목록과 진행 상태(pending/in_progress/completed) 표시
- **에이전트 상세 정보**: 최근 메시지, 수정된 파일 목록, 도구별 사용 빈도 확인
- **최근 세션 히스토리**: 종료된 세션의 모델명, 소요 시간, 토큰 사용량 요약

## 기술 스택

| 영역 | 기술 |
|------|------|
| 언어 | Swift 6.0 (Strict Concurrency) |
| UI | SwiftUI, MenuBarExtra(.window) |
| 빌드 | Swift Package Manager (Xcode 불필요) |
| 파일 감시 | FSEvents (CoreServices) |
| 최소 요구사항 | macOS 14.0+, Apple Silicon (arm64) |

## 시작하기

### 사전 요구사항

- macOS 14.0 (Sonoma) 이상
- Xcode Command Line Tools (`xcode-select --install`)
- Claude Code CLI가 설치되어 있고, 한 번 이상 실행한 적이 있어야 합니다 (`~/.claude/` 디렉토리 존재)

### 빌드 및 실행

```bash
git clone <repo-url>
cd mac-app-for-claude
bash scripts/build-app.sh
open ClaudeCodeMonitor.app
```

빌드 결과물은 프로젝트 루트에 `ClaudeCodeMonitor.app` (약 1.0MB)으로 생성됩니다.

### 배포

`.app` 번들을 zip으로 압축하여 공유할 수 있습니다. ad-hoc 서명이 적용되어 있으므로 다른 Mac에서 처음 실행 시 시스템 설정 > 개인정보 보호 및 보안에서 허용이 필요합니다.

```bash
zip -r ClaudeCodeMonitor.zip ClaudeCodeMonitor.app
```

## 프로젝트 구조

```
mac-app-for-claude/
├── Package.swift                    # SPM 패키지 정의
├── Info.plist                       # 앱 번들 메타데이터
├── Sources/ClaudeCodeMonitor/
│   ├── App/
│   │   └── ClaudeCodeMonitorApp.swift   # 앱 엔트리포인트, MenuBarExtra 설정
│   ├── Models/                      # 데이터 모델
│   │   ├── ActiveSession.swift      # 활성 세션
│   │   ├── SessionLog.swift         # 최근 세션 요약
│   │   ├── SubagentInfo.swift       # 서브에이전트 정보
│   │   ├── TokenUsage.swift         # 토큰 사용량
│   │   ├── TaskEntry.swift          # 태스크 항목
│   │   ├── ConversationEntry.swift  # 대화 메시지
│   │   ├── FileChange.swift         # 파일 변경 기록
│   │   ├── SessionExpandedData.swift # 세션 확장 데이터 (에이전트+태스크+토큰)
│   │   ├── AgentDetailData.swift    # 에이전트 상세 데이터
│   │   ├── SubagentMeta.swift       # 에이전트 메타 정보
│   │   └── SessionFileEntry.swift   # 세션 파일 JSON 구조
│   ├── DataLayer/                   # 데이터 읽기/파싱
│   │   ├── ClaudeDataStore.swift    # 중앙 데이터 저장소 (@Observable)
│   │   ├── SessionFileReader.swift  # ~/.claude/sessions/ JSON 읽기
│   │   ├── JSONLParser.swift        # JSONL 파싱 (토큰, 메시지, 파일 변경)
│   │   ├── SubagentLoader.swift     # 서브에이전트 JSONL/메타 로딩
│   │   ├── TaskLoader.swift         # 태스크 JSON 로딩
│   │   ├── FileWatcher.swift        # FSEvents 래퍼
│   │   └── PIDValidator.swift       # 프로세스 생존 확인
│   ├── Views/                       # SwiftUI 뷰
│   │   ├── MenuBarContentView.swift # 메인 팝오버 레이아웃
│   │   ├── ActiveSessionsSection.swift
│   │   ├── SessionRow.swift         # 세션 행 (확장 가능)
│   │   ├── SessionDetailView.swift  # 세션 확장 시 토큰/에이전트/태스크
│   │   ├── AgentRow.swift           # 에이전트 행 (확장 가능)
│   │   ├── AgentDetailView.swift    # 에이전트 확장 시 도구/파일/메시지
│   │   ├── RecentSessionsSection.swift
│   │   ├── StatusIndicator.swift    # 활성/비활성 상태 원형 표시
│   │   └── TokenBadge.swift         # 토큰 수 뱃지
│   ├── Utilities/
│   │   ├── TokenFormatter.swift     # 토큰 수 포맷 (1.2K, 5.3M)
│   │   ├── RelativeTimeFormatter.swift  # 경과 시간 포맷 (3h 42m)
│   │   ├── ModelNameFormatter.swift # 모델명 축약 (claude-opus-4-6 -> Opus 4.6)
│   │   └── PathDecoder.swift        # 프로젝트 경로 인코딩/디코딩
│   └── Resources/                   # 번들 리소스
│       ├── app-icon.png             # 앱 아이콘
│       ├── menubar-icon.png         # 메뉴바 아이콘 (@1x)
│       └── menubar-icon@2x.png      # 메뉴바 아이콘 (@2x)
├── Tests/ClaudeCodeMonitorTests/    # 테스트 디렉토리
├── scripts/
│   └── build-app.sh                 # 릴리스 빌드 + .app 번들 생성 스크립트
├── img/                             # 문서용 이미지
│   ├── claudecode.png               # 메뉴바 아이콘 원본 (흰색)
│   └── claudecode-color.png         # 앱 아이콘 원본 (컬러)
└── docs/
    └── qa/                          # QA 리포트
```

## 문서

- [아키텍처](./docs/architecture.md) -- 시스템 구조, 데이터 흐름, 주요 결정 사항
- [개발 가이드](./docs/development.md) -- 환경 설정, 빌드, 디버깅, 코드 컨벤션
- [프로젝트 진행 상황](./docs/progress.md) -- 작업 이력과 다음 계획
