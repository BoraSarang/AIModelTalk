# CHANGELOG

이 프로젝트는 **v0.1.0** 초기 릴리스이며, 여기서부터 신규 출발합니다. (이전 이력 없음)

## [0.2.0] — 2026-09-03 (Step A — 모델 테스트 심장)

> 범위 확정: Apple Intelligence 포함 / 단계별 커밋 / 우선순위 권장대로.
> 상세 기획: `docs/plans/PLAN_v0.2.0_macos.md`

### 신규 기능 (T-201 · T-202)
- **대화 내 병렬 모델 비교 (T-201)**: 입력창의 비교 버튼으로 여러 모델을 선택하면, 현재 대화 컨텍스트(`effectiveHistory`)를 모든 모델에 동시 발송해 나란히 스트리밍
  - 비교 오버레이 그리드: 래인별 TTFT/총시간/토큰/글자수 표시, 실패·스트리밍 상태 명시
  - "이 답변으로 대화 계속" — 선택한 래인을 세션의 어시스턴트 답변으로 채택
  - 취소로 오버레이 종료, 비교는 임시로 히스토리를 오염시키지 않음
- **비교 채택 변환**: 래인 → 세션 어시스턴트 메시지 변환 순수 함수(`assistantMessage(fromLane:)`)
- **비교 샘플링 온도 (T-202)**: 비교 실행 시 temperature 지정(기본값 = 공급자 기본값), nil이면 요청에서 생략
- **ComparisonService 확장**: 컨텍스트 기반 병렬 실행(`run(context:systemPrompt:temperature:models:)`) + 중단(`stopAll`) + 판정 질문 보정

### 개선
- `ComparisonResult` 래인·메시지 변환 시 실측 토큰 보존

### 추가 기능 — EOL/모델없음 자동 처리 + 비교 UX 개선 (커밋 b584ab8, 697fb75)
- **EOL(410)/모델없음(404) 자동 처리**: 채팅·비교·판정 실행에서 HTTP 410/404 응답 시 해당 모델을 공급자 무관으로 자동 비활성화(`disableUnavailableModel`) + 사용자 문구("모델이 목록에서 자동 제외됨"), 실패 원인 힌트(`failureHint`) 표기. (402 잔액·429 한도 등은 자동 비활성화하지 않음)
- **Gemini 턴 보정**: 마지막 콘텐츠 role이 `model`이면 보조 `user` 턴("계속하세요") 추가 — 400 "Requests ending with a model turn" 예방
- **갱신 리포트 사유 상세**: `ProviderRefreshResult.errorMessage` + 각 공급자(Ollama/Gemini/OpenAI호환/커스텀) 갱신 실패 사유 채움, `summaryText`에 실패 사유 "실패: 공급자(사유)" 표기, `refresh()` 로그에 실패 목록 포함.
- **비교 모델 선택 UX**: 공급자 섹션별 모델 행 클릭 토글(square ⇄ checkmark.square.fill) + 선택 카운터 + hover 툴팁 안정화
- **비교 오버레이 유지**: 완료 후에도 결과 그리드를 사용자가 채택/취소 전까지 유지
- **활성화한 모델만 필터 통일**: CompareModelPickerButton/SplitChatView/ComparisonView/BenchmarkView → `visibleModels(in:)` 공통 사용
- **자동 스크롤**: 고정 높이 Markdown 렌더러에 `__AUTOSCROLL`/`scrollToBottom` 주입

### 추가 기능 — 자동 제외 모델 정리 상태 표시 (커밋 e6ea29c)
- **자동 정리(410/404) 모델을 별도 기록**: `autoDisabledKeys`(UserDefaults `autoDisabledModelKeys`) 영구 저장 — 수동 해제와 구분. `disableUnavailableModel` 시 기록, 사용자가 재활성화(`setEnabled(true)`)하면 기록 해제
- **갱신 로그/설정에 정리 상태 표시**: 목록 갱신 완료 로그와 설정 하단 리포트에 "자동 제외(410/404) 모델 n개 유지" 병기

### 검증
- macOS build_and_run 성공 · 단위 테스트 265건 통과(신규 UnavailableModelTests_V020 6건·ParallelComparisonTests_T201 3건 포함)

## [0.1.0] — 2026-09-03 (초기 릴리스)

### 신규 기능
- **전역 장기 메모리**: 대화에서 사실을 자동 추출해 앱 전역 기억으로 저장하고, 모든 대화의 시스템 프롬프트에 관련도 검색으로 주입 (`MemoryItem` + `MemoryStore`, UserDefaults 주입형)
  - 수동 기억 추가/삭제/핀 토글, 핀 우선·예산 절단
  - 인코그니토 세션은 기억 미회수·미생성
- **보관함 & 휴지통**: `archivedAt`(보관) / `deletedAt`(휴지통) soft delete 상태 체계
  - 세션 컨텍스트 메뉴: 보관/해제 · 휴지통 이동/복원 · 영구 삭제
  - 휴지통 30일 자동 비우기 + 수동 전체 비우기
  - 보관 세션은 검색·메모리에 포함 유지, 휴지통 세션만 제외
  - 사이드바에 보관함·휴지통 접이식 섹션, 보관/삭제 시각 최신순 정렬
- **세션 관리**: 제목 자동 생성 · 저장/복원 · 대화 분기(fork) · 드래그 재배치
- **모델 디렉토리**: 무료 전용 모델 목록 + 공급자별 런타임 갱신
- **공급자**: NVIDIA / OpenRouter / Groq / Gemini / 커스텀 / Ollama — SSE 스트리밍, 키는 Keychain 관리
- **대화창**: 카카오톡 스타일 말풍선 + 네이티브 Markdown 렌더러 · 아티팩트 프리뷰(html/svg/mermaid/react)
- **벤치마크**(⌘⇧B) · 비교 모드(⌘⇧C) · 전역 검색(⌘⇧F) · 웹 검색
- **퀵챗** · 인코그니토 모드 · 글로벌 단축키 · 선택 텍스트 캡처
- **스킬 로더**(4소스 우선순위 병합·출처 배지) · **MCP 도구**(stdio/Streamable HTTP, 도구 루프, 권한 게이트)
- **디버그 패널**: 구조화 로깅 + 에러코드 래핑

### 기술 스택
- 플랫폼: macOS 14+ (Sonoma) · SwiftUI + AppKit · Swift 5.9
- 프로젝트 생성: xcodegen · 영속성: SwiftData + UserDefaults
- 통신: URLSession(SSE) · 핫키: Carbon · 접근성: AX API

### 검증
- macOS 14+ xcodegen 빌드 성공
- 전체 테스트 통과 (262건, 전역 메모리·보관/휴지통·스킬·MCP·벤치마크 등 스위트 포함)