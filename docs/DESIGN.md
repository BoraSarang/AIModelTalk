# DESIGN — AIModelTalk (macOS)

버전: **0.1.0** — 신규 출발 기준 아키텍처 문서

## 아키텍처

```
AIModelTalk/
├── project.yml                      (xcodegen, 버전 0.1.0)
├── build_and_run.sh                 (빌드 디스패처)
├── AIModelTalk/
│   ├── AIModelTalkApp.swift           (App entry, WindowGroup + MenuBarExtra + Settings)
│   ├── Core/
│   │   ├── DebugLogger.swift          (구조화 로거)
│   │   ├── AppError.swift             (에러코드 래핑)
│   │   ├── AppSettings.swift          (UserDefaults 설정)
│   │   ├── HotKeyManager.swift        (Carbon 핫키)
│   │   ├── KeychainService.swift      (키체인 관리)
│   │   ├── SelectedTextCapture.swift  (선택 텍스트 캡처)
│   │   ├── PersistenceController.swift(SwiftData 컨테이너)
│   │   ├── TokenEstimator.swift       (토큰 근사 추정)
│   │   ├── ColorHex.swift             (Color(hex:) 확장)
│   │   └── DesignSystem.swift         (디자인 토큰/헬퍼)
│   ├── Models/
│   │   ├── ChatModels.swift           (ChatMessage·ChatSession·AIModel·SkillInfo)
│   │   ├── MemoryItem.swift           (전역 메모리 항목 + MemoryDurability)
│   │   ├── MemoryStore.swift          (전역 메모리 UserDefaults 저장소)
│   │   ├── SessionOrderStore.swift    (세션 재배치 순서)
│   │   ├── Provider.swift · ProviderEntry.swift · CustomEndpoint.swift
│   │   ├── DefaultModelStore.swift · SkillFlagStore.swift
│   │   └── Persistence.swift          (SwiftData 엔티티)
│   ├── Providers/
│   │   ├── AIClientFactory.swift
│   │   ├── OpenAICompatibleClient.swift
│   │   ├── GeminiClient.swift
│   │   ├── AnthropicClient.swift · OllamaProvider.swift
│   │   └── ToolCalling.swift
│   ├── Services/
│   │   ├── ModelCatalog.swift
│   │   ├── BenchmarkService.swift · ComparisonService.swift
│   │   ├── SkillLoader.swift          (4소스 스킬 로드) · SearchIndexService.swift
│   │   ├── MemoryService.swift        (자동 기억 추출) · MemoryRetrieval.swift
│   │   ├── MCP*.swift                 (MCP 클라이언트/모델/권한)
│   │   ├── ToolLoopService.swift      (MCP 도구 루프)
│   │   ├── ArtifactPreview.swift      (아티팩트 프리뷰)
│   │   ├── WebSearchService.swift · SessionExportService.swift
│   │   └── UpdateCheckService.swift · StreamManager.swift
│   ├── ViewModels/
│   │   └── ChatViewModel.swift
│   └── Views/
│       ├── ContentView.swift · ChatView.swift · SidebarView.swift
│       ├── BubbleViews.swift · MessageListView.swift · MarkdownRenderer.swift
│       ├── SettingsView.swift + 각 설정 탭(프로바이더/모델/스킬/MCP/단축키)
│       ├── DebugPanelView.swift · BenchmarkView.swift · ComparisonView.swift
│       └── QuickChatView.swift · GlobalSearchView.swift
└── docs/
```

## 기술 스택
- **플랫폼**: macOS 14+ (Sonoma)
- **UI**: SwiftUI + AppKit
- **언어**: Swift 5.9
- **프로젝트 생성**: xcodegen (버전 0.1.0)
- **키체인**: Security.framework (SecItem)
- **핫키**: Carbon (`RegisterEventHotKey`)
- **네트워크**: URLSession (SSE 스트리밍)
- **접근성**: ApplicationServices.framework (AX API)
- **영속성**: SwiftData (`ModelContainer` + `ModelContext`)

## 데이터 모델 (SwiftData)

```swift
@Model final class ChatSessionEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var systemPrompt: String
    var createdAt: Date
    var updatedAt: Date
    var currentModelID: String?
    var currentProviderRaw: String?
    var parentSessionID: UUID?      // 대화 분기
    var forkedFromMessageID: UUID?
    var isIncognito: Bool           // 전역 기억 미사용
    var archivedAt: Date?           // 보관함
    var deletedAt: Date?            // 휴지통
    @Relationship(deleteRule: .cascade, inverse: \ChatMessageEntity.session)
    var messages: [ChatMessageEntity]
}

@Model final class ChatMessageEntity {
    @Attribute(.unique) var id: UUID
    var roleRaw: String
    var content: String
    var providerRaw: String?
    var modelID: String?
    var timestamp: Date
    var isError: Bool
    var toolRunsData: Data?         // [ToolRun] JSON (MCP 도구 실행 이력)
    var session: ChatSessionEntity?
}
```

- `isStreaming`은 transient 상태 → 엔티티에 미포함
- 마이그레이션: UserDefaults "chatSessions" → 첫 실행 시 자동 이전 후 삭제
- 전역 메모리는 UserDefaults 주입형 저장소(`MemoryStore`)로 관리

## 데이터 흐름

### SSE 스트리밍
```
ChatView 입력 → AIClientFactory(선택 provider.client.stream)
→ URLSession.bytes lines 파싱 (data: JSON)
→ ChatMessage append (스트리밍 중 부분 갱신)
→ 완료 시 TTFT/총시간 기록 → BenchmarkService 랭킹 반영
```

### 프롬프트 조립 (`buildSystemPrompt`)
```
전역 시스템 프롬프트(세션 오버라이드 > AppSettings)
→ 전역 메모리 주입(관련도 검색 선별, 인코그니토 제외, 핀 우선·예산 절단)
→ 선택 스킬 누적
```

### 키 관리
```
KeychainService (SecItem)
├── NVIDIA: 자동 감지 · OpenRouter/Groq/Gemini: 수동 입력
└── 커스텀: URL + 키 수동 입력
```

### 자동 기억 (전역 체계)
```
대화 4교환마다 shouldExtract → 보조 모델로 사실 추출
→ 중복 제거 → MemoryService.applying (상한 초과 시 미핀/임시 우선 eviction)
→ 메모리 저장소에 영속 → 이후 세션 프롬프트에 주입
```

### MCP 도구 호출
```
sendMessage → mcpToolsEnabled && 활성 서버 있음
→ ToolLoopService.run(model, connections, permissionGate)
→ LLM tool_calls ↔ MCP callTool 루프 (최대 N회)
→ 각 호출마다 권한 게이트: 이번만 / 항상 허용 / 항상 거부 (MCPPermissionStore)
→ 실행 결과는 ChatMessage.toolRuns로 말풍선 카드 표시 + 엔티티 영속
```

## 디자인 시스템
- **브랜드 컬러**: 퍼플 (#AF52DE → #7A5CFF), 가변 `AccentTheme`
- **그리드**: 8pt 기준
- **말풍선**: 12px radius
- **타이포**: SF Pro
- **AI 말풍선**: `.regularMaterial` 소재 · **사용자 말풍선**: 퍼플 그라디언트

## 에러 코드 체계
형식: `E-MAC-{CATEGORY}-{NUM4}`
- KEY(키) · NET(네트워크) · API(API 응답) · MDL(모델) · PERM(권한) · STR(세션 저장) · AUTH · GLIST · BRIDGE
- 사용자 메시지는 `error_message_ko.json`에서 관리

## 사이드바 구성
- 대화 내역: 단일 세션 목록, 드래그로 재배치
- 보관함: `archivedAt != nil && deletedAt == nil`, 보관 시각 최신순
- 휴지통: `deletedAt != nil`, 삭제 시각 최신순, 30일 자동 비우기 + 수동 비우기
- 전역 검색(⌘⇧F) · 새 대화(⌘N)

## 보관함 & 휴지통

- 상태는 nil-기반 soft delete: `archivedAt`(보관) / `deletedAt`(휴지통)
- 상태 우선순위: `deletedAt != nil`(휴지통) > `archivedAt != nil`(보관) > 활성
- "삭제" = 휴지통 이동(`deleteSession`) → `deletedAt = Date()` + 검색 인덱스 제외
- 보관해제(`unarchiveSession`) / 복원(`restoreSession`, 검색 인덱스 재포함) / 영구삭제(`purgeSession`)
- `emptyTrash()` — 휴지통 전체 영구삭제 · `purgeExpiredTrash()` — 30일 초과 자동 비움(시작 시)
- 보관 세션은 검색·메모리에 포함 유지, 휴지통 세션만 제외