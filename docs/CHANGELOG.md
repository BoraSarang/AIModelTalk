# CHANGELOG

이 프로젝트는 **v0.1.0** 초기 릴리스이며, 여기서부터 신규 출발합니다. (이전 이력 없음)

## [0.3.3] — 2026-09-05 (검증 무료 모델 카탈로그)

> 외부 무료 모델 정리 문서 대조 후 검증된 무료 모델만 반영 (기준일 2026-09-05)

### 검증 원천
- Zen: `opencode.ai/docs/zen` — 무료 6종 확정 (Big Pickle·MiMo-V2.5·Ling 3.0 Flash Fin·Nemotron 3 Ultra·Nemotron 3.5 Lightning·Muse Spark 1.3 Contributor)
- OpenRouter: `/api/v1/models` — `:free` 19종 ID·컨텍스트 확정 (외부 문서 표기와 ID까지 일치)
- NIM: 키 없이 검증 불가 → 정적 추가 없음 (NVIDIA refresh에 위임)

### 변경
- **defaultModels**: 사망 OR `:free` 4종 제거 (gemini-2.5-flash-preview·deepseek-v3-0324·llama-4-maverick·qwen3-235b — 목록에서 소멸 확인) + OR 무료 15종(North Mini Code·Laguna S/XS·Nemotron Ultra/Super/Lightning/Nano Omni·MiniMax M3/M2.7·Inkling/Small·Ling Fin·Dots3·GLM 5.2·LFM 2.5) + Zen 3종(Lightning·Ling Fin·Muse Spark 1.3) 추가
- **fallbackPriority**(T-162): Zen Muse Spark → OR North Mini Code → Zen Ultra → NVIDIA gpt-oss-20b → Gemini 3.6 Flash + 테스트 동기 수정
- **codingPreferredIDs**: 검증 무료 코딩 ID 정식 ID로 추가 (기존 유료 유지)
- **supportsVision**: mimo·inkling·nano-omni·minimax-m3 키워드 추가

### 주의
- Muse Spark 1.3 Contributor Free는 Zen 문서상 `/responses` 엔드포인트 — 앱의 chat/completions 직결은 **실기동 확인 필요** (실패 시 설정에서 해제)
- 무료 라인업은 수시 변동 — 다음 갱신 시 0단계(당일 대조) 반복

### T-332 오디오 모드 + 추천 일원화 + 추천 기본 활성화
- **오디오 모드**: `ChatMode.audio` + 세션별 TTS 모델 선택 + `AudioClient`(NIM 호환 `/audio/speech` JSON, mp3) + `sendAudio`(2000자 절단, 플레이스홀더→mp3 첨부) + 말풍선 재생/정지 행(AVAudioPlayer 메모리 재생)
- **NIM 대조**: Magpie(`nvidia/magpie-tts-zeroshot` 실존, 클라우드는 OpenAI 호환 스키마) · Qwen3-Coder ID 확정(`qwen/qwen3-coder-480b-a35b-instruct`, 262144) 후 기본 목록에 추가
- **코딩 추천 순위**: 팝오버 추천 섹션을 문서 순위 고정 (Muse Spark→North→Qwen3-Coder→Big Pickle)
- **추천 기본 활성화**: `defaultEnabledIDs` 7종 — 무오버라이드 시 기본 ON, 저장된 OFF 존중, 나머지 opt-in 유지
- **주의**: Magpie voice 미지정(서버 기본값, 한국어 voice ID 미확인) · Magpie 모델 ID 클라우드 실기동 확인 필요 (404면 자동제외)

### T-333 전체 MCP 공급자 자동/수동 OAuth 병행 (T-328 흡수)
- **모드 선택**: OAuth 템플릿 연결 화면에 [자동|수동] 세그먼트 (기본값=템플릿 권장) — Linear/GitHub도 자동 시도 가능, DCR 전용이던 공급자도 수동 가능
- **커스텀 엔드포인트**: 수동 폼에 Authorize/Token URL 입력 추가 (템플릿값 프리필·편집 가능) + 설정에 영속화 (`customAuthorizationEndpoint`·`customTokenEndpoint`, 구저장 호환)
- **템플릿 확정값**: GitLab·Slack 수동 엔드포인트 당일 대조 후 기입. Notion·Atlassian은 비표준 토큰 교환(JSON/Basic·audience)이라 미기입 — 커스텀 입력 + 후속 과제
- **갱신 경로**: `refreshToken`이 커스텀 토큰 엔드포인트 우선 사용 (수동 연결 갱신 실패 해소)
- **연결 기록**: 수동 연결 시 `authMode=.oauth21Manual`, 자동 시 `.oauth21DCR` 명시 저장

### T-320 코드 블록 Splash 연동
- **Splash 0.16.0 SPM 해결** (이전 xcodegen 실패 해소) + `CodeBlockView`의 Swift 경로를 Splash `AttributedString` 하이라이트로 교체 — 타언어(python/js 등)는 기존 정규식 유지 (Splash 문법이 Swift 전용)
- **AppSplashTheme**: 기존 One-Dark 계열 hex 팔레트 매핑, 평문은 시맨틱 컬러로 다크/라이트 대응

## [0.3.2] — 2026-09-05 (토큰 상태 표시)

> 비용(USD) 추정 제거 — "실제 토큰 상황만" 표시: 채팅 하단 남음 배지·팝오버 + 설정 토큰 상태 탭

### 축1 — 비용 제거
- **ChatMessage.costUSD / SessionCost / AIModel 가격 필드(inputPricePerM·outputPricePerM·isPaid)** 삭제 — 가격=공급자 과금 선불 모델과 불일치하는 추정치라 제거
- **ModelsSettingsView 가격 편집 UI**(AddModel 가격 입력·가격 컬럼) 제거, 카탈로그 하드코딩 가격 인자 제거
- **말풍선 실비용 라벨·CostSettingsView·"비용/토큰" 탭** 삭제 → "토큰 상태" 탭(tuningfork 아이콘)으로 대체

### 축2 — 토큰 배지
- **TokenQuota.swift 신규**: 선택 모델 기준 `ModelTokenSnapshot`(현재 세션 동일 모델 실측 usage 누적 → 없으면 추정 폴백) + 공급자 계정 풀 `ProviderAccountQuota`(Anthropic `x-ratelimit-*` 헤더 실측, nonisolated 캡처→MainActor 갱신)
- **AnthropicClient** 양 응답 지점(도구/일반)에 헤더 캡처 주입 → 계정 남음 표시
- **ChatInputBarView**: tokenMeter → "남음 N 토큰" 배지(ratio>0.9 빨강/0.7 오렌지) + 클릭 팝오버(모델·계정 풀·실측↑↓·사용/남음 게이지·갱신 시각)

### 축3 — 설정 토큰 상태 탭
- **TokenStatusSettingsView**: 사용 기록(실측>0)이 있는 공급자·모델만 테이블 — 모델명/ID·한도·실측↑↓·사용/남음 막대 + 계정 잔량 카드

### 축4 — MCP 설정 UI 정비 (이번 세션)
- **2중 헤더 제거**: `ThemedSettingsCard("원격 MCP 공급자")` 타이틀 제거 → 내부 헤더 HStack(제목 + "N/M 연결됨 · 도구 N개 · 전체 N" 요약 + 상태 확인/공급자 연결) 단독
- **ProviderCard 레이아웃 수정**: `MinimalCard.overlay(VStack.padding)` → `.padding(16).background(MinimalCard)` — 카드 배경이 콘텐츠를 감싸 헤더 겹침/콘텐츠 잘림 해소 (SimpleCard와 패턴 통일)
- **GradientButton 다크 복구**: `ColorHex.isLightColor`(백색 계열 sRGB luminance>0.6) 감지 → 전경색/스피너 tint 반전
- **삭제 컨펌**: 동일 뷰 `.alert` 2개(공급자/서버)는 macOS에서 첫 번째 무시 → `MCPDeletionTarget` enum + 단일 `.alert(item:)`("'X' 공급자/서버 삭제")로 통합
- **빈 상태 축소**: `EmptyStateView.compact`(캐릭터 160→80, 타이틀 20→14, maxWidth 420→260) — MCP 설정에서 compact 적용
- **MCP 공급자 중복 방지**(T-326): 동일 templateID+정규화 URL은 기존 항목 id 재사용·isEnabled 보존
- **수동 OAuth 연결**(T-327): Linear/GitHub 템플릿을 `.oauth21Manual`로 전환 + Client ID/Secret 입력 폼 + 고정 루프백 포트(13000) 리다이렉트 URI 복사 + `MCPOAuthService` 수동 엔드포인트 경로(디스커버리/DCR 생략, client_secret 교환 지원)
  - 배경: Linear/GitHub 등 다수 공급자가 DCR(동적 등록) 미지원 — 실제 자동 연결 가능 공급자는 Vercel/Atlassian/Supabase 3곳뿐 (ASM/OIDC/registration 엔드포인트 네트워크 검증)

### 축5 — 용도 모드 UX 완성 (T-329)
- **모드 세그먼트 동작 복구**: `setMode`가 세션 모드만 바꾸고 `_cachedSession` 무효화를 안 해 Picker가 stale 상태(항상 채팅)로 보이고 이미지 전송 분기가 미동작이던 버그 수정 — 캐시 무효화 + 세션 영속화 추가
- **이미지 모델 선택**: `ChatSession.selectedImageModelID` 추가 + 이미지 전송(`send`)이 `imageModels.first` 고정 대신 세션 선택 모델 사용(gpt-image-1/dall-e-3 메뉴)
- **코딩 모델 선택**: `ChatSession.selectedCodingModelID` + 입력바 메뉴(사전 정의 코딩 추천 세트 ∩ 활성 모델 → "추천/전체" 섹션 분리, 미선택 시 현재 모델 사용)
- **코딩 작업줄**: 워크스페이스 폴더 선택(NSOpenPanel)·변경·해제 버튼 + 미지정 경고("파일 도구 비활성") — `AppSettings.workspaceFolder` 공유
- **코딩 파일 목록 패널**: 입력바 위 접이식 패널(상위 3레벨, 디렉터리 우선 정렬, 숨김 제외) + 파일 컨텍스트 메뉴(경로 복사/채팅 입력창에 경로 삽입) — `WorkspaceFileRow` 재귀 View (opaque 재귀 함수 컴파일 오류 회피)
- **IME 교착 수정**: 코딩 모델 선택 `Menu`(이중 Section)가 한글 입력과 교차해 IMK→TSM 동기 XPC 응답 유실 → 메인 스레드 `HIRunLoopSemaphore` 스핀(CPU 105%, 한글 입력 전면 불가) 유발 확인 — 원인 실험(메뉴 제거 시 정상) 후 **이미지/코딩 모델 선택을 `.popover` 목록으로 교체**(Menu 원천 배제, `ModelSection` 공통 뷰, 추천/전체 섹션 + 선택 체크) — 적용 규칙: 입력바 텍스트 근처에 Menu 금지
- **세그먼트 좌측 정렬**: `frame(width:)`이 내용을 그 폭 안에서 **중앙 정렬**시키는 특성 때문에 채팅/이미지/코딩 세그먼트가 (260−165)/2≈47pt 오른쪽으로 밀림 — `HStack+Spacer` 래퍼 + `.frame(width: 260, alignment: .leading)`으로 세그먼트를 주 버튼줄(X=204)과 동일 열로 고정(`maxWidth:.infinity` 단독은 Spacer로 이미 가득 차 무효) — AX read-only 좌표 측정으로 X=204 일치 검증

### 검증
- smoke/유닛: `ProviderAndModelSortTestsV31` 통과, xcodebuild 빌드 성공
- AX 검증: 배지 "남음 115.3K 토큰" 표시 + 팝오버 창 생성, 설정 탭 모델 테이블(GPT-OSS-20B 실측 51.3k 사용/79.8k 남음) 확인, 추정값(Nemotron) 행 제외 확인
- MCP UI: 2중 헤더 제거·카드 겹침 해소 AX 확인, 삭제 컨펌(단일 alert)·compact 빈 상태·수동 OAuth 폼 구현 후 사용자 실기동 확인 대기
- 축5(T-329): 빌드 성공 + `~/Applications` 설치·실행 완료 — 모드 선택/모델·폴더 UI·파일 패널 실기동 확인 대기 (사용자 "컴퓨터 제어 하지마" 지침으로 AX 자동화 미수행)
- IME 교착: `sample` 스택으로 원인 특정(메인 스레드 `HIRunLoopSemaphore wait` 1933/1933 샘플, 입력기 KIM_Extension idle), 원인 실험(코딩 모델 Menu 제거 시 한글 입력 정상, 채팅/이미지는 정상) — 팝오버 교체판 빌드·설치 완료, 사용자 실기동 대기(AX 자동화 금지 지침, 사용자가 직접 확인)

## [0.3.1] — 2026-09-05 (축4 용도 모드 분리 + 이미지 생성) · `3d539a0`

> AI 채팅 기능 전면 실현 마지막 축 — 채팅/이미지/코딩 용도 모드 분리와 DALL-E·이미지 생성 파이프라인 추가

### 축4a — 용도 모드 분리
- **ChatMode enum** (chat/image/coding + label·icon) + `ChatSession.mode` (SwiftData 컬럼)
- **ChatInputBarView 모드 세그먼트**: 입력바 상단 채팅/이미지/코딩 Picker + 이미지·코딩 안내 문구
- **`setMode(_:for:)`** — 세션 모드 변경 + `[FEATURE] 세션 모드 변경` 로그

### 축4b — 이미지 생성
- **ImageClient.swift 신규**: OpenAI 호환 `/images/generations` (apiKey/baseURL는 Provider 설정 따름, 커스텀은 customBaseURL)
- **ModelCatalog.imageModels** = [gpt-image-1, dall-e-3] (isFree=false)
- **`sendImage(_:to:model:size:)`** — "이미지 생성 중…" 스트리밍 → 생성 이미지 assistant 메시지 attachment 부착
- **BubbleViews**: 어시스턴트 말풍선에 생성 이미지 표시 + NSSavePanel 저장 버튼

### 버그 수정
- **기동 크래시 수정**: ThemeManager 가 시작 초기화 단계에서 `NSApp`(IUO) nil 접근 → `NSApp?.effectiveAppearance.isDarkMode ?? false` 옵셔널 안전화. 미수정 시 앱 최초 실행 크래시(SIGTRAP)로 창이 뜨지 않았음.

---

## [0.3.0] — 2026-09-05 (축3 워크스페이스 파일 도구) · `3b601f8`

> 모델이 로컬 폴더(워크스페이스) 안에서 파일을 읽고 쓰는 내장 도구 추가

- **AppSettings.workspaceFolder**: UserDefaults 저장(단일 폴더), GeneralSettingsView에 NSOpenPanel 폴더 선택 UI(변경/해제)
- **FileSystemTools.swift 신규**: `@MainActor` — list_dir/read_file/write_file/edit_file + 경로 샌드박스 `resolve()` + `promptOverview()` 트리 요약
- **ToolLoopService**: 파일 도구는 미지정 시 `builtinToolNames`에서 제외(비활성), 지정 시 switch 분기 + `toolRecord`
- **ChatViewModel.builtinToolDefinitions**: 파일 도구 JSON 스키마 추가, `buildSystemPrompt()`에 워크스페이스 개요 주입

---

## [0.2.7] — 2026-09-05 (축2 크레딧·비용 추적) · `e4d532f`

> 모델 호출 비용을 추적하고 표시 — 순수 비용(충전/잔액 없음)

- **AIModel.inputPricePerM/outputPricePerM** + `isPaid` 계산 프로퍼티
- **ModelCatalog 모델 가격**: GPT-4o mini $0.15/$0.60, GPT-4o $2.50/$10.00, Haiku 4.5 $1.00/$5.00, Sonnet 4.5 $3.00/$15.00, DeepSeek V4 Flash $0.20/$0.60, V4 Pro $0.50/$1.50, Chat $0.27/$1.10, Reasoner $0.55/$2.19
- **ChatMessage.costUSD(@MainActor)** + **SessionCost** (누적/계산/유료 메시지 수/formatUSD)
- **BubbleViews**: $0.00 하드코딩 제거 → 실제 비용 표시
- **AddModelSheet**: 입력/출력 가격 입력 + 저장, ModelRow 가격 배지
- **CostSettingsView 신규** + SettingsTab `.cost`(비용/토큰, dollarsign.circle): 누적 비용·현재 세션·유료 메시지 수·월 예산 상한·모델 가격 테이블

---

## [0.2.6] — 2026-09-05 (축1 테마 시스템 전면 적용) · `711d021`

> 테마 인프라(0.2.5)를 채팅·설정·도구 뷰 전면에 적용

- **앱 루트 테마 주입**: `themeEnvironment(_:)` View 확장 — 모든 Scene(메인/벤치마크/브레인스토밍/비교/스플릿/평가/디버그/설정)에 `@Environment(\.theme)`
- **축1a**: GeneralSettingsView에 모드(시스템/라이트/다크)·액센트(시스템 따름 6색)·미리보기 카드, `syncAppearanceMode` 브리지
- **축1b**: 채팅(BubbleViews·InputBar·캔버스)·설정(Providers/Models/MCP/Skills/Memory/Hotkey/Cost)·도구(CompareOverlay, GlobalSearch 등) 전면 테마 적용
- **DS.\* 전면 제거 0건** (DesignSystem.swift의 DS만 `dsBadge` 호환으로 유지)
- 25 files, +459/−221

---

## [0.2.5] — 2026-09-05 (Osaurus 스타일 테마 인프라 & 컴포넌트 라이브러리)

> AIModelTalk에 Osaurus급 네이티브 macOS 디자인 시스템 적용 — 테마 인프라 구축 + 공통 컴포넌트 라이브러리 + 뷰 마이그레이션

### 테마 인프라 (Phase 1)
- **ThemeProtocol**: 50+ 시맨틱 토큰 (색상/글라스/그림자/타이포그래피/애니메이션/코너/말풍선)
- **LightTheme/DarkTheme**: WCAG AA 준수 대비도 (라이트 17:1, 다크 17:1)
- **ThemeBox**: `@dynamicMemberLookup` 래퍼 — SwiftUI `@Environment(\.theme)` 프로토콜 직접 지원
- **ThemeManager**: `@Observable` 싱글톤, 시스템 외형/액센트 추적 + `chatTheme` 세션별 오버라이드
- **ThemeConfigurationStore**: UserDefaults 기반 테마 설정 저장
- **DesignSystem 호환 레이어**: 기존 `DS.` 코드 무수정 유지

### 공통 컴포넌트 22개 (Phase 2)
- **카드**: MinimalCard, SimpleCard, ProviderCard(그리드), ProviderRowCard(리스트)
- **버튼**: GradientButton (Primary/Secondary/Destructive + 로딩)
- **시트/다이얼로그**: FittedSheetFrame, ThemedAlertDialog
- **배경**: ThemedBackgroundLayer, GlassBackground, GlassListRow
- **검색/탭**: SearchField, AnimatedTabSelector
- **섹션/뱃지**: SectionHeader, AuthModeBadge, CategoryBadge, StatusBadge
- **아바타/배지**: AvatarView, AgentBadge, InlineModelBadge
- **코드/스트리밍**: CodeBlockView, InlineCodeView, StreamingDots
- **입력**: FloatingInputCard, ChatInputCard, QuickChatInputCard
- **빈 상태/토스트**: EmptyStateView, SettingsEmptyState, ToastManager, ToastView, ToastContainer
- **캐릭터**: CharacterIllustrations (SF Symbol 폴백)

### 뷰 마이그레이션 (Phase 3)
- **SettingsView**: `.formStyle(.grouped)` + `AnimatedTabSelector` + `minHeight: 520` + theme environment
- **MCPSettingsView**: ProviderCard 2열 그리드 + 헬스 스냅샷 카드 (기존 목록 → 카드형)
- **MCPProviderConnectView**: 테마 컴포넌트 적용 + 단계 표시기(3점) + GradientButton
- **ChatSession.themeID**: `String?` 세션별 테마 필드 + SwiftData 엔티티 컬럼 + saveSession 동기화
- **CharacterIllustrations**: SF Symbol 폴백 (Assets 미로드 시 `face.smiling` 등 사용)

### 기술 결정
- **ThemeBox 사용 이유**: SwiftUI `@Environment(\.theme)`이 프로토콜 타입 직접 미지원 → `@dynamicMemberLookup` 래퍼로 속성 forwarding
- **Splash SPM 제외**: xcodegen 패키지 의존성 추가 실패 → regex 기반 `CodeBlockView`로 대체 (T-320 백לוג 유지)
- **캐릭터 에셋**: AI 이미지 생성 플레이스홀더 → SF Symbol 폴백 (추후 PDF 벡터 교체 가능)

---

## [0.2.3] — 2026-09-04 (병렬 비교 UX 개선 — 선택·마크다운·창 크기) · `690365d`

> 비교 팝오버 선택/갱신 문제와 결과 뷰어(Diff·합성·프롬프트)의 마크다운 렌더링을 개선.

### 비교 팝오버 선택 UX
- **행 체크 즉시 갱신 수정**: 팝오버 내용물을 별도 `CompareSelectorView`로 분리 — macOS 팝오버에서 호스트 뷰의 `@ObservedObject` 구독이 끊겨 행 선택 아이콘이 열어둔 채 안 바뀌던 문제 해결 (`selectedCompareModelIDs` 변경 = 행 아이콘·개수 즉시 반영). 기존 `selectionTick` 강제 재평가 hack 제거
- **선택 시각 강화**: 선택 행 `accent` 배경 하이라이트 + `checkmark.circle.fill`, 미선택 빈 원, "선택됨" 텍스트
- **현재 채팅 모델 비교 제외**: 해당 행 비활성 + "현재 채팅" 표시 + 툴팁, `toggle()` 가드
- **2개 이상 선택 필수**: 하단 개수(2개 미만 주황 경고) + "비교 실행" 버튼 disabled + `startCompare()` 가드
- **모델 파라미터 정렬**: temperature/topP/maxTokens 라벨(좌) : 설정(우) 정렬
- **비교 창 표시 시 이전 선택 초기화**

### 결과 뷰어 마크다운 렌더링
- **시스템 프롬프트**("무엇을 보냈나") → `MarkdownRenderer`(fixedHeight 140)
- **합성 답변** → `MarkdownRenderer`(fixedHeight 200)
- **Diff 패널 재작성**: 라인 단위 diff → **두 래인 답변을 마크다운으로 좌우 나란히 비교**, 창 크기 400 → **900×520** 확대. 미사용 `DiffRow` 제거

## [0.2.2] — 2026-09-03 (성능 — 모델 팝업·설정 멈춤 근본 해결) · `d363630`

> 모델 771+개로 피커/설정이 수 초 멈추던 문제의 근본 원인 세 가지를 해결.

### 성능
- **init O(N²) 제거**: `ModelCatalog.init`에서 `loadCustomModels()`를 `isBatchUpdating` 배치로 묶어, 커스텀 모델 수백 개를 개별 `append`할 때마다 `rebuildIndexes()`(UserDefaults JSON + 전체 모델 순회) 800회가 아닌 **최종 1회만** 실행 → 앱 시작 메인 스레드 블로킹 해소
- **활성 인덱스 캐시**: `enabledByEntryID`/`enabledLegacyCustomModels` 추가. `visibleModels(in:)/visibleModels(for:)`가 조회 시점에 전체를 `.filter { isEnabled }`로 순회하지 않고 **상수 시간에 활성만 반환** → 380개 팝업 open 시 800개 순회 제거
- **토글 1초 딜레이 해소**:
  - `setEnabled` → `rebuildEnabledIndexes(for:)` 증분 갱신(토글 모델이 속한 엔트리만)
  - `ModelsSettingsView`가 토글(`enabledOverrides`) 변화를 관찰하지 않게 분리 — 각 `ModelRow`(독립 `@ObservedObject catalog`)가 자기 모델만 재평가
- **`totalModelCount(in:)` O(1)** 추가 — 공급자 Picker "활성 N/전체N" 카운트가 전체 배열 조립 대신 인덱스 크기 조회
- **팝업 경량화 유지**: `privateEntries` 캐시 + 활성 모델만 표시
- 유닛 테스트 실행 시간 40s → 18s 단축

## [0.2.1] — 2026-09-03 (기본 모델 개념 제거 — 모든 모델 기본 해제) · `47324c1`

> 리모트 모델 800+개가 기본 `enabled`로 노출되어 피커가 멈추던 원인. 모든 모델을 기본 해제로 전환.

### 변경
- `isEnabled` 기본값 `true` → **`false` 전환** — 미등록(신규/원격) 모델은 기본 숨김
- **Apple Intelligence(온디바이스)만 기본 ON** 예외 유지
- 설정에서 사용자 요청 시 켠 모델만 팝업·피커에 노출
- 테스트: 기본 해제 반영(`testNewModelDefaultsToDisabled`), `testDefaultOverridePolicy` 추가

## [0.2.0] — 2026-09-03 (Step A·B — 모델 테스트 심장 + 에이전트 경험)

> 범위 확정: Apple Intelligence 포함 / 단계별 커밋 / 우선순위 권장대로.
> 상세 기획: `docs/plans/PLAN_v0.2.0_macos.md`

### 신규 기능 (Step A — T-201 · T-202 · T-203 · T-206 · T-209)
- **대화 내 병렬 모델 비교 (T-201)**: 입력창의 비교 버튼으로 여러 모델을 선택하면, 현재 대화 컨텍스트(`effectiveHistory`)를 모든 모델에 동시 발송해 나란히 스트리밍
  - 비교 오버레이 그리드: 래인별 TTFT/총시간/토큰/글자수 표시, 실패·스트리밍 상태 명시
  - "이 답변으로 대화 계속" — 선택한 래인을 세션의 어시스턴트 답변으로 채택
  - 취소로 오버레이 종료, 비교는 임시로 히스토리를 오염시키지 않음
- **비교 채택 변환**: 래인 → 세션 어시스턴트 메시지 변환 순수 함수(`assistantMessage(fromLane:)`)
- **비교 샘플링 온도 (T-202)**: 비교 실행 시 temperature 지정(기본값 = 공급자 기본값), nil이면 요청에서 생략
- **ComparisonService 확장**: 컨텍스트 기반 병렬 실행(`run(context:systemPrompt:temperature:models:)`) + 중단(`stopAll`) + 판정 질문 보정
- **평가(Eval) 그리드 (T-203)**: 프롬프트×모델 매트릭스 그리드에서 한 번에 평가
  - 5개 셀 병렬 실행, 셀별 TTFT/tok/s/글자수·오류 상태 표시
  - 1~10 점수 지정(회귀 표시: 이전 vs 최신), 모델·프롬프트 필터/정렬(TTFT/tok/s/점수)
  - CSV·Markdown 내보내기(미리보기·복사·파일 저장), ⌘⇧E/메뉴바 진입
- **비교 자동 판정·합성·Diff (T-206)**:
  - 판정 모델 공급자 우선 선택(자동=NVIDIA, 사용자 지정 공급자), API 키 있으면 해당 공급자 우선
  - 합성(synthesis): 판정 모델이 여러 후보를 병합한 최선 답변을 자동 생성해 표시
  - 텍스트 Diff: 두 래인 텍스트를 라인 단위로 비교(공통/추가/제거 색상 구분)

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

### 추가 기능 — 오류 안내 메시지 상태코드별 명확화 (커밋 a3e8173)
- `AppError.errorDescription`을 상태코드별로 분화해 "서버 오류" 같은 모호한 표현 제거:
  400 요청형식 / 401·403 인증 / 402 잔액부족 / 404 모델없음 / 410 EOL / 429 한도 / 5xx 공급자서버 각각 사용자 언어로 안내
- `ComparisonService.failureHint` 제거 → 원인이 `errorDescription`에 통합되어 비교·채팅 래인에서 중복 이어붙임("X — Y") 정리
- `error_message_ko.json` E-MAC-API-1001 문구 동기화

### 추가 기능 — topP/maxTokens 파라미터 인프라 (T-202, 다음 커밋)
- `ChatClient.stream(messages:systemPrompt:temperature:topP:maxTokens:onUsage:)` 확장 — 네이티브 오버라이드 + 기본 폴백(non-breaking)
- 공급자별 파라미터 매핑 (nil이면 요청에서 생략):
  - **OpenAI 호환**: `RequestBody`에 `top_p`/`max_tokens` 추가, `encodeRequestBody` 확장
  - **Gemini**: `GenerationConfig`에 `topP`/`maxOutputTokens`, `temperature`만 있을 때와 구분해 config 생성
  - **Anthropic**: `top_p` 추가, `max_tokens`는 네이티브 필수값(8192)에서 사용자 지정 시 대체
  - **Ollama**: `options.temperature/top_p/num_predict` — temperature 미지원이던 것을 T-202에서 온도까지 최초 지원
- `ToolCalling.streamWithTools(...topP:maxTokens:)` 오버라이드 — 도구 없을 때 텍스트 스트림에 파라미터 전달(도구 포함 경로는 후속)
- 실제 사용처(비교·채팅 편집 UI / 성능 메트릭 / "무엇을 보냈는지" 패널)는 후속 커밋에서 이 인프라를 연결

### 추가 기능 — 비교 파라미터 편집 UI·성능 메트릭·보낸 요청 패널 (T-202, 커밋 fad17a7)
- **`ModelParams` 공유 구조**: `temperature/topP/maxTokens` (모두 nil = 공급자 기본값), `hasAny` 판단
- **비교 파라미터 전달**: `ComparisonService`를 단일 `temperature` → `ModelParams` 기반으로 승격, `run(context:systemPrompt:params:models:)` 오버로드 추가(이전 온도 시그니처 유지·비파괴) — `streamOne`이 `stream(...temperature:topP:maxTokens:)` 호출
- **편집 UI**: `CompareModelPickerButton`에 temperature/topP/maxTokens 3단 편집 피커(각각 "기본값" 포함)
- **성능 메트릭 확장**: 래인 헤더에 `tok/s`(실측 완료 토큰 ÷ 총 응답 시간) 추가
- **"무엇을 보냈나" 패널**(`CompareOverlayView` 헤더 버튼): 파라미터 요약 · 시스템 프롬프트(400자) · 래인별 실측 토큰/시간 투명 표시
- 채팅 단일 실행(`SendContext`)은 기존 온도 nil 기본값 유지 — 세션별 파라미터 저장은 후속(비교 래인별 우선)

### 신규 기능 (Step B — 에이전트 경험 · 내장 도구 · 미드스위치 · 메모리/템플릿)
- **Apple Intelligence 노출 (T-209)**: 시스템 모델(iCloud 날씨·Emoji 등)이 가능할 때(`appleAvailable`) 비교·Eval 가용 목록에 Apple 공급자 추가 — 순수 헬퍼로 단위 테스트(ChatViewModel.assemblePrompt 계열)
- **내장 에이전트 도구 (T-204)**: web_search / fetch_url / calculator
  - `WebSearchService`: `web_search`(draw 제공) 문맥 통합, `fetchURL`(SSRF 가드 `isSafeFetchURL` — 사설·루프백·링크로컬 차단, HTML 정제 4000자 캡), `evaluateCalculator`(화이트리스트 + 순수 재귀 하강 파서 `CalcParser`)
  - `ToolLoopService.execute` 내장 도구 분기 + `builtinToolNames`, MCP 연결 실패 폴백
  - `ChatViewModel.builtinToolDefinitions()` — 3개 내장 도구 JSON 스키마를 도구 루프에 공급
- **에이전트 모드·YOLO (T-204)**: `agentMode`(내장 도구 활성), `yoloMode`(권한 자동 승인) 토글 — 일반 설정 UI, 도구 루프 진입 조건 `mcpToolsEnabled || agentMode`
- **웹 검색 강화 (T-205)**: `parse_link` 상위 3개 URL 본문 추출(`enrichWithBodies`), 결과 포맷에 본문(〔본문〕)·인용 번호([n]) 포함
- **모델 미드스위치·포크 재실행 (T-207)**: 스트리밍 중 모델 변경 시 정지 후 미완 어시스턴트 제거 → 동일 컨텍스트로 새 모델 즉시 재전송(`rerunAfterModelSwitch`), `sendMessage`에 `reuseLastUser`(중복 append 방지), 어시스턴트 우클릭 "이 지점에서 재실행 (현재 모델)"(`forkSessionAndRerun`)
- **메모리 관리 화면 (T-208)**: 설정에 `메모리` 탭 — 목록(핀·최신순)·검색·핀 토글·듀레이션(영구/임시)·삭제·수동 추가(`MemorySettingsView`, `setMemoryDurability`)
- **프롬프트 템플릿 (T-208)**: `PromptTemplate`/`PromptTemplateStore`(UserDefaults), 입력창 ⌘⇧T 팝오버로 삽입·저장·삭제, `{변수}` placeholder 변수 입력 후 치환(`applyTemplate`)
- **토큰 예산 게이지 (T-208)**: 입력창 토큰 미터에 비율 막대 게이지 + 한도 초과 경고 시각화

### 검증
- 단위 테스트 **327건 전부 통과**(T-204~T-208 신규 9건: BuiltinToolTests/AppleIntelligenceTests/PromptTemplateTests 포함) · 빌드 성공 · `./build_and_run.sh debug macos` 설치/실행 확인
- 전체 테스트는 **병렬 실행 불안정**(Ollama 등 네트워크 스위트 경합) → `-parallel-testing-enabled NO`로 실행 안정화 — 이후 게이트에 반영
- **에러코드 충돌 정리**: T-204 `fetchBlocked`가 `E-MAC-NET-1005`(429용)를, `calcInvalid`가 `E-MAC-VALID-1003`(URL 형식용)을 재사용하던 중복을 분리 — 각각 `E-MAC-NET-1007`/`E-MAC-VALID-1005`로 재배정 + `E-MAC-NET-1006` 문구 추가(JSON 동기화).

### 검증
- 단위 테스트 **286건 전부 통과**(신규 ModelParameterTests_T202 8건 — ModelParams.hasAny/Equatable·tok/s 2건 추가) · 빌드 성공
- UnavailableModelTests_V020 수정: `@MainActor` 격리 추가 + `summaryTextSuccessOnly`를 실제 구현("변경 없음")과 정합 + 빈키 사유 테스트 1건 추가

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