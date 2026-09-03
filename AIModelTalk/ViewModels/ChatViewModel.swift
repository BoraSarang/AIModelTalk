import Foundation
import Combine
import SwiftData
import AppKit
import UniformTypeIdentifiers

extension Notification.Name {
    static let scrollToBottom = Notification.Name("scrollToBottom")
}

/// send() 스트림 콜백에서 수집한 usage 보관함 — 값 캡처 데이터레이스 회피용 참조 타입 (v1.9 T-76)
final class UsageCapture {
    var promptTokens: Int?
    var completionTokens: Int?
}

@MainActor
final class ChatViewModel: ObservableObject {
    static let shared = ChatViewModel()

    @Published var sessions: [ChatSession] = []
    @Published var currentSessionID: UUID?
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var selectedModel: AIModel = {
        if let data = UserDefaults.standard.data(forKey: "lastSelectedModel"),
           let model = try? JSONDecoder().decode(AIModel.self, from: data) {
            return model
        }
        return ModelCatalog.primaryFallbackModel()
    }()
    @Published var availableSkills: [SkillInfo] = []
    @Published var selectedSkills: [SkillInfo] = {
        if let data = UserDefaults.standard.data(forKey: "lastSelectedSkills"),
           let skills = try? JSONDecoder().decode([SkillInfo].self, from: data) {
            return skills
        }
        return []
    }()
    @Published var streamingMessageID: UUID? = nil
    /// 이미지 첨부 대기열 (v1.8 T-71) — 전송 시 사용자 메시지에 부착 후 비움
    @Published var pendingAttachments: [MessageAttachment] = []
    /// 첨부 관련 안내 문구 (비전 미지원 모델 등)
    @Published var attachmentNotice: String? = nil
    /// 이번 전송에 웹 검색 사용 (v1.8 T-72) — 전송 후 자동 해제
    @Published var webSearchForNextSend = false
    /// 토큰 실측 갱신 신호 — 세션 합계 UI 재렌더 트리거 (v1.9 T-76)
    @Published private(set) var tokenTick = 0
    /// 검색 결과 이동 시 임시 하이라이트 대상 메시지 (v2.1 T-97)
    @Published var highlightedMessageID: UUID?
    // MARK: - 병렬 모델 비교 (T-201) — 대화 컨텍스트를 여러 모델에 동시 발송
    /// 비교 실행 중 여부 — true면 메시지 리스트 하단에 비교 결과 그리드 오버레이
    @Published var isComparing = false
    /// 비교 대상 모델 ID 집합 (대화 나란히 비교 선택)
    @Published var selectedCompareModelIDs: Set<String> = []
    /// 비교 실행 모델 파라미터 (T-202) — 전부 nil이면 공급자 기본값
    @Published var compareParams: ModelParams = .none
    /// 빠른 대화(패널) 세션 — 미저장 draft는 목록에서 숨겨지고 패널을 닫으면 폐기됨 (런타임 전용, SwiftData 미저장)
    @Published private(set) var quickSessionID: UUID?
    @Published private(set) var isQuickSessionDraft = false

/// 검색 결과 메시지 점프 요청 알림 — MessageListView가 수신해 절대 좌표 스크롤 (v2.1 T-97 고도화)
    static let scrollToMessage = Notification.Name("AIModelTalk.scrollToMessage")

    static let maxAttachments = 4
    /// 첨부 이미지 최대 변 (긴 쪽 기준, 픽셀) — API 페이로드 절감용
    static let attachmentMaxDimension: CGFloat = 1568

    // MARK: - 전역 메모리 (v0.1.2) — 과거 캐릭터 단위에서 앱 전역 단일로 전환

    @Published private(set) var memoryItems: [MemoryItem] = []
    private var memoryStore = MemoryStore(defaults: .standard)

    // MARK: - 프롬프트 템플릿 (T-208)

    @Published var promptTemplates: [PromptTemplate] = []
    private var templateStore = PromptTemplateStore(defaults: .standard)

    private let context: ModelContext
    /// 세션별 병렬 스트리밍 수명주기 관리 (v3.0 T-002)
    private let streamManager = StreamManager.shared
    /// 병렬 모델 비교 서비스 (T-201) — 대화 컨텍스트 공유 비교 실행
    private let comparisonService = ComparisonService.shared
    /// 현재 메인 창이 스트리밍 중인 세션 ID (스트리밍 중지 대상 추적)
    private var mainStreamingSessionID: UUID?

    // currentSession 캐시 — O(n) 선형 검색 제거
    var currentSession: ChatSession? {
        get {
            if let cached = _cachedSession, cached.id == currentSessionID {
                return cached
            }
            let found = sessions.first { $0.id == currentSessionID }
            _cachedSession = found
            return found
        }
    }
    private var _cachedSession: ChatSession?

    init() {
        DebugLogger.shared.info("APP", "ChatViewModel 초기화 시작")
        self.context = PersistenceController.shared.modelContext
        DebugLogger.shared.debug("APP", "SwiftData 컨텍스트 로드 완료")
        // UserDefaults → SwiftData 마이그레이션 (이미 되어 있으면 no-op)
        PersistenceController.migrateFromUserDefaultsIfNeeded()
        DebugLogger.shared.debug("APP", "마이그레이션 확인 완료")
        commonInit()
    }

    /// 테스트 격리용 — 인메모리 컨텍스트 + 격리 UserDefaults 주입 (공유 저장소·마이그레이션 미사용) (v1.8 T-73)
    init(context: ModelContext, defaults: UserDefaults = .standard) {
        self.context = context
        self.memoryStore = MemoryStore(defaults: defaults)
        self.templateStore = PromptTemplateStore(defaults: defaults)
        commonInit()
    }

    private func commonInit() {
        loadMemory()
        loadTemplates()
        loadSessions()
        purgeExpiredTrash()
        DebugLogger.shared.info("APP", "세션 로드 완료: \(sessions.count)개")
        SearchIndexService.shared.reindexIfEmpty(sessions: sessions)
        let active = visibleSessions
        if active.isEmpty {
            createNewSession()
            DebugLogger.shared.debug("APP", "새 세션 생성")
        } else {
            currentSessionID = active.first?.id
            if let first = active.first {
                restoreSessionState(first)
            }
            DebugLogger.shared.debug("APP", "기존 세션 선택: \(active.first?.title ?? "")")
        }
        Task { await refreshSkills() }
    }

    // MARK: - 세션 관리
    func createNewSession() {
        applyDefaultSkills() // 새 대화마다 기본 스킬 자동 적용 (v1.7 D7)
        // selectedSkills를 세션에 함께 저장 — 누락 시 직후 restoreSessionState가 빈 배열로
        // 덮어써서 기본 스킬이 즉시 사라졌음 (v1.7.3 T-65)
        // systemPrompt는 오버라이드 전용 필드 — 빈 값이면 전역 설정을 따른다 (v1.9 T-74)
        var session = ChatSession(title: "새 대화", currentModel: selectedModel, selectedSkills: selectedSkills)
        sessions.insert(session, at: 0)
        currentSessionID = session.id
        _cachedSession = nil
        saveSession(session)
    }

    /// Split Chat 분기 결과를 정식 세션으로 저장 (v3.0 T-129)
    /// sessions 맨 앞에 삽입 + 선택 + SwiftData 영속화. 인코그니토는 유지하지 않음.
    func importSplitSession(_ session: ChatSession) {
        var imported = session
        if imported.title.isEmpty { imported.title = "스플릿 채팅" }
        sessions.insert(imported, at: 0)
        currentSessionID = imported.id
        _cachedSession = nil
        saveSession(imported)
        SearchIndexService.shared.index(imported)
        DebugLogger.shared.info("SPLIT", "[FEATURE] 스플릿 세션 주입 완료: '\(imported.title)' (\(imported.messages.count)개 메시지)")
    }

    /// 세션 오버라이드가 없으면 전역 설정 + 선택된 모든 스킬을 조합 (v1.9 T-74)
    func buildSystemPrompt() -> String {
        let override = currentSession?.systemPrompt ?? ""
        var prompt = Self.resolveBasePrompt(
            override: override,
            globalPrompt: AppSettings.shared.systemPrompt
        )
        // 전역 메모리 주입 — 관련도 검색 선별. 인코그니토 세션은 기억을 회수하지 않는다
        let lastUserQuery = currentSession?.messages.last(where: { $0.role == .user })?.content
        prompt = Self.assemblePrompt(
            base: prompt,
            memories: memoryItems,
            includeMemory: currentSession?.isIncognito != true,
            memoryQuery: lastUserQuery
        )
        for skill in selectedSkills {
            prompt += "\n\n## 스킬: \(skill.name)\n\(skill.content)"
        }
        return prompt
    }

    /// 베이스 프롬프트 우선순위 — 세션 오버라이드 > 전역
    nonisolated static func resolveBasePrompt(override: String, globalPrompt: String) -> String {
        let o = override.trimmingCharacters(in: .whitespacesAndNewlines)
        if !o.isEmpty { return o }
        return globalPrompt
    }

    /// 전역 메모리 조립 — 관련도 검색 선별, 예산 초과분 절단. 순수 함수로 테스트 가능 (v0.1.2)
    nonisolated static func assemblePrompt(
        base: String,
        memories: [MemoryItem] = [],
        memoryBudget: Int = 3_000,
        includeMemory: Bool = true,
        memoryQuery: String? = nil
    ) -> String {
        var p = base

        // 메모리 — 관련도 검색 선별, 쿼리 없으면 핀·최신순, 예산 초과분 절단
        var lines: [String] = []
        if includeMemory {
            let selected: [MemoryItem]
            let sorted = memories.sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return $0.createdAt > $1.createdAt
            }
            if let memoryQuery, !memoryQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                selected = MemoryRetrieval.rank(
                    query: memoryQuery, items: memories,
                    limit: MemoryRetrieval.defaultLimit,
                    embedder: SemanticEmbedder.shared.vector)
            } else {
                selected = sorted
            }
            var used = 0
            for item in selected where !item.content.trimmingCharacters(in: .whitespaces).isEmpty {
                let line = "- \(item.content)"
                if used + line.count > memoryBudget { break }
                lines.append(line)
                used += line.count
            }
        }
        if !lines.isEmpty {
            p += "\n\n## 장기 기억 (모든 대화에 걸쳐 유지하는 기억)\n" + lines.joined(separator: "\n")
        }

        return p
    }

    // MARK: - 전역 메모리 관리 (v0.1.2)

    func loadMemory() {
        memoryItems = memoryStore.items
    }

    func addMemory(_ content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = MemoryItem(content: trimmed, isAuto: false)
        memoryStore.upsert(item)
        loadMemory()
        DebugLogger.shared.info("MEMORY", "[FEATURE] 기억 추가됨: '\(trimmed.prefix(40))'")
    }

    func deleteMemory(memoryID: UUID) {
        memoryStore.remove(id: memoryID)
        loadMemory()
        DebugLogger.shared.info("MEMORY", "[FEATURE] 기억 삭제됨")
    }

    func toggleMemoryPin(memoryID: UUID) {
        var list = memoryItems
        guard let index = list.firstIndex(where: { $0.id == memoryID }) else { return }
        list[index].isPinned.toggle()
        memoryStore.items = list
        loadMemory()
        DebugLogger.shared.info("MEMORY", "[FEATURE] 기억 고정 토글됨")
    }

    /// 기억 듀레이션(영구/임시) 변경 (T-208) — 임시는 자동 정리 우선 대상
    func setMemoryDurability(memoryID: UUID, to durability: MemoryDurability) {
        var list = memoryItems
        guard let index = list.firstIndex(where: { $0.id == memoryID }) else { return }
        list[index].durability = durability
        memoryStore.items = list
        loadMemory()
        DebugLogger.shared.info("MEMORY", "[FEATURE] 기억 내구성 변경 → \(durability.rawValue)")
    }

    // MARK: - 프롬프트 템플릿 (T-208)

    func loadTemplates() {
        promptTemplates = templateStore.templates
    }

    func saveTemplate(_ template: PromptTemplate) {
        templateStore.upsert(template)
        loadTemplates()
        DebugLogger.shared.info("TEMPLATE", "[FEATURE] 프롬프트 템플릿 저장됨: '\(template.name)'")
    }

    func deleteTemplate(id: UUID) {
        templateStore.remove(id: id)
        loadTemplates()
        DebugLogger.shared.info("TEMPLATE", "[FEATURE] 프롬프트 템플릿 삭제됨")
    }

    /// 템플릿을 입력창에 삽입 — placeholder는 변수 값으로 치환 후 커서 위치에 붙임 (T-208)
    func applyTemplate(_ template: PromptTemplate, values: [String: String]) {
        let rendered = template.applying(values: values)
        if inputText.isEmpty {
            inputText = rendered
        } else {
            if !inputText.hasSuffix("\n") { inputText += "\n" }
            inputText += rendered
        }
        DebugLogger.shared.info("TEMPLATE", "[FEATURE] 프롬프트 템플릿 적용: '\(template.name)'")
    }

    // MARK: - 보조 모델 (v2.3 T-118)

    /// 백그라운드 작업용 보조 모델 — 설정 지정 우선, 자동 감지(flash→mini), 최종 nil이면 세션 모델 폴백
    var auxiliaryModel: AIModel? {
        let spec = AppSettings.shared.auxiliaryModelSpec
        let enabled = ModelCatalog.shared.models.filter { ModelCatalog.shared.isEnabled($0) }
        if !spec.isEmpty {
            return Self.resolveModel(spec: spec, catalog: enabled)
                ?? Self.autoDetectAuxiliaryModel(from: enabled)
        }
        return Self.autoDetectAuxiliaryModel(from: enabled)
    }

    /// spec("providerRaw:modelID") → 카탈로그 모델 (순수)
    nonisolated static func resolveModel(spec: String, catalog: [AIModel]) -> AIModel? {
        guard let sep = spec.firstIndex(of: ":") else { return nil }
        let providerRaw = String(spec[..<sep])
        let modelID = String(spec[spec.index(after: sep)...])
        return catalog.first {
            $0.provider.rawValue.caseInsensitiveCompare(providerRaw) == .orderedSame && $0.id == modelID
        }
    }

    /// 자동 감지 — flash 계열 → mini 계열 우선, 없으면 nil(호출부가 세션 모델 폴백) (순수)
    nonisolated static func autoDetectAuxiliaryModel(from models: [AIModel]) -> AIModel? {
        if let flash = models.first(where: { $0.id.lowercased().contains("flash") }) { return flash }
        if let mini = models.first(where: { $0.id.lowercased().contains("mini") }) { return mini }
        return nil
    }

    /// 모델 응답에서 제목 정제 — 코드펜스·따옴표·개행 제거, 24자 제한 (순수)
    nonisolated static func cleanedTitle(from response: String) -> String? {
        var t = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = t.replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        t = t.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let quotes = ["\"", "'", "\u{201C}", "\u{201D}", "\u{2018}", "\u{2019}"]
        for q in quotes where t.count > 1 && t.hasPrefix(q) && t.hasSuffix(q) {
            t = String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        guard !t.isEmpty else { return nil }
        return t.count > 24 ? String(t.prefix(24)) + "…" : t
    }

    /// 제목 LLM 자동생성 — 보조 모델 사용, 실패·부재 시 무음 폴백(임시 접두사 유지)
    private func generateTitle(sessionID: UUID, provisional: String, userText: String) {
        guard let model = auxiliaryModel else { return }
        let prompt = """
        다음 대화의 제목을 지어주세요.
        규칙: 한국어, 20자 이내, 따옴표·마침표·설명 없이 제목 본문만 출력.

        사용자 메시지:
        \(String(userText.prefix(300)))
        """
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let client = try AIClientFactory.client(provider: model.provider, modelID: model.id)
                var text = ""
                let stream = client.stream(messages: [ChatMessage(role: .user, content: prompt)], systemPrompt: nil, onUsage: nil)
                for try await chunk in stream { text += chunk }
                guard let title = Self.cleanedTitle(from: text) else { return }
                guard let idx = self.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
                // 사용자가 이미 이름을 바꾸지 않았을 때만 반영
                guard self.sessions[idx].title == provisional || self.sessions[idx].title == "새 대화" else { return }
                self.sessions[idx].title = title
                self._cachedSession = nil
                self.saveSession(self.sessions[idx])
                DebugLogger.shared.info("SESSION", "[FEATURE] 제목 자동생성됨: '\(title)' (보조 모델)")
            } catch {
                DebugLogger.shared.debug("SESSION", "제목 자동생성 실패 — 무음 폴백: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - MCP 도구 호출 (v2.4 T-120)

    /// 서버별 연결 캐시 — 같은 설정이면 재사용 (stdio/http 공용, v2.4 T-122)
    @Published private(set) var mcpConnections: [UUID: any MCPTransportConnection] = [:]

    /// 권한 확인 대기 — ChatView의 confirmationDialog가 렌더링
    struct PendingToolPermission: Identifiable {
        let id = UUID()
        let toolName: String
        let argumentsPreview: String
        fileprivate let continuation: CheckedContinuation<ToolLoopService.PermissionDecision, Never>
    }
    @Published var pendingToolPermission: PendingToolPermission?

    enum ToolPermissionResponse {
        case allowOnce, alwaysAllow, denyOnce, alwaysDeny
    }

    /// 활성화된 MCP 서버 연결 확보 — 실패 서버는 건너뛴다
    func activeMCPConnections() async -> [any MCPTransportConnection] {
        var result: [any MCPTransportConnection] = []
        for config in MCPServerStore.shared.servers where config.isEnabled {
            let connection = mcpConnections[config.id] ?? MCPConnectionFactory.make(config: config)
            mcpConnections[config.id] = connection
            if case .ready = connection.state {
                result.append(connection)
                continue
            }
            await connection.connect()
            if case .ready = connection.state {
                result.append(connection)
            } else if case let .failed(reason) = connection.state {
                DebugLogger.shared.warn("MCP", "[\(config.name)] 연결 실패로 제외: \(reason)")
            }
        }
        return result
    }

    /// 도구 정의 목록 — 연결에서 수집
    private func toolDefinitions(from connections: [any MCPTransportConnection]) -> [LLMToolDefinition] {
        connections.flatMap { conn in
            conn.tools.map { LLMToolDefinition(name: $0.name, description: $0.description, parametersJSON: $0.inputSchemaJSON) }
        }
    }

    /// 내장 도구(에이전트 모드) 스키마 (T-204) — 웹검색·페이지읽기·계산기
    static func builtinToolDefinitions() -> [LLMToolDefinition] {
        [
            LLMToolDefinition(name: "web_search", description: "실시간 웹 검색. 질문에 최신 정보가 필요할 때 사용하세요.", parametersJSON: """
            {"type":"object","properties":{"query":{"type":"string","description":"검색어"}},"required":["query"]}
            """),
            LLMToolDefinition(name: "fetch_url", description: "주어진 URL의 웹 페이지 본문을 읽어옵니다.", parametersJSON: """
            {"type":"object","properties":{"url":{"type":"string","description":"http(s) URL"}},"required":["url"]}
            """),
            LLMToolDefinition(name: "calculator", description: "사칙연산 계산. 정확한 수치 계산 시 사용하세요.", parametersJSON: """
            {"type":"object","properties":{"expression":{"type":"string","description":"예: (2+3)*4"}},"required":["expression"]}
            """)
        ]
    }

    /// 권한 게이트 — 정책 조회, YOLO 자동 승인, ask면 UI 프롬프트 대기
    private func permissionGate(for call: LLMToolCall) async -> ToolLoopService.PermissionDecision {
        if AppSettings.shared.yoloMode {
            return .allowed // T-204 YOLO — 모든 도구 자동 승인
        }
        switch MCPPermissionStore.shared.policy(forTool: call.name) {
        case .alwaysAllow:
            return .allowed
        case .deny:
            return .denied
        case .ask:
            return await withCheckedContinuation { continuation in
                pendingToolPermission = PendingToolPermission(
                    toolName: call.name,
                    argumentsPreview: Self.prettyArguments(call.argumentsJSON),
                    continuation: continuation)
            }
        }
    }

    /// 인자 JSON을 사람이 읽는 형태로 — 카드/프롬프트 표시용 (순수)
    nonisolated static func prettyArguments(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: pretty, encoding: .utf8) else {
            return json.isEmpty ? "{}" : json
        }
        return text
    }

    func respondToToolPermission(_ response: ToolPermissionResponse) {
        guard let pending = pendingToolPermission else { return }
        pendingToolPermission = nil
        let store = MCPPermissionStore.shared
        switch response {
        case .allowOnce:
            pending.continuation.resume(returning: .allowed)
        case .alwaysAllow:
            store.setPolicy(.alwaysAllow, forTool: pending.toolName)
            pending.continuation.resume(returning: .allowed)
        case .denyOnce:
            pending.continuation.resume(returning: .denied)
        case .alwaysDeny:
            store.setPolicy(.deny, forTool: pending.toolName)
            pending.continuation.resume(returning: .denied)
        }
        DebugLogger.shared.info("TOOLS", "권한 결정 '\(pending.toolName)': \(response)")
    }

    /// 실행 기록을 어시스턴트 메시지에 부착 — 말풍선 실행 카드
    private func attachToolRuns(_ records: [ToolLoopService.ExecutionRecord], messageID: UUID, sessionID: UUID) {
        mutateMessages(of: sessionID) { messages in
            if let idx = messages.firstIndex(where: { $0.id == messageID }) {
                messages[idx].toolRuns = records
            }
        }
    }

    // MARK: - 인코그니토 (v2.3 T-116)

    /// 현재 세션의 인코그니토 토글 — 기억 미회수·미생성
    func toggleIncognito() {
        guard let sessionID = currentSessionID,
              let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].isIncognito.toggle()
        _cachedSession = nil
        saveSession(sessions[index])
        DebugLogger.shared.info("APP", "[FEATURE] 인코그니토 \(sessions[index].isIncognito ? "켜짐" : "꺼짐"): 세션 \(sessionID)")
    }

    // MARK: - 자동 기억 추출 (v0.1.2 전역화)

    /// 응답 완료 후 호출 — 4교환마다 전역 기억 추출 실행 (실패 시 조용히 로그만)
    /// 인코그니토 세션은 기억을 만들지 않는다
    private func maybeAutoExtractMemory(ctx: SendContext) {
        guard let session = sessions.first(where: { $0.id == ctx.sessionID }),
              !session.isIncognito else { return }
        let userCount = session.messages.filter { $0.role == .user }.count
        guard MemoryService.shouldExtract(userMessageCount: userCount) else { return }

        let recent = session.messages.suffix(8)
            .map { "\($0.role == .user ? "사용자" : "제너레이터"): \($0.content)" }
            .joined(separator: "\n\n")
        let existing = memoryItems.map { $0.content }
        // 보조 모델 우선 — 대화 모델 토큰 낭비 방지, 없으면 세션 모델
        let model = auxiliaryModel ?? ctx.model

        Task { @MainActor [weak self] in
            await self?.extractMemories(model: model, existing: existing, recent: recent)
        }
    }

    private func extractMemories(model: AIModel, existing: [String], recent: String) async {
        let prompt = MemoryService.extractionPrompt(existing: existing, recentTranscript: recent)
        do {
            let client = try AIClientFactory.client(provider: model.provider, modelID: model.id)
            var text = ""
            let stream = client.stream(messages: [ChatMessage(role: .user, content: prompt)], systemPrompt: nil, onUsage: nil)
            for try await chunk in stream { text += chunk }

            var candidates = MemoryService.parseCandidates(text)
            candidates = MemoryService.deduplicate(candidates, existing: existing)
            guard !candidates.isEmpty else { return }

            memoryItems = MemoryService.applying(candidates, to: memoryItems)
            memoryStore.items = memoryItems
            loadMemory()
            DebugLogger.shared.info("MEMORY", "[FEATURE] 자동 기억 저장됨: \(candidates.count)건")
        } catch {
            DebugLogger.shared.warn("MEMORY", "[E-MAC-AI-1005] 자동 기억 추출 실패: \(error.localizedDescription)")
        }
    }

    /// 휴지통으로 이동 (soft delete) — 즉시 소멸하지 않고 deletedAt 설정
    func deleteSession(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        var session = sessions[index]
        session.deletedAt = Date()
        session.archivedAt = nil
        sessions[index] = session
        saveSession(session)
        SearchIndexService.shared.remove(sessionID: id) // 검색 인덱스에서 제외 (휴지통)
        if currentSessionID == id {
            currentSessionID = sessions.first { $0.deletedAt == nil && $0.archivedAt == nil }?.id
            _cachedSession = nil
        }
    }

    /// 보관함으로 이동
    func archiveSession(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }), sessions[index].deletedAt == nil else { return }
        var session = sessions[index]
        session.archivedAt = Date()
        sessions[index] = session
        saveSession(session)
        if currentSessionID == id {
            currentSessionID = sessions.first { $0.deletedAt == nil && $0.archivedAt == nil }?.id
            _cachedSession = nil
        }
    }

    /// 보관 해제 (활성으로 복귀)
    func unarchiveSession(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        var session = sessions[index]
        session.archivedAt = nil
        sessions[index] = session
        saveSession(session)
    }

    /// 휴지통에서 복원 (활성으로 복귀)
    func restoreSession(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        var session = sessions[index]
        session.deletedAt = nil
        session.archivedAt = nil
        sessions[index] = session
        saveSession(session)
        SearchIndexService.shared.index(session) // 검색 인덱스 재포함
    }

    /// 완전 소멸 (복구 불가) — 휴지통에서만 동작
    func purgeSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        deleteSessionEntity(id)
        SearchIndexService.shared.remove(sessionID: id)
        if currentSessionID == id {
            currentSessionID = sessions.first { $0.deletedAt == nil && $0.archivedAt == nil }?.id
            _cachedSession = nil
        }
    }

    /// 휴지통 전체 비우기 (완전 소멸)
    func emptyTrash() {
        let trashIDs = trashSessions.map(\.id)
        for id in trashIDs {
            sessions.removeAll { $0.id == id }
            deleteSessionEntity(id)
            SearchIndexService.shared.remove(sessionID: id)
        }
        if let cur = currentSessionID, trashIDs.contains(cur) {
            currentSessionID = sessions.first { $0.deletedAt == nil && $0.archivedAt == nil }?.id
            _cachedSession = nil
        }
    }

    /// 휴지통 자동 비우기 — deletedAt이 30일 초과한 세션을 완전 소멸
    func purgeExpiredTrash() {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        let expired = sessions.filter { $0.deletedAt.map { $0 < cutoff } ?? false }
        guard !expired.isEmpty else { return }
        for session in expired {
            sessions.removeAll { $0.id == session.id }
            deleteSessionEntity(session.id)
            SearchIndexService.shared.remove(sessionID: session.id)
        }
        DebugLogger.shared.info("APP", "[FEATURE] 휴지통 자동 비우기: \(expired.count)개 세션 완전 삭제")
    }

    func importSession(_ session: ChatSession) {
        var imported = session
        imported.id = UUID() // 중복 방지
        imported.updatedAt = Date()
        sessions.insert(imported, at: 0)
        saveSession(imported)
        currentSessionID = imported.id
    }

    // MARK: - 빠른 대화 패널 세션 (PLAN_v1.6 T-43)

    /// 사이드바 노출용 목록 — 미저장 draft + 보관/휴지통 세션 제외
    var visibleSessions: [ChatSession] {
        sessions.filter { $0.deletedAt == nil && $0.archivedAt == nil && !($0.id == quickSessionID && isQuickSessionDraft) }
    }

    /// 보관함 — 보관 상태이며 휴지통 아님, 보관 시각 최신순
    var archivedSessions: [ChatSession] {
        sessions
            .filter { $0.archivedAt != nil && $0.deletedAt == nil }
            .sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
    }

    /// 휴지통 — 삭제 시각 최신순
    var trashSessions: [ChatSession] {
        sessions
            .filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    /// 패널 열림: 이전 패널 세션 정리(미저장 draft 폐기) 후 새 draft 생성
    /// currentSessionID는 건드리지 않아 메인 창 선택이 유지된다
    func beginQuickChat() {
        endQuickChat()
        let session = ChatSession(title: "빠른 대화", currentModel: selectedModel, selectedSkills: selectedSkills)
        sessions.append(session)
        _cachedSession = nil
        quickSessionID = session.id
        isQuickSessionDraft = true
        DebugLogger.shared.info("SESSION", "빠른 대화 draft 시작")
    }

    /// draft를 정식 세션으로 저장 (제목 = 첫 사용자 메시지 30자).
    /// 저장 후에도 같은 세션에 이어서 대화할 수 있다.
    @discardableResult
    func saveQuickSessionAsNew() -> Bool {
        guard isQuickSessionDraft, let id = quickSessionID,
              let index = sessions.firstIndex(where: { $0.id == id }),
              !sessions[index].messages.isEmpty else { return false }
        let raw = sessions[index].messages.first(where: { $0.role == .user })?.content ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "빠른 대화" : String(trimmed.prefix(30))
        sessions[index].title = base + (trimmed.count > 30 ? "…" : "")
        sessions[index].updatedAt = Date()
        isQuickSessionDraft = false
        saveSession(sessions[index])
        DebugLogger.shared.info("SESSION", "빠른 대화 저장: \(sessions[index].title)")
        return true
    }

    /// 패널 닫힘: 미저장 draft면 폐기(요구사항 — 닫으면 삭제), 저장된 세션이면 목록에 유지
    func endQuickChat() {
        guard let id = quickSessionID else { return }
        defer {
            quickSessionID = nil
            isQuickSessionDraft = false
        }
        guard isQuickSessionDraft,
              let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        if isLoading || streamingMessageID != nil {
            stopStreaming()
        }
        sessions.remove(at: index)
        _cachedSession = nil
        DebugLogger.shared.info("SESSION", "빠른 대화 draft 폐기")
    }

    func selectModel(_ model: AIModel) {
        DebugLogger.shared.info("MODEL", "모델 변경: \(model.id) (\(model.provider.rawValue))")
        // T-207 미드스위치 — 생성 중이면 정지 후 새 모델로 그 자리에 재전송
        let wasStreaming = !isLoading && streamingMessageID != nil
        let abortedAssistantID = streamingMessageID
        if wasStreaming {
            stopStreaming()
        }
        selectedModel = model
        persistSelection()
        // 모델 변경 시 현재 세션 상태 동기화
        if let index = sessions.firstIndex(where: { $0.id == currentSessionID }) {
            sessions[index].currentModel = model
            sessions[index].selectedSkills = selectedSkills
            saveSession(sessions[index])
        }
        // 미드스위치 — 미완 어시스턴트 제거 후 마지막 사용자 프롬프트 재전송
        if wasStreaming {
            rerunAfterModelSwitch(model: model, abortedAssistantID: abortedAssistantID)
        }
    }

    /// 미드스위치 재전송 (T-207) — 스트리밍 중단 후 미완 어시스턴트를 지우고 마지막 질문을 새 모델로 재전송
    private func rerunAfterModelSwitch(model: AIModel, abortedAssistantID: UUID?) {
        guard let sessionID = currentSessionID,
              let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        // 미완 어시스턴트 제거 후 마지막 사용자 프롬프트 결정 (순수)
        guard let (text, attachments) = Self.midSwitchProxy(
            in: sessions[sessionIndex].messages,
            abortedAssistantID: abortedAssistantID
        ) else { return }
        if abortedAssistantID != nil {
            // 중단된 어시스턴트가 실제로 있는 경우에만 제거
            mutateMessages(of: sessionID) { messages in
                if let abortedID = abortedAssistantID {
                    if let i = messages.firstIndex(where: { $0.id == abortedID }) {
                        messages.remove(at: i)
                    } else if let last = messages.last, last.role == .assistant, last.content.isEmpty {
                        messages.removeLast()
                    }
                }
            }
        } else if let last = sessions[sessionIndex].messages.last, last.role == .assistant, last.content.isEmpty {
            mutateMessages(of: sessionID) { messages in messages.removeLast() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.sendMessage(text, to: sessionID, attachments: attachments, reuseLastUser: true)
        }
        DebugLogger.shared.info("MODEL", "[FEATURE] 미드스위치 → '\(model.displayName)'로 재전송: \(text.prefix(40))…")
    }

    /// 미드스위치 재전송 대상 결정 (순수, T-207) — 중단된 어시스턴트를 논리적으로 배제하고 마지막 사용자 메시지를 반환.
    /// 실제 메시지 배열은 수정하지 않는다(전송 대상 식별만). 어시스턴트가 진짜 중단 대상이면 그 자리의 사용자 프롬프트를 재전송.
    nonisolated static func midSwitchProxy(in messages: [ChatMessage], abortedAssistantID: UUID?) -> (text: String, attachments: [MessageAttachment])? {
        var working = messages
        // 중단 어시스턴트 제거 — 명시 ID, 없으면 마지막 빈 어시스턴트
        if let abortedID = abortedAssistantID {
            if let i = working.firstIndex(where: { $0.id == abortedID }) {
                working.remove(at: i)
            } else if let last = working.last, last.role == .assistant, last.content.isEmpty {
                working.removeLast()
            }
        } else if let last = working.last, last.role == .assistant, last.content.isEmpty {
            working.removeLast()
        }
        guard let user = working.last(where: { $0.role == .user }) else { return nil }
        return (user.content, user.attachments ?? [])
    }

    /// 포크 재실행 대상 결정 (순수, T-207) — 분기점까지 히스토리에서 마지막 사용자 메시지를 반환.
    nonisolated static func forkRerunProxy(in messages: [ChatMessage], cutMessageID: UUID) -> (text: String, attachments: [MessageAttachment])? {
        guard let cutIndex = messages.firstIndex(where: { $0.id == cutMessageID }) else { return nil }
        let slice = messages[messages.startIndex...cutIndex]
        guard let user = slice.last(where: { $0.role == .user }) else { return nil }
        return (user.content, user.attachments ?? [])
    }

    func toggleSkill(_ skill: SkillInfo) {
        if let index = selectedSkills.firstIndex(where: { $0.id == skill.id }) {
            selectedSkills.remove(at: index)
        } else {
            selectedSkills.append(skill)
        }
        persistSelection()
        // 스킬 변경 시 현재 세션에 저장 (프롬프트는 전송 시점에 라이브 조합)
        if let index = sessions.firstIndex(where: { $0.id == currentSessionID }) {
            sessions[index].selectedSkills = selectedSkills
            saveSession(sessions[index])
        }
    }

    func clearSkills() {
        selectedSkills.removeAll()
        syncCurrentSessionSkills()
    }

    private func persistSelection() {
        if let data = try? JSONEncoder().encode(selectedModel) {
            UserDefaults.standard.set(data, forKey: "lastSelectedModel")
        }
        if let data = try? JSONEncoder().encode(selectedSkills) {
            UserDefaults.standard.set(data, forKey: "lastSelectedSkills")
        }
    }

    // MARK: - 스킬 표시/기본 설정 (v1.7 T-54~56 · v1.7.1 T-60~62)

    /// 저장 경유용(UserDefaults 주입형) — 뷰 갱신은 아래 @Published 플래그가 담당 (T-60)
    var skillFlags = SkillFlagStore(defaults: .standard)

    /// 피커에서 숨긴(사용 해제한) 스킬 ID — @Published라 설정 탭·피커에 즉시 반영
    @Published private(set) var hiddenSkillIDs: Set<String> = SkillFlagStore(defaults: .standard).hiddenIDs

    /// 기본 스킬 ID — 새 대화에 자동 적용 (D7)
    @Published private(set) var defaultSkillIDs: Set<String> = SkillFlagStore(defaults: .standard).defaultIDs

    /// 피커에 노출되는 스킬 — 사용 해제 제외 (D4 완전 숨김)
    var visibleSkills: [SkillInfo] {
        availableSkills.filter { !hiddenSkillIDs.contains($0.id) }
    }

    func isSkillHidden(_ skill: SkillInfo) -> Bool {
        hiddenSkillIDs.contains(skill.id)
    }

    func setSkillHidden(_ skill: SkillInfo, _ hidden: Bool) {
        var ids = hiddenSkillIDs
        if hidden {
            ids.insert(skill.id)
            // 사용 해제 시: 현재 선택 + 기본 체크도 함께 해제 (T-62)
            if selectedSkills.contains(where: { $0.id == skill.id }) {
                selectedSkills.removeAll { $0.id == skill.id }
                syncCurrentSessionSkills()
            }
            if defaultSkillIDs.contains(skill.id) {
                var defIDs = defaultSkillIDs
                defIDs.remove(skill.id)
                skillFlags.defaultIDs = defIDs
                defaultSkillIDs = defIDs
            }
        } else {
            ids.remove(skill.id)
        }
        skillFlags.hiddenIDs = ids
        hiddenSkillIDs = ids
        DebugLogger.shared.info("APP", "스킬 \(hidden ? "사용 해제" : "사용"): \(skill.name)")
    }

    func isDefaultSkill(_ skill: SkillInfo) -> Bool {
        defaultSkillIDs.contains(skill.id)
    }

    func setDefaultSkill(_ skill: SkillInfo, _ isDefault: Bool) {
        var ids = defaultSkillIDs
        if isDefault {
            ids.insert(skill.id)
        } else {
            ids.remove(skill.id)
        }
        skillFlags.defaultIDs = ids
        defaultSkillIDs = ids
        DebugLogger.shared.info("APP", "기본 스킬 \(isDefault ? "설정" : "해제"): \(skill.name)")
    }

    /// 스킬 일괄 토글 — 모두 숨김 시 선택·기본도 전체 해제 (T-61)
    func setAllSkillsHidden(_ hidden: Bool) {
        let ids: Set<String> = hidden ? Set(availableSkills.map(\.id)) : []
        skillFlags.hiddenIDs = ids
        hiddenSkillIDs = ids

        if hidden {
            skillFlags.defaultIDs = []
            defaultSkillIDs = []
            if !selectedSkills.isEmpty {
                selectedSkills.removeAll()
                syncCurrentSessionSkills()
            }
        }
        DebugLogger.shared.info("APP", "스킬 \(hidden ? "전체 숨김" : "전체 표시"): \(availableSkills.count)개")
    }

    /// 현재 세션에 선택 스킬 동기화
    private func syncCurrentSessionSkills() {
        persistSelection()
        if let index = sessions.firstIndex(where: { $0.id == currentSessionID }) {
            sessions[index].selectedSkills = selectedSkills
            saveSession(sessions[index])
        }
    }

    /// 새 대화마다 기본 스킬을 자동 적용 (D7) — 삭제된 스킬은 무시
    private func applyDefaultSkills() {
        guard !defaultSkillIDs.isEmpty else { return }
        let matched = availableSkills.filter { defaultSkillIDs.contains($0.id) }
        guard !matched.isEmpty else { return }
        selectedSkills = matched
        persistSelection()
    }

    /// ~/.opencode/skills 재스캔 — 앱 재시작 없이 반영 (T-54)
    func refreshSkills() async {
        availableSkills = await SkillLoader.loadSkills()
        DebugLogger.shared.info("APP", "스킬 로드 완료: \(availableSkills.count)개")
    }

    /// 전역 검색 결과로 이동 — 세션 전환 + 해당 메시지 하이라이트 (v2.1 T-97)
    func jumpToSearchHit(_ hit: SearchIndexService.SearchHit) {
        currentSessionID = hit.sessionID
        _cachedSession = nil
        guard hit.role != "title" else {
            DebugLogger.shared.info("SEARCH", "[FEATURE] 검색 결과 이동 실행됨(세션 제목): \(hit.sessionID)")
            return
        }
        highlightedMessageID = hit.messageID
        DebugLogger.shared.info("SEARCH", "[FEATURE] 검색 결과 이동 실행됨: 메시지 \(hit.messageID)")
        // 뷰가 해당 메시지 위치로 절대 스크롤하도록 요청 (수렴형 보정은 MessageListView 담당)
        NotificationCenter.default.post(
            name: ChatViewModel.scrollToMessage,
            object: nil,
            userInfo: ["id": hit.messageID]
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if self?.highlightedMessageID == hit.messageID {
                self?.highlightedMessageID = nil
            }
        }
    }

    /// API 실측 토큰 수를 어시스턴트 메시지에 기록 (v1.9 T-76)
    func attachTokenCounts(prompt: Int, completion: Int, messageID: UUID, sessionID: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionID }),
              let mIdx = sessions[idx].messages.firstIndex(where: { $0.id == messageID }) else { return }
        sessions[idx].messages[mIdx].promptTokens = prompt
        sessions[idx].messages[mIdx].completionTokens = completion
        _cachedSession = nil
        tokenTick += 1
        saveSession(sessions[idx])
    }

    /// 세션 전환 시 모델/스킬 복원
    func restoreSessionState(_ session: ChatSession) {
        if let model = session.currentModel {
            selectedModel = model
        }
        selectedSkills = session.selectedSkills
        persistSelection()
    }

    // MARK: - 세션 이름 수정
    func renameSession(_ id: UUID, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].title = trimmed
        sessions[index].updatedAt = Date()
        saveSession(sessions[index])
        DebugLogger.shared.info("SESSION", "세션 이름 변경: \(trimmed)")
    }

    // MARK: - 메시지 뮤테이션 헬퍼 (캐시 무효화 일원화)

    /// 세션을 ID로 조회해 메시지 배열을 안전하게 갱신하고 currentSession 캐시를 무효화한다.
    /// 전송 중 세션 삭제/전환에도 인덱스 크래시 없이 동작한다.
    private func mutateMessages(of sessionID: UUID, _ transform: (inout [ChatMessage]) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        transform(&sessions[index].messages)
        _cachedSession = nil
    }

    /// 스트리밍 대상 어시스턴트 메시지의 내용을 갱신한다
    private func setAssistantContent(_ text: String, messageID: UUID, sessionID: UUID) {
        mutateMessages(of: sessionID) { msgs in
            if let i = msgs.firstIndex(where: { $0.id == messageID }) {
                msgs[i].content = text
            }
        }
    }

    /// 스트리밍 종료 처리 (정상/취소 공통)
    private func finishStreaming(messageID: UUID, sessionID: UUID, finalText: String? = nil) {
        mutateMessages(of: sessionID) { msgs in
            guard let i = msgs.firstIndex(where: { $0.id == messageID }) else { return }
            msgs[i].isStreaming = false
            if let finalText { msgs[i].content = finalText }
        }
    }

    /// 어시스턴트 메시지의 공급자/모델 식별자를 갱신 (429 폴백 시 전송 실모델 반영)
    private func setAssistantProviderModel(messageID: UUID, sessionID: UUID, model: AIModel) {
        mutateMessages(of: sessionID) { msgs in
            if let i = msgs.firstIndex(where: { $0.id == messageID }) {
                msgs[i].provider = model.provider
                msgs[i].modelID = model.id
            }
        }
    }

    /// 429 자동 폴백 안내를 어시스턴트 메시지 맨 앞에 삽입 (v3.4 T-162)
    private func prependAssistantNote(_ note: String, messageID: UUID, sessionID: UUID) {
        mutateMessages(of: sessionID) { msgs in
            guard let i = msgs.firstIndex(where: { $0.id == messageID }) else { return }
            msgs[i].content = note + "\n\n" + msgs[i].content
        }
    }

    /// HTTP 429(무료 티어 요청 한도/속도 초과) 오류인지 판별 — 자동 폴백 트리거 조건 (v3.4 T-162)
    private static func isRateLimitError(_ error: Error) -> Bool {
        if case AppError.serverError(let code, _) = error {
            return code == 429
        }
        return false
    }

    /// 전송 시작 시점의 세션 상태를 값으로 고정 (Task 내 인덱스 접근 제거)
    private struct SendContext {
        let sessionID: UUID
        let assistantMessageID: UUID
        let history: [ChatMessage]
        let model: AIModel
        /// 캐릭터별 샘플링 온도 (v2.2 T-111) — nil이면 공급자 기본값
        let temperature: Double?
    }

    // MARK: - 전송
    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading, let sessionID = currentSessionID else { return }
        // 이미지 첨부 시 비전 지원 모델인지 확인 (T-71)
        if !pendingAttachments.isEmpty && !selectedModel.supportsVision {
            attachmentNotice = "'\(selectedModel.displayName)' 모델은 이미지를 지원하지 않습니다. 비전 지원 모델(👁)로 변경해 주세요."
            DebugLogger.shared.warn("SEND", "[E-MAC-VALID-1001] 비전 미지원 모델에 이미지 첨부 시도: \(selectedModel.id)")
            return
        }
        attachmentNotice = nil
        inputText = ""
        let attachments = pendingAttachments
        pendingAttachments = []
        sendMessage(text, to: sessionID, attachments: attachments)
    }

    // MARK: - 이미지 첨부 (v1.8 T-71)

    /// 이미지 데이터 추가 — 다운스케일 후 대기열에 저장 (최대 4개)
    /// PNG/JPEG 원본은 축소 불필요 시 무손실 패스스루, 나머지(HEIC/TIFF 등)는 JPEG로 변환
    func addImageAttachment(_ rawData: Data, fileName: String? = nil) {
        guard pendingAttachments.count < Self.maxAttachments else {
            attachmentNotice = "이미지는 최대 \(Self.maxAttachments)개까지 첨부할 수 있습니다."
            return
        }
        guard let image = NSImage(data: rawData) else {
            attachmentNotice = "이미지를 불러올 수 없습니다."
            return
        }

        let pixelsWide = image.representations.first?.pixelsWide ?? 0
        let pixelsHigh = image.representations.first?.pixelsHigh ?? 0
        let needsResize = max(pixelsWide, pixelsHigh) > Int(Self.attachmentMaxDimension)

        let imageData: Data
        let mimeType: String

        if !needsResize && Self.isPNG(rawData) {
            imageData = rawData
            mimeType = "image/png"
        } else if !needsResize && Self.isJPEG(rawData) {
            imageData = rawData
            mimeType = "image/jpeg"
        } else if needsResize, let resized = Self.downscaledImageData(image, maxDimension: Self.attachmentMaxDimension) {
            imageData = resized
            mimeType = "image/jpeg"
        } else if let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
            imageData = jpeg
            mimeType = "image/jpeg"
        } else {
            attachmentNotice = "이미지 인코딩에 실패했습니다."
            return
        }

        let attachment = MessageAttachment(fileName: fileName, mimeType: mimeType, imageData: imageData)
        pendingAttachments.append(attachment)
        attachmentNotice = nil
        DebugLogger.shared.info("ATTACH", "이미지 첨부: \(imageData.count)바이트, mimeType=\(mimeType), 총 \(pendingAttachments.count)개")
    }

    func removeAttachment(id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
        if pendingAttachments.isEmpty { attachmentNotice = nil }
    }

    func clearAttachments() {
        pendingAttachments = []
        attachmentNotice = nil
    }

    /// 긴 변을 maxDimension으로 축소한 JPEG/PNG 데이터. 축소 불필요 시 nil
    static func downscaledImageData(_ image: NSImage, maxDimension: CGFloat) -> Data? {
        guard let rep = image.representations.first,
              max(rep.pixelsWide, rep.pixelsHigh) > Int(maxDimension) else { return nil }
        let scale = maxDimension / CGFloat(max(rep.pixelsWide, rep.pixelsHigh))
        let newSize = NSSize(width: CGFloat(rep.pixelsWide) * scale, height: CGFloat(rep.pixelsHigh) * scale)
        let target = NSImage(size: newSize)
        target.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        target.unlockFocus()
        guard let tiff = target.tiffRepresentation,
              let result = NSBitmapImageRep(data: tiff) else { return nil }
        return result.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }

    private static func isPNG(_ data: Data) -> Bool {
        data.starts(with: [0x89, 0x50, 0x4E, 0x47])
    }

    private static func isJPEG(_ data: Data) -> Bool {
        data.starts(with: [0xFF, 0xD8])
    }

    /// 빠른 대화 패널 전송 — 패널 세션 대상 (메인 창 선택은 유지)
    func sendQuick(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading, let sessionID = quickSessionID else { return }
        sendMessage(text, to: sessionID)
    }

    /// AI 요청 이력 조립 — 실패 자리표시자(⚠️) 어시스턴트 메시지 제외 (v2.1 T-104)
    /// 모델이 과거 에러 문구를 읽고 "내가 고장났다"고 착각해 사과문을 생성하는 것을 방지
    static func effectiveHistory(from messages: [ChatMessage]) -> [ChatMessage] {
        let filtered = messages.filter { !($0.role == .assistant && $0.content.hasPrefix("⚠️")) }
        if filtered.count != messages.count {
            DebugLogger.shared.warn("SEND", "[CONTEXT] 에러 자리표시자 \(messages.count - filtered.count)개 요청 이력에서 제외")
        }
        return filtered
    }

    /// 메인 입력창·빠른 대화 패널 공통 전송 코어
    func sendMessage(_ text: String, to sessionID: UUID, attachments: [MessageAttachment] = [], reuseLastUser: Bool = false) {
        guard !text.isEmpty, !isLoading,
              let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else {
            // 조용한 차단은 재현 디버깅을 어렵게 한다 — 차단 사유 반드시 기록 (v2.1 T-104)
            let state = text.isEmpty ? "빈 입력" : "있음"
            DebugLogger.shared.warn("SEND", "전송 차단: text=\(state), isLoading=\(isLoading), sessionFound=\(sessions.contains { $0.id == sessionID })")
            return
        }

        DebugLogger.shared.info("SEND", "메시지 전송 시작: \(text.prefix(50))...")
        DebugLogger.shared.info("SEND", "모델: \(selectedModel.id) | 공급자: \(selectedModel.provider.rawValue)\(attachments.isEmpty ? "" : " | 이미지 \(attachments.count)개")")

        // 미드스위치 재전송(reuseLastUser)이면 마지막 사용자 메시지를 새로 추가하지 않고 재사용 (T-207)
        if !reuseLastUser {
            let userMessage = ChatMessage(role: .user, content: text, attachments: attachments.isEmpty ? nil : attachments)
            sessions[sessionIndex].messages.append(userMessage)
        }
        isLoading = true

        // 새 세션이면 제목 자동 설정 — 임시 접두사 + 보조 모델 LLM 제목 (v2.3 T-118)
        // 인사말이 있으면 count 2이므로 <= 2 조건
        if sessions[sessionIndex].title == "새 대화" && sessions[sessionIndex].messages.count <= 2 {
            let short = String(text.prefix(30))
            let provisional = short + (text.count > 30 ? "…" : "")
            sessions[sessionIndex].title = provisional
            generateTitle(sessionID: sessions[sessionIndex].id, provisional: provisional, userText: text)
        }

        // 스트리밍 컨텍스트를 값으로 고정 — Task 내 세션 인덱스/모델 재조회 제거
        let assistantMessage = ChatMessage(
            role: .assistant,
            content: "",
            provider: selectedModel.provider,
            modelID: selectedModel.id,
            isStreaming: true
        )
        let ctx = SendContext(
            sessionID: sessions[sessionIndex].id,
            assistantMessageID: assistantMessage.id,
            history: Self.effectiveHistory(from: sessions[sessionIndex].messages),
            model: selectedModel,
            temperature: nil
        )
        mutateMessages(of: ctx.sessionID) { $0.append(assistantMessage) }
        streamingMessageID = assistantMessage.id
        mainStreamingSessionID = ctx.sessionID
        isLoading = true
        _ = streamManager.start(ctx.sessionID) { @MainActor [weak self] in
            guard let self else { return }

            // 429 자동 폴백 체인 (v3.4 T-162) — rate 한도 걸리면 다음 우선순위 무료 모델로 재시도
            var attemptModel = ctx.model
            var fallbackTrace: [String] = []
            let fallbackPool = ModelCatalog.freeFallbackCandidates(excluding: ctx.model)
            var attemptLimit = 1 + fallbackPool.count

            while attemptLimit > 0 {
                attemptLimit -= 1
                if attemptModel.provider != ctx.model.provider || attemptModel.id != ctx.model.id {
                    // 어시스턴트 메시지의 공급자/모델 식별자를 폴백 모델로 갱신 (폴백 시)
                    setAssistantProviderModel(messageID: ctx.assistantMessageID, sessionID: ctx.sessionID, model: attemptModel)
                    DebugLogger.shared.info("SEND", "429 폴백 → 모델 전환: \(attemptModel.provider.rawValue) \(attemptModel.id)")
                }

                let startTime = Date()
                // 스트리밍 UI 갱신 상태 — 쓰로틀링(30fps)·자동 스크롤(1초). 폴백 재시도마다 fresh 초기화
                final class StreamUIState {
                    var fullText = ""
                    var chunkCount = 0
                    var lastUpdate = Date()
                    var lastScroll = Date()
                }
                let ui = StreamUIState()
                // API 실측 usage 캡처 — 백그라운드 클로저에서 기록 후 완료 시 메시지에 부착 (v1.9 T-76)
                let usageCapture = UsageCapture()
                let onUsageCapture: (Int?, Int?) -> Void = { prompt, completion in
                    usageCapture.promptTokens = prompt
                    usageCapture.completionTokens = completion
                }
                do {
                DebugLogger.shared.info("SEND", "API 클라이언트 생성 중... (공급자: \(attemptModel.provider.rawValue))")
                let client = try AIClientFactory.client(provider: attemptModel.provider, modelID: attemptModel.id)
                DebugLogger.shared.info("SEND", "API 클라이언트 생성 완료. 스트리밍 시작...")

                let systemPrompt = self.buildSystemPrompt()
                DebugLogger.shared.debug("SEND", "시스템 프롬프트 길이: \(systemPrompt.count)자")

                // 웹 검색 (v1.8 T-72) — 마지막 사용자 메시지로 검색해 시스템 프롬프트에 주입
                var effectivePrompt = systemPrompt
                if self.webSearchForNextSend {
                    self.webSearchForNextSend = false
                    if let lastUser = ctx.history.last(where: { $0.role == .user }),
                       !lastUser.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        do {
                            let results = try await WebSearchService.search(
                                query: lastUser.content,
                                apiKey: AppSettings.shared.tavilyAPIKey
                            )
                            let block = WebSearchService.formatResults(results, query: lastUser.content)
                            if !block.isEmpty {
                                effectivePrompt += "\n\n" + block
                                DebugLogger.shared.info("WEBSEARCH", "시스템 프롬프트에 검색 결과 주입 (\(results.count)건)")
                            }
                        } catch {
                            DebugLogger.shared.error("WEBSEARCH", "[E-MAC-NET-1003] 검색 실패, 검색 없이 진행: \(error.localizedDescription)")
                        }
                    }
                }

                @MainActor func appendChunk(_ chunk: String) {
                    ui.fullText += chunk
                    ui.chunkCount += 1
                    let now = Date()
                    if now.timeIntervalSince(ui.lastUpdate) >= 0.033 || ui.chunkCount <= 3 {
                        self.setAssistantContent(ui.fullText, messageID: ctx.assistantMessageID, sessionID: ctx.sessionID)
                        ui.lastUpdate = now
                    }
                    if now.timeIntervalSince(ui.lastScroll) >= 1.0 {
                        NotificationCenter.default.post(name: .scrollToBottom, object: nil)
                        ui.lastScroll = now
                    }
                }

                // 도구 경로 (v2.4 T-120, T-204) — MCP 설정 활성 또는 에이전트 모드 시 진입
                var toolRecords: [ToolLoopService.ExecutionRecord] = []
                var usedToolPath = false
                let mcpOn = AppSettings.shared.mcpToolsEnabled
                let agentOn = AppSettings.shared.agentMode
                if (mcpOn || agentOn) && client.supportsTools {
                    let connections = await self.activeMCPConnections()
                    var tools = mcpOn ? self.toolDefinitions(from: connections) : []
                    if agentOn {
                        tools += Self.builtinToolDefinitions()
                    }
                    if !tools.isEmpty {
                        usedToolPath = true
                        DebugLogger.shared.info("SEND", "[TOOLS] 도구 루프 진입 — 도구 \(tools.count)개 (MCP:\(tools.contains { $0.name != "web_search" && $0.name != "fetch_url" && $0.name != "calculator" }), 에이전트:\(agentOn))")
                        toolRecords = try await ToolLoopService.run(
                            client: client,
                            messages: ctx.history,
                            systemPrompt: effectivePrompt,
                            temperature: ctx.temperature,
                            tools: tools,
                            connections: connections,
                            permissionGate: { call in await self.permissionGate(for: call) },
                            onText: { appendChunk($0) },
                            onToolRun: { record in
                                DebugLogger.shared.info("TOOLS", "도구 실행: \(record.toolName) (\(record.permissionDecision)) \(Int(record.durationMS ?? 0))ms")
                            },
                            onUsage: onUsageCapture)
                        NotificationCenter.default.post(name: .scrollToBottom, object: nil)
                    } else if agentOn {
                        DebugLogger.shared.info("SEND", "[TOOLS] 에이전트 모드지만 내장 도구 없음 — 일반 경로")
                    } else {
                        DebugLogger.shared.info("SEND", "[TOOLS] 연결된 MCP 서버 없음 — 일반 경로")
                    }
                }

                if !usedToolPath {
                    let stream = client.stream(messages: ctx.history, systemPrompt: effectivePrompt, temperature: ctx.temperature, onUsage: onUsageCapture)
                    for try await chunk in stream {
                        if Task.isCancelled {
                            DebugLogger.shared.info("SEND", "취소 감지 — 루프 탈출")
                            break
                        }
                        appendChunk(chunk)
                        if ui.chunkCount % 20 == 0 {
                            DebugLogger.shared.debug("SEND", "청크 수신: \(ui.chunkCount)개, 누적 \(ui.fullText.count)자")
                        }
                    }
                }
                // 최종 업데이트 (마지막 청크 반영 보장)
                self.setAssistantContent(ui.fullText, messageID: ctx.assistantMessageID, sessionID: ctx.sessionID)
                let elapsed = Date().timeIntervalSince(startTime) * 1000

                if Task.isCancelled {
                    DebugLogger.shared.info("SEND", "취소 완료: \(ui.fullText.count)자 수신됨 (\(Int(elapsed))ms)")
                    self.finishStreaming(messageID: ctx.assistantMessageID, sessionID: ctx.sessionID, finalText: ui.fullText)
                    streamingMessageID = nil
                    return
                }

                DebugLogger.shared.info("SEND", "응답 완료: \(ui.fullText.count)자, \(ui.chunkCount)개 청크, \(Int(elapsed))ms\(usedToolPath ? ", 도구 \(toolRecords.count)건" : "")")
                DebugLogger.shared.perf("SEND", "response_time=\(Int(elapsed))ms chunks=\(ui.chunkCount) chars=\(ui.fullText.count)")

                self.finishStreaming(messageID: ctx.assistantMessageID, sessionID: ctx.sessionID, finalText: ui.fullText)
                // 실행 카드 부착 — 도구 경로로 실행된 기록 (v2.4 T-120)
                if !toolRecords.isEmpty {
                    self.attachToolRuns(toolRecords, messageID: ctx.assistantMessageID, sessionID: ctx.sessionID)
                }
                if let p = usageCapture.promptTokens, let c = usageCapture.completionTokens {
                    self.attachTokenCounts(prompt: p, completion: c,
                                           messageID: ctx.assistantMessageID, sessionID: ctx.sessionID)
                    DebugLogger.shared.perf("SEND", "tokens prompt=\(p) completion=\(c)")
                } else {
                    DebugLogger.shared.debug("SEND", "usage 미보고 공급자 — 토큰 실측 없음")
                }
                streamingMessageID = nil
                if let idx = sessions.firstIndex(where: { $0.id == ctx.sessionID }) {
                    sessions[idx].updatedAt = Date()
                    saveSession(sessions[idx])
                }
                // 자동 기억 추출 — 정상 완료 시에만 (v2.2 T-112)
                self.maybeAutoExtractMemory(ctx: ctx)

                // 429 폴백 안내 — 폴백 경유해 정상 완료된 경우 어시스턴트 메시지 앞에 표기
                if let original = fallbackTrace.first {
                    let note = "⚠️ \(original) 요청이 너무 많아 \(attemptModel.provider.rawValue) \(attemptModel.displayName)로 전환되었습니다."
                    self.prependAssistantNote(note, messageID: ctx.assistantMessageID, sessionID: ctx.sessionID)
                    DebugLogger.shared.info("SEND", "429 폴백 완료 안내: \(note)")
                }
                break
            } catch {
                let elapsed = Date().timeIntervalSince(startTime) * 1000
                if Task.isCancelled {
                    DebugLogger.shared.info("SEND", "취소됨: \(error.localizedDescription) (\(Int(elapsed))ms)")
                    self.finishStreaming(messageID: ctx.assistantMessageID, sessionID: ctx.sessionID)
                    break
                }

                let isRateLimit = Self.isRateLimitError(error)
                let isCleanStart = ui.fullText.isEmpty
                if isRateLimit, isCleanStart, attemptLimit > 0, let nextPool = ModelCatalog.freeFallbackCandidates(excluding: attemptModel).first {
                    fallbackTrace.append("\(attemptModel.provider.rawValue) \(attemptModel.displayName)")
                    attemptModel = nextPool
                    DebugLogger.shared.info("SEND", "429 감지 — 다음 우선순위 모델로 재시도: \(nextPool.provider.rawValue) \(nextPool.id) (남은 시도 \(attemptLimit))")
                    continue
                }

                // 모델 EOL(410)/모델 없음(404) — 공급자 무관 자동 비활성화 + 사용자 안내
                let disabled = ModelCatalog.shared.disableUnavailableModel(error: error, model: ctx.model)
                let message = error.localizedDescription
                    + (disabled ? " (모델이 목록에서 자동 제외됨)" : "")

                DebugLogger.shared.error("SEND", "에러: \(message) (\(Int(elapsed))ms)")
                // 사용자에게 에러 표시
                self.finishStreaming(
                    messageID: ctx.assistantMessageID,
                    sessionID: ctx.sessionID,
                    finalText: "⚠️ \(message)"
                )
                streamingMessageID = nil
                break
            }
            } // while
            isLoading = false
            if mainStreamingSessionID == ctx.sessionID {
                mainStreamingSessionID = nil
            }
        }
    }

    // MARK: - 병렬 모델 비교 (T-201)

    /// 현재 대화 컨텍스트를 여러 모델에 나란히 발송한다.
    /// 대화 이력(effectiveHistory)을 통일 컨텍스트로 사용해 모든 래인이 같은 맥락에서 응답한다.
    /// 결과는 ComparisonService.results에 채워져 비교 오버레이가 렌더링한다.
    func runComparison(in sessionID: UUID) {
        guard !isComparing, !isLoading,
              let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }

        let models = ModelCatalog.shared.models.filter { selectedCompareModelIDs.contains($0.id) }
        guard !models.isEmpty else {
            DebugLogger.shared.warn("COMPARE", "[E-MAC-VALID-1004] 비교 실행 차단 — 선택된 모델 없음")
            return
        }

        DebugLogger.shared.info("COMPARE", "[FEATURE] 대화 병렬 비교 시작: 모델 \(models.count)개, 세션 이력 \(sessions[index].messages.count)개")
        let context = Self.effectiveHistory(from: sessions[index].messages)
        let systemPrompt = buildSystemPrompt()

        isComparing = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.comparisonService.run(
                context: context,
                systemPrompt: systemPrompt,
                params: self.compareParams,
                models: models)
            // 완료 후에도 오버레이를 유지한다 — 사용자가 결과를 보고
            // "이 답변으로 대화 계속"(채택) 또는 "취소"로 직접 닫기 전까지.
            // (isComparing 유지 → CompareOverlayView가 결과 그리드를 계속 표시)
        }
    }

    /// 비교 종료 — 선택한 래인의 응답을 이 세션의 어시스턴트 답변으로 확정해 대화에 남긴다.
    /// "이 답변으로 계속" 버튼에서 호출. 비교는 임시 오버레이로, 선택 결과만 히스토리에 반영된다.
    func adoptCompareLane(index: Int, in sessionID: UUID) {
        guard comparisonService.results.indices.contains(index),
              let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let lane = comparisonService.results[index]
        guard lane.error == nil else { return }

        mutateMessages(of: sessionID) { $0.append(Self.assistantMessage(fromLane: lane)) }
        sessions[sessionIndex].updatedAt = Date()
        saveSession(sessions[sessionIndex])
        DebugLogger.shared.info("COMPARE", "[FEATURE] 비교 래인 채택됨: \(lane.model.displayName), \(lane.text.count)자")

        // 비교 모델 재선택을 쉽게 — 세션 기본 모델 유지는 유지, 비교는 종료
        isComparing = false
    }

    /// 비교 래인을 세션에 확정될 어시스턴트 메시지로 변환 (순수 — T-201 테스트 대상)
    nonisolated static func assistantMessage(fromLane lane: ComparisonResult) -> ChatMessage {
        ChatMessage(
            role: .assistant,
            content: lane.text,
            provider: lane.model.provider,
            modelID: lane.model.id,
            isStreaming: false,
            promptTokens: lane.promptTokens,
            completionTokens: lane.completionTokens
        )
    }

    /// 비교 대상 모델 목록 (순서 보장)
    func selectedCompareModels() -> [AIModel] {
        ModelCatalog.shared.models.filter { selectedCompareModelIDs.contains($0.id) }
    }

    /// 비교 실행 후 초기화 — 비교 오버레이 종료
    func cancelComparison() {
        isComparing = false
        comparisonService.stopAll()
    }

    // MARK: - 스트리밍 중지
    func stopStreaming() {
        DebugLogger.shared.info("SEND", "사용자가 스트리밍 중지 요청")
        if let sessionID = mainStreamingSessionID {
            streamManager.stop(sessionID)
            mainStreamingSessionID = nil
        } else {
            streamManager.stopAll()
        }
        isLoading = false
        streamingMessageID = nil
        // 대기 중인 권한 프롬프트 해제 — continuation 유실 방지
        if pendingToolPermission != nil {
            respondToToolPermission(.denyOnce)
        }
    }

    // MARK: - 외부 호출 (글로벌 핫키에서 사용)
    func prefillInput(_ text: String) {
        inputText = text
    }

    /// 전송 가능 여부 (입력 있음 + 로딩 중 아님)
    var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    // MARK: - SwiftData 저장/로드

    // MARK: - 대화 Fork (v1.8 T-73)

    /// 지정 메시지 지점까지 히스토리를 복사해 새 분기 세션 생성
    /// 메시지 ID는 SwiftData @Attribute(.unique) 충돌 방지를 위해 새로 발급
    func forkSession(at messageID: UUID, from sessionID: UUID) {
        guard !isLoading, let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let source = sessions[index]
        guard let cutIndex = source.messages.firstIndex(where: { $0.id == messageID }) else { return }

        let copiedMessages = source.messages[...cutIndex].map { msg -> ChatMessage in
            ChatMessage(
                role: msg.role,
                content: msg.content,
                provider: msg.provider,
                modelID: msg.modelID,
                timestamp: msg.timestamp,
                isError: msg.isError,
                promptTokens: msg.promptTokens,
                completionTokens: msg.completionTokens,
                attachments: msg.attachments
            )
        }

        let forked = ChatSession(
            title: source.title + " (분기)",
            systemPrompt: source.systemPrompt,
            messages: Array(copiedMessages),
            currentModel: selectedModel,
            selectedSkills: source.selectedSkills,
            parentSessionID: source.id,
            forkedFromMessageID: messageID
        )

        sessions.insert(forked, at: sessions.index(after: index))
        currentSessionID = forked.id
        saveSession(forked)
        DebugLogger.shared.info("FORK", "[FEATURE] 세션 분기 실행됨: '\(source.title)' → '\(forked.title)', 메시지 \(copiedMessages.count)개 복사")
    }

    /// 포크 재실행 (T-207) — 분기 후 분기점의 마지막 질문을 현재 선택 모델로 자동 재전송(비교/재실행)
    func forkSessionAndRerun(at messageID: UUID, from sessionID: UUID) {
        guard !isLoading else {
            DebugLogger.shared.warn("FORK", "재실행 차단 — 응답 생성 중")
            return
        }
        guard let source = sessions.first(where: { $0.id == sessionID }) else { return }
        // 분기점까지 히스토리에서 마지막 사용자 메시지가 재전송 대상 (순수)
        guard let lastUser = Self.forkRerunProxy(in: source.messages, cutMessageID: messageID) else { return }
        forkSession(at: messageID, from: sessionID)
        let forkedID = currentSessionID ?? sessionID
        let text = lastUser.text
        let attachments = lastUser.attachments
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            // 포크 세션엔 이미 마지막 사용자 메시지가 복사돼 있으므로 재사용 (중복 append 방지)
            self?.sendMessage(text, to: forkedID, attachments: attachments, reuseLastUser: true)
        }
        DebugLogger.shared.info("FORK", "[FEATURE] 포크 재실행: '\(source.title)' 분기점에서 '\(text.prefix(40))…' 재전송")
    }

    private func saveSession(_ session: ChatSession) {
        SearchIndexService.shared.index(session) // 전역 검색 인덱스 동기화 (v1.9 T-77)

        // 기존 엔티티 찾기
        let id = session.id
        let descriptor = FetchDescriptor<ChatSessionEntity>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try? context.fetch(descriptor).first {
            // 업데이트
            existing.title = session.title
            existing.systemPrompt = session.systemPrompt
            existing.updatedAt = session.updatedAt
            existing.currentModelID = session.currentModel?.id
            existing.currentProviderRaw = session.currentModel?.provider.rawValue
            existing.selectedSkillsJSON = session.selectedSkills.isEmpty ? nil : (
                try? JSONEncoder().encode(session.selectedSkills)
            ).flatMap { String(data: $0, encoding: .utf8) }
            existing.parentSessionID = session.parentSessionID
            existing.forkedFromMessageID = session.forkedFromMessageID
            existing.isIncognito = session.isIncognito
            existing.archivedAt = session.archivedAt
            existing.deletedAt = session.deletedAt
            // 메시지 동기화 (diff upsert — 스트리밍 중 전체 삭제/재삽입 방지)
            var synced: [ChatMessageEntity] = []
            for message in session.messages {
                if let entity = existing.messages.first(where: { $0.id == message.id }) {
                    entity.content = message.content
                    entity.isError = message.isError
                    entity.promptTokens = message.promptTokens
                    entity.completionTokens = message.completionTokens
                    let attachmentsData: Data? = {
                        guard let attachments = message.attachments, !attachments.isEmpty else { return nil }
                        return try? JSONEncoder().encode(attachments)
                    }()
                    entity.attachmentsData = attachmentsData
                    synced.append(entity)
                } else {
                    let entity = ChatMessageEntity(from: message, session: existing)
                    context.insert(entity)
                    synced.append(entity)
                }
            }
            for entity in existing.messages where !session.messages.contains(where: { $0.id == entity.id }) {
                context.delete(entity)
            }
            existing.messages = synced
        } else {
            let entity = ChatSessionEntity(from: session)
            context.insert(entity)
        }
        try? context.save()
    }

    private func deleteSessionEntity(_ id: UUID) {
        let descriptor = FetchDescriptor<ChatSessionEntity>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try? context.fetch(descriptor).first {
            context.delete(existing)
            try? context.save()
        }
    }

    private func loadSessions() {
        let descriptor = FetchDescriptor<ChatSessionEntity>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        guard let entities = try? context.fetch(descriptor) else { return }
        sessions = entities.map { $0.toChatSession() }
        migrateLegacyPromptSnapshots()
    }

    /// v1.9 마이그레이션 — 이전 버전은 세션 systemPrompt에 전역+스킬 스냅샷을 저장했으나
    /// 미사용 필드였다. v1.9부터 오버라이드(페르소나) 전용으로 의미가 바뀌므로,
    /// 기존 세션의 스냅샷을 1회 비운다 (안 하면 오래된 스냅샷이 전역 설정을 덮어씀).
    private func migrateLegacyPromptSnapshots() {        let flag = "legacySessionPromptCleared"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        var migratedSessions: [ChatSession] = []
        for index in sessions.indices where !sessions[index].systemPrompt.isEmpty {
            sessions[index].systemPrompt = ""
            migratedSessions.append(sessions[index])
        }
        UserDefaults.standard.set(true, forKey: flag)
        if !migratedSessions.isEmpty {
            for session in migratedSessions {
                saveSession(session)
            }
            DebugLogger.shared.info("APP", "레거시 프롬프트 스냅샷 정리: \(migratedSessions.count)개 세션")
        }
    }
}
