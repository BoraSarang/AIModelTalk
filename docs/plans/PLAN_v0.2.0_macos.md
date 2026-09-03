# PLAN v0.2.0 — "모델 테스트 + 일반 에이전트" (macOS)

> 제작자: BoRaSaRang · 2026-09-03

## 0. 목표 & 포지셔닝

> **"무료·로컬 모델을 네이티브하고 투명하게 나란히 테스트하고, 필요할 땐 웹검색·도구로 일반 에이전트처럼."**

경쟁 분석에서 "**네이티브 + 병렬비교 + 자동판정 + 평가그리드 + 전역메모리 + 무료 모델 디렉토리 + 내장 도구**"의 조합은 어디에도 없음이 확인됨. 여기가 AIModelTalk의 고유 자리.

### 확정 스코프 (사용자 결정)
1. **Apple Intelligence 포함** — 성능이 떨어져도 비교 래인·평가 그리드에 추가 (T-209).
2. **단계별 커밋** — 비교 → 에이전트 → 경험 3단계로, 각 Step은 독립 커밋.
3. **우선순위는 권장대로** — P0(비교) → P1(에이전트·검색) → P2(경험).

### 현재 0.1.0에서 이미 존재하는 자산 (조립·확장 성격)
- `ComparisonService`: `ComparisonResult`(TTFT/총시간/토큰), `JudgeScore`(루브릭 0~10), `parseVerdict`, `rankedEntries`, `streamOne`(withTaskGroup 병렬).
- `StreamManager`: 세션별 병렬 스트리밍(`start/stop/stopAll/isStreaming`).
- `BenchmarkService`: 단일 프롬프트 TTFT/총시간.
- `WebSearchService`: **Tavily 단일**, 시스템 프롬프트 주입, 페이지 읽기 없음.
- `ToolLoopService`: **MCP 도구만**, 내장 도구 없음.
- `ChatViewModel.sendMessage`(1053): 스트리밍 진입점, `effectiveHistory`(1044), `toolDefinitions`(365).
- 클라이언트 4종 모두 `stream(...,temperature:)` 지원 (현재 호출부는 항상 `nil`).
- `AppSettings`: `tavilyAPIKey`/`webSearchEnabled`/`mcpToolsEnabled`/`showJudgeSummary`.
- **Apple Intelligence 지원 존재**: `AppleIntelligenceSupport.modelAvailable`, `AuxModelTestsV23`.

## 1. 작업 패키지 (T-ID)

### Step 1 — 모델 테스트 심장 (`feat(macos): 병렬 비교·파라미터·평가 그리드`) — 커밋 A

**T-201 · 대화 내 병렬 멀티모델 비교 (P0-A)**
- 대화 세션 내에서 여러 모델 선택 → 한 프롬프트를 N개 모델에 병렬 발송, 나란히 스트리밍.
- **UI 2종**: 뷰A(같은 말풍선 UI 좌우 분할 2~4열) + 뷰B(전용 비교 그리드 — 기존 `ComparisonView` 진화).
- 대화 컨텍스트 `effectiveHistory`를 각 래인에 동일 적용 (통일 컨텍스트).
- 각 래인을 별도 `ConversationTurn` 분기로 저장 + "승자로 계속 대화" 버튼.

**T-202 · 모델 파라미터 투명·편집 + 성능 메트릭 (P0-B)**
- 세션/래인별 `temperature/topP/maxTokens` 편집 UI.
- `stream(...,temperature:,topP:,maxTokens:)` 확장 — 클라이언트 4종 파라미터 맵핑.
- 래인별 TTFT/총시간/토큰/tok-per-sec/비용(예측) 상시 표시.
- "무엇을 보냈는지" 패널 — 시스템프롬프트/파라미터/사용 토큰 투명 표시.

**T-203 · 평가(Eval) 그리드 (P0-C)**
- 프롬프트×모델 매트릭스를 병렬로(5-at-a-time) 셀별 1~10점 + TTFT + tok/s.
- 회귀 추적(이전 실행 대비), 결과 정렬·필터, CSV/Markdown 내보내기.
- `BenchmarkService` 확장 — 사용자 지정 프롬프트 리스트.

**T-206 · 비교 자동 판정·합성·Diff (P0 보강)**
- 기존 `runJudge`(루브릭 0~10, 승자, 요약) 유지 + **합성(synthesis)** 한답변 추출(판정 모델이 병합) + **Diff 뷰**.
- 판정 모델 공급자 선택 가능(NVIDIA 우선 유지).

**T-209 · Apple Intelligence 추가 (확정)**
- `AppleIntelligenceSupport`를 비교 래인·Eval에 추가 (성능 미달 허용).

### Step 2 — 일반 AI 에이전트 (`feat(macos): 내장 도구·웹검색 페이지 읽기·에이전트 모드`) — 커밋 B

**T-204 · 내장 에이전트 도구 (P1-A)**
- `ToolLoopService`에 내장 도구 `web_search`(Tavily 재활용), `fetch_url`(parse_link — 페이지→Markdown, SSRF 가드·크기 캡), `calculator`.
- 도구 승인 게이트 강화: 읽기 전용 자동, 쓰기/실행 인챗 승인 카드(Deny/Once/Session) + YOLO 모드 + 작업 폴더 바인딩.
- 챗/에이전트(워크) 모드 전환.

**T-205 · 웹 검색 강화 (P1-B)**
- **페이지 내용 읽기(parse_link)** 포함 한 번에 (Tavily search + 별도 fetch로 본문 추출 + 인용 번호).
- 공급자 선택 프레임(Bing/Tavily/직접) — 최소 백엔드 확장 + 인용 렌더링.

### Step 3 — 경험 완성도 (`feat(macos): 미드스위치·포크 재실행·메모리 관리·템플릿·예산 게이지`) — 커밋 C

**T-207 · 모델 미드스위치·포크 재실행 (P2-A)**
- `@모델명`/모델 피커 미드스위치(컨텍스트 유지).
- 포크 → 다른 모델/파라미터 재실행 비교 (`forkSession` 확장).

**T-208 · 메모리 관리 화면 · 프롬프트 템플릿 · 토큰 예산 게이지 (P2-B)**
- 전역 메모리 관리 화면(목록·검색·핀·듀레이션·삭제).
- 프롬프트 템플릿(변수 입력·단축키).
- 컨텍스트/토큰 예산 게이지 + 정리 표시.

## 2. 핵심 아키텍처 영향 지점

| 파일 | 변경 |
|---|---|
| `ChatViewModel.sendMessage` | N-래인 병렬·내장도구·워크모드 분기 |
| `ComparisonService` | 저장/재실행/Diff/합성, 파라미터 퍼-래인 |
| `SendContext` | temperature 상시 전달 + topP/maxTokens 추가 |
| `OpenAICompatibleClient` 등 4종 `stream` | topP/maxTokens 맵핑 |
| `ToolLoopService` | 내장 도구 정의 + 승인/YOLO/작업폴더 |
| `WebSearchService` | parse_link + 공급자 선택 |
| `BenchmarkService` | 사용자 지정 프롬프트·평가 그리드·회귀 |
| `AppSettings` | 파라미터·워크모드·판정/합성·공급자 토글 |
| `Views/ComparisonView·ChatView·NewView(Eval)` | 비교 그리드·대화 래인·평가 UI |

## 3. 커밋 단계 (단계별 커밋)

| Step | 커밋 | T-ID | 성격 |
|---|---|---|---|
| A | `feat(macos): 병렬 비교·파라미터·평가 그리드` | T-201,202(온도),203,206,209 | 모델 테스트 심장 |
| B | `feat(macos): 내장 도구·웹검색 페이지 읽기·에이전트 모드` | T-204,205 | 일반 에이전트 |
| C | `feat(macos): 미드스위치·포크 재실행·메모리·템플릿·예산게이지` | T-207,208 | 경험 완성도 |

각 Step: 문서 → 구현 → `./build_and_run.sh build macos` → smoke/unit → 커밋.

### 커밋 A 실제 진행 (2026-09-03) — 범위 조정
- **포함**: T-201 대화 내 병렬 비교(뷰A) · T-202 캐릭터별 **온도 전달**
- **보류(다음 커밋)**: T-202의 `topP/maxTokens`(ChatClient 프로토콜 시그니처 변경 — 파괴적으로 리스크 커서 분리) · T-203 Eval · T-206 합성/Diff · T-209 AppleInt
- 검증: build_and_run 성공 · 265건 테스트 통과

## 4. 검증

- 실측: `xcodebuild` (swift build 금지).
- 테스트: 기존 스위트 유지 + 신규(병렬비교·Eval·판정합성·parse_link·도구승인·메모리관리·템플릿).
- 성능 예산: 사용자 사용 중 병렬 ≤2 원칙, ToolLoop 타임아웃 30s 단위 / E2E 60s 단계.
- Release 커밋 이전 `build_and_run.sh build macos` 통과.

## 5. 문서 갱신
- `docs/CHANGELOG.md` — v0.2.0 단일 엔트리(platform 태그 + 에러코드).
- `.agent/session-2026-09-03-macos.md` — 8줄 요약.
- `error_message_ko.json` — 신규 에러코드 매핑.