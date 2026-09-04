# PLAN v0.2.6 ~ v0.3.0 — AI 채팅 기능 전면 실현 (테마·크레딧·파일·이미지)

> **작성일**: 2026-09-05  
> **플랫폼**: macOS (SwiftUI, macOS 15.5+ / 26 Liquid Glass)  
> **목표**: Osaurus급 AI 채팅 앱의 온전한 기능 세트 실현 — 4개 축(축1 테마 적용 / 축2 모델 크레딧·비용 / 축3 로컬 폴더·파일 접근 / 축4 용도 모드·이미지 생성)

---

## 0. 배경 및 사용자 요구

기존 v0.2.5에서 테마 **인프라만** 구축하고 실제 화면 적용은 미미해 "바뀐 게 없다"는 지적 발생. 사용자는 진짜 원하는 것이 **오픈소스 AI 채팅 앱의 기능 전반**임을 밝힘:
- 토큰 표시 방식
- AI 인터넷 검색 (이미 구현 — Tavily + 도구 루프)
- 로컬 프로젝트 폴더 지정 / 파일 읽기·쓰기
- 용도 구분 (채팅/이미지 생성/코딩)
- 모델 크레딧·비용
- 모델 로딩·목록 (이미 구현 — ModelCatalog/Provider/AIClientFactory)

사용자 결정(질문 응답):
1. **축1~4 전부 진행** (우선순위 순)
2. **크레딧 = 순수 비용 추적/표시만** (충전/잔액 없음)
3. **이미지 생성 추가** (DALL-E/이미지 API 지원)

---

## 1. 축별 구현 범위

### 축 1: 테마/UI 전체 적용 (v0.2.6)

**1a. ThemeManager 정상화 + 앱 루트 주입**
- `Core/ThemeManager.swift` 클래스명 `n` → `ThemeManager` 복구
- `AIModelTalkApp.swift` — 모든 Scene(7 Window + Settings) 루트에 `.environment(\.theme, ...)` 주입 (기존 Preview 한정 → 실제 경로 연결)
- SettingsView "일반" 탭에 라이트/다크/시스템/커스텀 테마 선택 UI 추가 (즉시 전환 확인 가능)

**1b. 16개 미적용 뷰 테마/글라스 적용**
- BubbleViews, SidebarView, ChatInputBarView, ModelPickerPopover
- ProvidersSettingsView, ModelsSettingsView, ModelManagerView, CustomEndpointEditorView
- 비교/평가/벤치마크/스플릿/브레인스토밍 등
- DS.* 호환 레이어 제거 (80곳) → Theme 적용
- GlassBackground 전체 적용 (macOS 26 글라스 + 폴백)

### 축 2: 모델 크레딧·비용 (v0.2.7) — 순수 비용 추적/표시

**2a. 모델 가격 데이터**
- `AIModel`에 `inputPricePerM: Double?` / `outputPricePerM: Double?` (백만 토큰당 USD) 추가
- `ModelCatalog.defaultModels` 유료 모델에 가격 부여; 무료(Ollama/`:free`/Apple)는 0
- 커스텀 모델 등록 UI(`AddModelSheet`)에 옵션 가격 입력 필드 추가

**2b. 비용 계산**
- `ChatMessage.costUSD: Double?` 추가 — 전송 시 `prompt×input + completion×output`
- `SessionTokens` 확장 → `SessionCost.calculated(messages:)` 누적
- `AssistantBubbleView`의 `$0.00` 하드코딩 제거 → 실제 계산 표시

**2c. 표시 UI**
- SettingsView "비용/토큰" 섹션 — 세션/전체 누적 비용, 모델별 가격 테이블, 예산(상한) 설정
- 말풍선 실비용 뱃지

### 축 3: 로컬 폴더 지정 + 파일 읽기·쓰기 (v0.3.0)

**3a. 프로젝트 폴더 지정**
- AppSettings에 `workspaceFolder: String?` 추가
- 설정/입력창 NSOpenPanel 폴더 선택 UI
- 시스템 프롬프트에 폴더 경로 + 파일 트리(요약) 주입

**3b. 내장 filesystem 도구 (MCP 의존 제거)**
- `ToolLoopService` 내장 도구에 `list_dir`, `read_file`, `write_file`, `edit_file` 추가
- 경로 샌드박스(지정 폴더 내 제한), 권한 게이트(YOLO/ask) 재사용
- `ToolRunCardView` 실행 기록 연동

### 축 4: 용도 모드 분리 + 이미지 생성 (v0.3.x)

**4a. 용도 모드 선택 UI**
- 채팅 / 이미지 생성 / 코딩 모드 (세션 속성 `mode` 추가, 상단 탭)
- 코딩 모드는 축3 파일 도구와 연계

**4b. DALL-E/이미지 API 지원 (신규 파이프라인)**
- `Providers/ImageClient.swift` — OpenAI `/v1/images/generations` + 호환 엔드포인트
- 이미지 생성 모델 추가 (ModelCatalog), 요청 시 이미지 결과 표시·저장

---

## 2. 핵심 구현 파일

| 축 | 파일 | 작업 |
|----|------|------|
| 1a | `Core/ThemeManager.swift`, `AIModelTalkApp.swift`, `Views/SettingsView.swift`, `Views/GeneralSettingsView.swift` | 클래스명 복구·주입·테마 UI |
| 1b | `Views/BubbleViews.swift`, `SidebarView.swift`, `ChatInputBarView.swift`, `ModelPickerPopover.swift`, `Views/ProvidersSettingsView.swift`, `ModelsSettingsView.swift`, `ModelManagerView.swift`, `CustomEndpointEditorView.swift` 등 | 테마/글라스 적용, DS 제거 |
| 2a | `Models/ChatModels.swift`, `Services/ModelCatalog.swift`, `Views/ModelsSettingsView.swift` | 가격 필드·가격 테이블·등록 UI |
| 2b | `Models/ChatModels.swift`, `ViewModels/ChatViewModel.swift`, `Views/BubbleViews.swift` | 비용 계산·누적·표시 |
| 2c | `Views/SettingsView.swift`, `Views/BubbleViews.swift` | 비용 섹션 UI |
| 3a | `Core/AppSettings.swift`, `Views/ChatInputBarView.swift`, `ViewModels/ChatViewModel.swift` | 폴더 선택·주입 |
| 3b | `Services/ToolLoopService.swift`, `Services/FileSystemTools.swift`(신규) | 내장 파일 도구 |
| 4a | `Models/ChatSession.swift`, `Views/ChatView.swift`, `ViewModels/ChatViewModel.swift` | 모드 선택 |
| 4b | `Providers/ImageClient.swift`(신규), `Services/ModelCatalog.swift`, `Views/ChatInputBarView.swift` | 이미지 생성 |

---

## 3. 검증 게이트

- 축마다: `xcodegen generate --spec project.yml` → `xcodebuild -project AIModelTalk.xcodeproj -scheme AIModelTalk -destination 'platform=macOS' -configuration Debug -derivedDataPath build CODE_SIGNING_REQUIRED=NO build` → 실행 확인
- 최종: `./build_and_run.sh debug macos`
- DebugPanel 로그: NEW 기능별 `[INFO] [FEATURE] <이름>` 1개 이상, 실패 경로 `[ERROR] E-...`
- 커밋: `feat(macos): ... (v0.2.x)` — main 직접, 1커밋 1관심사

---

## 4. 완료 기준 (DoD)

| 검증 항목 | 통과 기준 |
|----------|----------|
| 테마 즉시 전환 | 시스템/앱 설정에서 테마 전환 → 전체 뷰 즉시 반영 |
| 크레딧/비용 | 유료 모델 실측 토큰 → 실제 USD 비용 계산·누적·표시 (하드코딩 $0.00 제거) |
| 파일 접근 | 로컬 폴더 지정 + list_dir/read_file/write_file/edit_file 도구 동작 (샌드박스 보안) |
| 이미지 생성 | DALL-E/호환 API로 텍스트→이미지 생성·표시·저장 |
| 모드 분리 | 채팅/이미지/코딩 모드 전환 동작 |
| 빌드 성공 | xcodebuild + build_and_run 무오류 |
| 문서 갱신 | TODO.md·CHANGELOG.md·DESIGN.md 갱신, 짝수 릴리스마다 session 로그 |

---

## 5. 작업 순서 (일자별)

| 일차 | 작업 | 검증 |
|------|------|------|
| Day 1 | 1a ThemeManager 복구 + 앱 루트 주입 + 설정 테마 UI | 테마 전환 동작 |
| Day 2 | 1b 16개 뷰 테마/글라스 적용 + DS 제거 | 빌드 + 시각 확인 |
| Day 3 | 2a~2c 크레딧/비용(가격 테이블·계산·UI) | 유료 모델 비용 표시 |
| Day 4 | 3a 폴더 지정 + 프롬프트 주입 | 시스템 프롬프트 확인 |
| Day 5 | 3b 내장 파일 도구(샌드박스+권한) | 도구 실행 카드 |
| Day 6 | 4a 용도 모드 분리 | 모드 전환 |
| Day 7 | 4b 이미지 생성 파이프라인 | 이미지 렌더링 |
| Day 8 | 전체 빌드·실행·회귀 검증 + 문서 갱신 + 커밋 | build_and_run 통과 |

---

## 6. 승인

- [x] 사용자 명령: 문서 저장 후 축4까지 전체 진행
- [x] 크레딧 = 순수 비용 추적/표시
- [x] 이미지 생성 = DALL-E/이미지 API 지원 추가
