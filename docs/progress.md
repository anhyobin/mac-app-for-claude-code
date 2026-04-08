# 프로젝트 진행 상황

## 현재 상태

**마지막 업데이트**: 2026-04-09 01:00
**현재 단계**: v0.1.0 완료, 문서화 완료
**진행률**: 100% (v0.1.0 마일스톤 기준)

## 완료된 작업

### 2026-04-09
- ✅ tool_result content 배열 형태 파싱 수정 (JSONLParser.parseRecentMessages)
- ✅ 메인 세션 토큰 표시 검증 (QA PASS)
- ✅ tool_result 파싱 2차 QA 검증 (PASS)
- ✅ 프로젝트 문서 작성 (README, architecture, development, progress)

### 2026-04-08
- ✅ 빌드 스크립트 개선 (scripts/build-app.sh)
- ✅ 메뉴바 아이콘 최적화 (21x13pt @2x, isTemplate)
- ✅ Info.plist 완성 (LSUIElement, 앱 아이콘 연결)

### 2026-04-07
- ✅ 프로젝트 초기 설계 및 구현
- ✅ Phase 1: 기본 메뉴바 앱 + 활성 세션 표시
- ✅ Phase 2: 세션 확장 (에이전트/태스크/토큰)
- ✅ Phase 3: 최근 세션 히스토리
- ✅ Phase 4: 에이전트 상세 (도구/파일/메시지)
- ✅ FSEvents sessions/ only 최적화 (CPU 스파이크 해결)
- ✅ SubagentLoader mtime 캐싱 (~90% I/O 감소)
- ✅ 글로벌 디렉토리(-) 스킵 최적화
- ✅ UX 리뷰 4라운드 (21건 이슈 발견/해결)
- ✅ 최종 QA 5/5, Review GO 판정

## 진행 중인 작업

없음

## 다음 단계 (v0.2 후보)

아래 항목은 v0.1.0 QA/Review 과정에서 식별된 개선 후보입니다. 사용하면서 필요성을 확인한 후 진행합니다.

1. **StreamReader 도입**: JSONLParser를 line-by-line 스트리밍으로 전환하여 대형 파일 메모리 피크 감소
2. **SubagentLoader 병렬 파싱**: withTaskGroup으로 다수 에이전트 동시 파싱
3. **RecentSessionRow 클릭 확장**: 현재 클릭 액션 없음, 세션 상세 표시 추가
4. **토큰 cache 분리 표시**: cache_read/cache_write를 별도 표시
5. **os.Logger 전환**: print() 로깅을 구조화된 os.Logger로 교체
6. **유닛 테스트 추가**: TokenFormatter, PathDecoder, RelativeTimeFormatter 등

## 블로커 / 이슈

| 이슈 | 영향 | 해결 방안 | 상태 |
|------|------|----------|------|
| PathDecoder 경로 인코딩이 lossy | 역디코딩 불가 (`/` -> `-`, `.` -> `-`) | 파일시스템 대조 방식 검토 | 현재 문제 없음 |
| 팀 태스크 shutdown 시 삭제 | 태스크 히스토리 보존 불가 | Claude Code 동작 제한, 앱에서 해결 불가 | 수용 |

## 의사결정 로그

### 2026-04-07: FSEvents 감시 범위를 sessions/ only로 제한

**배경**: 초기 구현에서 `sessions/`와 `projects/` 모두 FSEvents로 감시했으나, 에이전트 팀 작업 중 초당 수백 건의 JSONL 쓰기로 CPU 스파이크 발생
**선택지**: 1) 두 디렉토리 모두 감시 + 디바운싱 2) sessions/ only 감시 + projects/ 30초 타이머
**결정**: sessions/ only 감시 채택
**이유**: 새 세션 시작/종료는 즉시 반응해야 하지만, 대화 내용은 30초 지연이 수용 가능. CPU 스파이크 완전 해결

### 2026-04-07: SubagentLoader mtime 캐싱 도입

**배경**: 에이전트가 10개 이상일 때 5초마다 모든 에이전트 JSONL을 재파싱하면 I/O 부하가 심함
**선택지**: 1) 전체 재파싱 주기를 늘림 2) mtime 비교 후 변경된 파일만 재파싱
**결정**: mtime 기반 선택적 재파싱
**이유**: 활성 에이전트는 즉시 반영하면서, 완료된 에이전트는 캐시 사용. I/O ~90% 감소

## 내일 이어서 할 일

> 이 섹션만 읽으면 바로 작업 시작 가능

v0.1.0은 완료 상태입니다. 다음 작업 시:

1. **사용 중 발견된 이슈 확인**
   - 파일: 이 문서의 "블로커 / 이슈" 섹션
   - 할 일: 실사용 중 새로 발견된 문제가 있으면 여기에 기록 후 해결

2. **v0.2 후보에서 우선순위 결정**
   - 파일: 이 문서의 "다음 단계 (v0.2 후보)" 섹션, `memory/future_improvements.md`
   - 할 일: 실사용 경험을 바탕으로 가장 필요한 항목을 선정

### 참고 컨텍스트

- QA 리포트: `docs/qa/` 디렉토리 (Phase 1~4 + UX 리뷰 4라운드 + 최종 검증)
- 빌드/실행: `bash scripts/build-app.sh && open ClaudeCodeMonitor.app`
- 메모리 파일: `~/.claude/projects/-Users-anhyobin-dev-mac-app-for-claude/memory/`
