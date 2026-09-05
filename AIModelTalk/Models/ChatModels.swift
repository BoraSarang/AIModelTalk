import Foundation

struct AIModel: Identifiable, Codable, Hashable {
    let id: String
    let provider: Provider
    let displayName: String
    var isFree: Bool = true
    var contextLimit: Int = 128_000

    var ttft: TimeInterval?
    var totalTime: TimeInterval?

    /// 이미지 입력(멀티모달) 지원 여부 — 모델 ID 휴리스틱 (v1.8 T-71)
    var supportsVision: Bool {
        switch provider {
        case .gemini:
            // Gemini 계열은 전 멀티모달, Gemma/학습용은 텍스트 전용
            return !id.lowercased().contains("gemma")
        case .appleIntelligence:
            return false
        case .custom:
            return true // 커스텀 엔드포인트는 사용자 판단에 위임
        case .anthropic:
            return true // 현행 Claude 라인업은 멀티모달 (v2.1 T-93)
        case .openRouter, .groq, .nvidia, .ollama, .openAI, .vercelGateway, .tokenRouter, .opencode, .deepseek:
            let lowerID = id.lowercased()
            return Self.visionKeywords.contains { lowerID.contains($0) }
        }
    }

    private static let visionKeywords = [
        "gpt-4o", "gpt-4.1", "claude-3", "claude-4", "gemini",
        "llama-4", "llama4", "pixtral", "vision", "llava", "-vl",
        "moondream", "minicpm-v", "bakllava"
    ]

    static func == (lhs: AIModel, rhs: AIModel) -> Bool {
        lhs.id == rhs.id && lhs.provider == rhs.provider
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(provider)
    }
}

enum ChatRole: String, Codable {
    case system
    case user
    case assistant
}

/// 세션 용도 모드 (v0.3.x 축4) — 채팅/이미지 생성/코딩
enum ChatMode: String, Codable, CaseIterable, Identifiable {
    case chat
    case image
    case coding

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chat: return "채팅"
        case .image: return "이미지"
        case .coding: return "코딩"
        }
    }

    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .image: return "photo.on.rectangle.angled"
        case .coding: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// 메시지 첨부 이미지 (T-71 Vision)
struct MessageAttachment: Identifiable, Codable, Hashable {
    let id: UUID
    var fileName: String?
    var mimeType: String
    var imageData: Data

    init(id: UUID = UUID(), fileName: String? = nil, mimeType: String, imageData: Data) {
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.imageData = imageData
    }
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    var role: ChatRole
    var content: String
    var provider: Provider?
    var modelID: String?
    var timestamp: Date
    var isStreaming: Bool
    var isError: Bool
    var promptTokens: Int?
    var completionTokens: Int?
    var attachments: [MessageAttachment]?
    /// MCP 도구 실행 카드 기록 (v2.4 T-120) — 어시스턴트 메시지에만 첨부
    var toolRuns: [ToolLoopService.ExecutionRecord]?

    init(id: UUID = UUID(), role: ChatRole, content: String, provider: Provider? = nil, modelID: String? = nil, timestamp: Date = Date(), isStreaming: Bool = false, isError: Bool = false, promptTokens: Int? = nil, completionTokens: Int? = nil, attachments: [MessageAttachment]? = nil, toolRuns: [ToolLoopService.ExecutionRecord]? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.provider = provider
        self.modelID = modelID
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.isError = isError
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.attachments = attachments
        self.toolRuns = toolRuns
    }
}

struct ChatSession: Identifiable, Codable {
    var id: UUID
    var title: String
    var systemPrompt: String
    var messages: [ChatMessage]
    var currentModel: AIModel?
    var selectedSkills: [SkillInfo]
    var createdAt: Date
    var updatedAt: Date
    var parentSessionID: UUID?
    var forkedFromMessageID: UUID?
    /// 인코그니토 — 이 대화는 기억을 사용하지 않고 새 기억도 만들지 않음
    var isIncognito: Bool = false
    /// 보관 시각 — nil이면 활성(대화 내역), 값 있으면 보관함. 휴지통(deletedAt)과 동시 설정 무시됨
    var archivedAt: Date?
    /// 휴지통 이동 시각 — nil이면 활성/보관, 값 있으면 휴지통
    var deletedAt: Date?
    /// 세션별 테마 ID — nil이면 글로벌 테마 사용
    var themeID: String? = nil
    /// 세션 용도 모드 (v0.3.x 축4) — 채팅/이미지/코딩
    var mode: ChatMode = .chat

    init(id: UUID = UUID(), title: String = "새 대화", systemPrompt: String = "", messages: [ChatMessage] = [], currentModel: AIModel? = nil, selectedSkills: [SkillInfo] = [], createdAt: Date = Date(), updatedAt: Date = Date(), parentSessionID: UUID? = nil, forkedFromMessageID: UUID? = nil, isIncognito: Bool = false, archivedAt: Date? = nil, deletedAt: Date? = nil, themeID: String? = nil, mode: ChatMode = .chat) {
        self.id = id
        self.title = title
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.currentModel = currentModel
        self.selectedSkills = selectedSkills
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.parentSessionID = parentSessionID
        self.forkedFromMessageID = forkedFromMessageID
        self.isIncognito = isIncognito
        self.archivedAt = archivedAt
        self.deletedAt = deletedAt
        self.themeID = themeID
        self.mode = mode
    }
}

/// 세션 토큰 실측 합계 — API가 보고한 usage 누적 (v1.9 T-76)
struct SessionTokens {
    let prompt: Int
    let completion: Int

    var total: Int { prompt + completion }
    var isEmpty: Bool { prompt == 0 && completion == 0 }

    static func total(for messages: [ChatMessage]) -> SessionTokens {
        let p = messages.compactMap(\.promptTokens).reduce(0, +)
        let c = messages.compactMap(\.completionTokens).reduce(0, +)
        return SessionTokens(prompt: p, completion: c)
    }

    /// "1.2k" 형식 축약
    static func compact(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }
}
