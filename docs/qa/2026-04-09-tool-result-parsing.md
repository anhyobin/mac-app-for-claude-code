# QA 리포트: tool_result 파싱 수정

**날짜**: 2026-04-09
**마일스톤**: AgentDetailView Recent Messages에서 user 메시지의 tool_result 블록 내용 표시 수정
**상태**: ❌ FAIL
**프로젝트 유형**: macOS 네이티브 앱 (Swift + SwiftUI)

## 평가 점수

| 평가 축 | 점수 | 기준 | 판정 |
|---------|------|------|------|
| Functionality (기능 완성도) | 3/5 | >= 4 | ❌ |
| Spec Fidelity (스펙 충실도) | 3/5 | >= 4 | ❌ |
| User Experience (사용자 경험) | 4/5 | >= 4 | ✅ |
| Edge Cases (경계 조건) | 3/5 | >= 3 | ✅ |
| Design Quality (디자인 품질) | N/A | - | - |

## 요약

| 카테고리 | 테스트 | 성공 | 실패 |
|----------|--------|------|------|
| 빌드 검증 | 2 | 2 | 0 |
| 기능 테스트 | 5 | 3 | 2 |
| 회귀 검증 | 4 | 4 | 0 |
| 스펙 충실도 | 3 | 2 | 1 |
| 사용자 경험 | 2 | 2 | 0 |
| **합계** | **16** | **13** | **3** |

## 테스트 결과

### ✅ 성공한 테스트

1. **빌드 검증 (Release)**
   - 입력: `swift build -c release`
   - 예상: 빌드 성공
   - 실제: `Build complete! (0.13s)` -- 경고 없음, 에러 없음

2. **빌드 검증 (Debug)**
   - 입력: `swift build`
   - 예상: 빌드 성공
   - 실제: `Build complete! (2.94s)` -- 컴파일 에러 없음

3. **tool_result content가 String인 경우 contentPreview 추출**
   - 입력: `{"type":"tool_result","content":"File created successfully at: /path/to/file.swift"}`
   - 예상: contentPreview = "File created successfully..."
   - 실제: contentPreview = "File created successfully at: /path/to/file.swift" ✅

4. **toolResultCount 카운팅 정상 동작**
   - 입력: tool_result 블록이 1개 있는 user 메시지
   - 예상: toolResultCount = 1
   - 실제: toolResultCount = 1 ✅ (모든 content 타입에서 정상 카운트)

5. **text 블록이 tool_result보다 앞에 있는 경우 text 우선 표시**
   - 입력: `[{"type":"text","text":"Hello"},{"type":"tool_result","content":"result"}]`
   - 예상: contentPreview = "Hello" (text 우선)
   - 실제: contentPreview = "Hello" ✅

6. **ConversationEntry에 toolResultCount 파라미터 전달**
   - ConversationEntry 생성은 JSONLParser.swift:214 한 곳에서만 발생
   - toolResultCount 파라미터가 정상 전달됨 ✅

7. **AgentDetailView fallback 표시 로직**
   - contentPreview가 비어있고 toolResultCount > 0일 때 "↩ N tool results" 표시
   - 실제 E2E 테스트에서 정상 동작 확인 ✅

8. **assistant 메시지의 tool_use 표시 로직 변경 없음 (회귀)**
   - JSONLParser.swift:91, 202, 256 -- tool_use 처리 로직 정상
   - assistant 메시지에서 tool_use name 추출 및 툴 카운트 로직 변경 없음 ✅

9. **AgentDetailView 기존 레이아웃/스타일 변경 없음 (회귀)**
   - Tools 섹션: FlowLayout + Capsule 스타일 유지
   - Files 섹션: doc.fill 아이콘 + shortPath 유지
   - Recent Messages 섹션: person.fill/cpu 아이콘 + 컬러 유지
   - 전체 VStack(spacing: 8) + padding(.leading, 8) 유지 ✅

10. **실제 JSONL 파일 E2E 파싱**
    - 대상: agent-a3188b4923e9171e4.jsonl (78 user messages, 69 with tool_result)
    - String content 63개 정상 파싱, 최근 10개 메시지 표시 정상 ✅

### ❌ 실패한 테스트

1. **[MEDIUM] tool_result content가 Array(list) 형태인 경우 contentPreview 미추출**
   - 위치: `Sources/ClaudeCodeMonitor/DataLayer/JSONLParser.swift:206`
   - 입력: `{"type":"tool_result","content":[{"type":"text","text":"Success: file was written"}]}`
   - 예상: contentPreview = "Success: file was written"
   - 실제: contentPreview = "" (빈 문자열) -- `block["content"] as? String` 캐스팅 실패로 array 내부의 text를 추출하지 못함
   - 심각도: **MEDIUM**
   - 영향 범위: 전체 2,577개 subagent JSONL 파일 분석 결과:
     - 전체 tool_result 블록: 61,582개
     - String content (처리됨): 52,624개 (85.5%)
     - **Array content (미처리): 8,958개 (14.5%)**
     - Array 중 text 블록 포함 (preview 추출 가능): 7,222개
     - Array 중 image만 포함 (text 추출 불가): 1,736개
   - 대상 파일(agent-a3188b4923e9171e4.jsonl): 69개 tool_result 중 6개가 list 타입 (fallback 표시로 전환)
   - 수정 방향: 206번 줄 이후에 array 형태 content 처리 로직 추가 필요:
     ```swift
     } else if blockType == "tool_result" {
         toolResultCount += 1
         if contentPreview.isEmpty {
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
         }
     }
     ```

2. **[LOW] tool_result content가 빈 문자열인 경우 의미 없는 빈 preview**
   - 입력: `{"type":"tool_result","content":""}`
   - 예상: 빈 문자열이지만 toolResultCount > 0 이므로 fallback 표시
   - 실제: contentPreview = "" + toolResultCount = 1 -> fallback "↩ 1 tool results" 표시 ✅
   - 참고: 이 경우는 fallback이 정상 작동하므로 UI에는 문제 없음. LOW로 분류.

## 스펙 충실도 체크리스트

| # | 요구사항 | 구현 여부 | 동작 확인 | 비고 |
|---|---------|----------|----------|------|
| 1 | user 메시지의 tool_result 블록 내용 표시 | ✅ | ⚠️ | String content만 처리, Array content 미처리 |
| 2 | toolResultCount 필드 추가 | ✅ | ✅ | ConversationEntry에 정상 추가 |
| 3 | contentPreview 비어있을 때 fallback 표시 | ✅ | ✅ | "↩ N tool results" 정상 표시 |
| 4 | 기존 assistant tool_use 표시 회귀 없음 | ✅ | ✅ | 변경 없음 확인 |
| 5 | 기존 레이아웃/스타일 회귀 없음 | ✅ | ✅ | 변경 없음 확인 |

## 사용자 경험 평가

### 긍정적 측면
- fallback 표시 "↩ N tool results"는 사용자에게 tool_result의 존재를 알려주는 적절한 대안
- 기존 assistant 메시지의 도구 태그(blue capsule) 표시와 일관된 디자인 언어
- 메시지 순서와 role 구분(person.fill/cpu 아이콘)이 명확

### 개선 필요
- Array 형태의 tool_result content에서 text를 추출할 수 있음에도 fallback 표시로 전환됨
  - 전체 데이터 기준 14.5%의 tool_result가 내용 미표시
  - 7,222개 블록에서 의미 있는 텍스트를 보여줄 수 있었으나 "↩ tool results"로만 표시

## 디자인 품질 평가

N/A (macOS 네이티브 앱 -- Playwright UI 테스트 불가, API-only 테스트 대상)

## 검증 커맨드

```bash
# 빌드 검증
cd /Users/anhyobin/dev/mac-app-for-claude && swift build -c release 2>&1

# 실제 데이터에서 tool_result content 타입 분포 확인
python3 -c "
import json, os
base = os.path.expanduser('~/.claude/projects')
str_count = list_count = 0
for root, dirs, files in os.walk(base):
    for f in files:
        if f.startswith('agent-') and f.endswith('.jsonl'):
            with open(os.path.join(root, f)) as fh:
                for line in fh:
                    obj = json.loads(line.strip())
                    if obj.get('type') == 'user' and not obj.get('isMeta'):
                        content = obj.get('message',{}).get('content','')
                        if isinstance(content, list):
                            for b in content:
                                if b.get('type') == 'tool_result':
                                    c = b.get('content')
                                    if isinstance(c, str): str_count += 1
                                    elif isinstance(c, list): list_count += 1
print(f'String: {str_count}, List: {list_count}, List%: {list_count/(str_count+list_count)*100:.1f}%')
"

# Swift 단위 테스트 (list content 미처리 재현)
swift -e '
import Foundation
let json = "{\"type\":\"tool_result\",\"content\":[{\"type\":\"text\",\"text\":\"hello\"}]}"
let data = json.data(using: .utf8)!
let block = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
let asString = block["content"] as? String
print("as? String result: \(String(describing: asString))")  // nil
'
```

## 결론

**Scores**: Func 3/5 | Spec 3/5 | UX 4/5 | Edge 3/5 | Design N/A

**권장사항**: ❌ **FIX REQUIRED**

### 수정 필요 항목

- **[MEDIUM] JSONLParser.swift:206 -- Array 형태의 tool_result content 미처리**
  - 위치: `Sources/ClaudeCodeMonitor/DataLayer/JSONLParser.swift:204-209`
  - 입력: tool_result의 content가 `[{"type":"text","text":"..."}]` 배열 형태
  - 예상: 배열 내 text 블록에서 텍스트를 추출하여 contentPreview에 반영
  - 실제: `block["content"] as? String` 캐스팅 실패로 contentPreview가 빈 문자열
  - 영향: 전체 tool_result의 14.5% (8,958/61,582)에서 내용 미표시, 이 중 7,222개는 text 추출 가능
  - 수정 방향: String 캐스팅 실패 시 `[[String: Any]]`로 캐스팅하여 text 블록 탐색

빌드는 정상이고, String 형태의 tool_result content 처리와 fallback UI는 정상 동작합니다. 그러나 실제 데이터에서 14.5%를 차지하는 Array 형태의 content가 처리되지 않아 기능 완성도와 스펙 충실도가 기준(>= 4)에 미달합니다. 사용자는 정상 사용 중 이 문제를 반복적으로 만나게 됩니다.
