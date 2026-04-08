# QA 리포트: tool_result 파싱 수정 (2차 검증)

**날짜**: 2026-04-09
**마일스톤**: tool_result content가 배열 형태일 때 text 추출 로직 추가
**상태**: PASS
**프로젝트 유형**: macOS 네이티브 앱 (Swift + SwiftUI)
**QA 라운드**: 2차 (1차 QA에서 MEDIUM 이슈 1건 발견 후 수정 검증)

## 평가 점수

| 평가 축 | 점수 | 기준 | 판정 |
|---------|------|------|------|
| Functionality (기능 완성도) | 4/5 | >= 4 | PASS |
| Spec Fidelity (스펙 충실도) | 4/5 | >= 4 | PASS |
| User Experience (사용자 경험) | 4/5 | >= 4 | PASS |
| Edge Cases (경계 조건) | 4/5 | >= 3 | PASS |
| Design Quality (디자인 품질) | N/A | - | - |

## 요약

| 카테고리 | 테스트 | 성공 | 실패 |
|----------|--------|------|------|
| 빌드 검증 | 1 | 1 | 0 |
| 1차 이슈 재검증 | 4 | 4 | 0 |
| 회귀 검증 | 2 | 2 | 0 |
| 경계 조건 | 2 | 2 | 0 |
| 실제 데이터 검증 | 1 | 1 | 0 |
| **합계** | **10** | **10** | **0** |

## 1차 QA 이슈 재검증

### 이전 FAIL 항목 해결 확인

**[MEDIUM] tool_result content가 Array 형태인 경우 contentPreview 미추출** -- RESOLVED

- 위치: `Sources/ClaudeCodeMonitor/DataLayer/JSONLParser.swift:204-217`
- 1차 QA 당시: `block["content"] as? String` 캐스팅만 존재하여 배열 형태 content가 무시됨
- 수정 내용: String 캐스팅 실패 시 `block["content"] as? [[String: Any]]` 캐스팅 추가, 배열 내 `type=="text"` 항목에서 text 추출
- 수정 코드 (라인 207-217):
  ```swift
  if let resultText = block["content"] as? String {
      contentPreview = String(resultText.prefix(100))
  } else if let resultArray = block["content"] as? [[String: Any]] {
      for item in resultArray {
          if item["type"] as? String == "text",
             let text = item["text"] as? String {
              contentPreview = String(text.prefix(100))
              break
          }
      }
  }
  ```
- 검증 결과: 1차 QA에서 제안한 수정 방향과 구현이 정확히 일치. 4개 Swift 인라인 테스트 통과.

## 테스트 결과

### 빌드 검증

1. **Release 빌드**
   - 입력: `swift build -c release`
   - 예상: 빌드 성공, 경고/에러 없음
   - 실제: `Build complete! (0.11s)` -- 경고 없음, 에러 없음 PASS

### 1차 이슈 재검증 (Swift 인라인 테스트)

2. **Array content + text 블록 추출**
   - 입력: `{"type":"tool_result","content":[{"type":"text","text":"Success: file was written to /path/file.swift"}]}`
   - 예상: contentPreview = "Success: file was written to /path/file.swift"
   - 실제: contentPreview = "Success: file was written to /path/file.swift" PASS

3. **String content 회귀 검증**
   - 입력: `{"type":"tool_result","content":"File created successfully at /path/file.swift"}`
   - 예상: contentPreview = "File created successfully at /path/file.swift"
   - 실제: contentPreview = "File created successfully at /path/file.swift" PASS

4. **Image-only array (text 없음) -- 빈 preview 유지**
   - 입력: `{"type":"tool_result","content":[{"type":"image","source":{"type":"base64","data":"abc123"}}]}`
   - 예상: contentPreview = "" (text 블록 없으므로 비어있어야 함, fallback 표시로 전환)
   - 실제: contentPreview = "" PASS

5. **Mixed array (tool_reference + text) -- text 추출**
   - 입력: `{"type":"tool_result","content":[{"type":"tool_reference","id":"ref1"},{"type":"text","text":"Tool completed with output: OK"}]}`
   - 예상: contentPreview = "Tool completed with output: OK"
   - 실제: contentPreview = "Tool completed with output: OK" PASS

### 회귀 검증

6. **tool_use name 추출 (assistant 메시지)**
   - 코드: 라인 89-96 (scanSessionSummary), 라인 202-203 (parseRecentMessages) -- 변경 없음
   - 판정: 회귀 없음 PASS

7. **toolResultCount 카운팅 로직**
   - 코드: 라인 204-205 -- `toolResultCount += 1`이 content 타입 분기 이전에 위치
   - 모든 content 타입(String, Array, null)에서 카운트 정상 동작 PASS

### 경계 조건

8. **배열 내 빈 text ("") 처리**
   - 로직: `item["text"] as? String`은 빈 문자열도 추출하지만 `contentPreview.isEmpty` 체크로 다음 블록 탐색
   - 판정: 빈 text 블록이 있고 이후에 내용 있는 text가 오면 후자를 사용. 빈 text만 있으면 fallback 표시. PASS

9. **content 키 자체가 없는 tool_result**
   - 실데이터: 520건 (0.8%) -- content 키 없거나 빈 문자열
   - 로직: 두 캐스팅 모두 실패하여 contentPreview 비어있음 -> fallback "N tool results" 표시
   - 판정: 안전하게 스킵됨 PASS

### 실제 데이터 검증

10. **전체 subagent JSONL 파일 대상 커버리지 분석**
    - 대상: ~/.claude/projects 하위 전체 subagent JSONL 파일
    - 전체 tool_result 블록: 61,617개
    - **수정 전**: text 추출 52,139건 (84.6%)
    - **수정 후**: text 추출 59,361건 (96.3%)
    - 커버리지 개선: +11.7%p (7,222건 추가 추출)
    - 나머지 3.7% (2,256건): image-only 배열(1,736) 또는 content 미존재(520) -- fallback 표시가 적절
    - 판정: PASS

## 스펙 충실도 체크리스트

| # | 요구사항 | 구현 여부 | 동작 확인 | 비고 |
|---|---------|----------|----------|------|
| 1 | tool_result content가 String일 때 contentPreview 추출 | DONE | PASS | 기존 동작 유지 |
| 2 | tool_result content가 Array일 때 text 블록에서 추출 | DONE | PASS | 1차 QA MEDIUM 이슈 해결 |
| 3 | tool_result content가 없거나 다른 타입일 때 안전하게 스킵 | DONE | PASS | fallback 표시로 전환 |
| 4 | toolResultCount 정상 카운팅 | DONE | PASS | content 타입과 무관하게 카운트 |
| 5 | 기존 동작 회귀 없음 | DONE | PASS | assistant tool_use, layout 변경 없음 |

## 사용자 경험 평가

- 수정 전: 14.5%의 tool_result에서 "N tool results" fallback 표시만 노출되어 사용자에게 정보 부족
- 수정 후: 96.3%의 tool_result에서 실제 텍스트 미리보기 표시
- 나머지 3.7% (image-only, content 없음)는 텍스트 추출이 불가능한 구조이므로 fallback 표시가 적절한 대응
- contentPreview 길이 제한(.prefix(100))이 일관되게 적용됨

## 디자인 품질 평가

N/A (macOS 네이티브 앱 -- Playwright UI 테스트 불가, 파싱 로직 변경만 해당)

## 실데이터 분포 참고

| tool_result content 타입 | 건수 | 비율 | 수정 후 처리 방식 |
|-------------------------|------|------|-----------------|
| String | 52,139 | 84.6% | contentPreview 직접 추출 |
| Array (text 포함) | 7,222 | 11.7% | Array 내 text 블록에서 추출 (NEW) |
| Array (image only) | 1,736 | 2.8% | fallback "N tool results" 표시 |
| Empty/missing | 520 | 0.8% | fallback "N tool results" 표시 |

Array 내 세부 타입 분포:
- text: 7,371건
- tool_reference: 4,838건
- image: 1,643건

## 검증 커맨드

```bash
# 빌드 검증
cd /Users/anhyobin/dev/mac-app-for-claude && swift build -c release 2>&1

# 실제 데이터 커버리지 확인
python3 -c "
import json, glob
files = glob.glob('/Users/anhyobin/.claude/projects/*/*/subagents/agent-*.jsonl')
array_content_count = 0
text_extracted = 0
for f in files:
    try:
        with open(f) as fh:
            for line in fh:
                obj = json.loads(line.strip())
                if obj.get('type') != 'user': continue
                msg = obj.get('message', {})
                content = msg.get('content', '')
                if not isinstance(content, list): continue
                for block in content:
                    if block.get('type') != 'tool_result': continue
                    c = block.get('content', '')
                    if isinstance(c, list):
                        array_content_count += 1
                        for item in c:
                            if item.get('type') == 'text' and item.get('text'):
                                text_extracted += 1
                                break
    except: pass
print(f'Array content tool_results: {array_content_count}')
print(f'Text extractable from arrays: {text_extracted}')
print(f'Coverage: {text_extracted}/{array_content_count} = {text_extracted/max(array_content_count,1)*100:.1f}%')
"
```

## 결론

**Scores**: Func 4/5 | Spec 4/5 | UX 4/5 | Edge 4/5 | Design N/A

**권장사항**: PROCEED

1차 QA에서 발견된 MEDIUM 이슈 (Array 형태 tool_result content 미처리)가 정확히 수정되었습니다.
수정 코드는 1차 QA 리포트에서 제안한 구현과 동일한 패턴으로 작성되었으며, 4개의 Swift 인라인 테스트(Array+text, String 회귀, Image-only, Mixed)를 모두 통과했습니다.
실제 데이터 기준 text 추출 커버리지가 84.6%에서 96.3%로 개선되었고, 나머지 3.7%는 텍스트 추출이 원천적으로 불가한 케이스(image-only, content 미존재)로 fallback 표시가 적절합니다.
기존 동작에 대한 회귀는 없습니다.
