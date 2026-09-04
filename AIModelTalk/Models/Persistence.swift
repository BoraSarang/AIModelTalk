import Foundation
import SwiftData

@Model final class ChatSessionEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var systemPrompt: String
    var createdAt: Date
    var updatedAt: Date
    var currentModelID: String?
    var currentProviderRaw: String?
    var selectedSkillsJSON: String?
    var parentSessionID: UUID?
    var forkedFromMessageID: UUID?
    var isIncognito: Bool = false
    var archivedAt: Date?
    var deletedAt: Date?
    var themeID: String?
    @Relationship(deleteRule: .cascade, inverse: \ChatMessageEntity.session)
    var messages: [ChatMessageEntity]

    init(id: UUID = UUID(), title: String, systemPrompt: String, createdAt: Date, updatedAt: Date, currentModelID: String? = nil, currentProviderRaw: String? = nil, selectedSkillsJSON: String? = nil, parentSessionID: UUID? = nil, forkedFromMessageID: UUID? = nil, isIncognito: Bool = false, archivedAt: Date? = nil, deletedAt: Date? = nil, themeID: String? = nil, messages: [ChatMessageEntity] = []) {
        self.id = id
        self.title = title
        self.systemPrompt = systemPrompt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.currentModelID = currentModelID
        self.currentProviderRaw = currentProviderRaw
        self.selectedSkillsJSON = selectedSkillsJSON
        self.parentSessionID = parentSessionID
        self.forkedFromMessageID = forkedFromMessageID
        self.isIncognito = isIncognito
        self.archivedAt = archivedAt
        self.deletedAt = deletedAt
        self.themeID = themeID
        self.messages = messages
    }

    convenience init(from session: ChatSession) {
        let skillsJSON = session.selectedSkills.isEmpty ? nil : (
            try? JSONEncoder().encode(session.selectedSkills)
        ).flatMap { String(data: $0, encoding: .utf8) }

        let messageEntities = session.messages.map { ChatMessageEntity(from: $0, session: nil) }
        self.init(
            id: session.id,
            title: session.title,
            systemPrompt: session.systemPrompt,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt,
            currentModelID: session.currentModel?.id,
            currentProviderRaw: session.currentModel?.provider.rawValue,
            selectedSkillsJSON: skillsJSON,
            parentSessionID: session.parentSessionID,
            forkedFromMessageID: session.forkedFromMessageID,
            isIncognito: session.isIncognito,
            archivedAt: session.archivedAt,
            deletedAt: session.deletedAt,
            themeID: session.themeID,
            messages: messageEntities
        )
        for msg in messageEntities {
            msg.session = self
        }
    }

    @MainActor func toChatSession() -> ChatSession {
        let model: AIModel? = {
            guard let id = currentModelID, let providerRaw = currentProviderRaw,
                  let provider = Provider(rawValue: providerRaw) else { return nil }
            return ModelCatalog.shared.model(id: id, provider: provider)
        }()
        let sortedMessages = messages
            .sorted { $0.timestamp < $1.timestamp }
            .map { $0.toChatMessage() }
        let skills: [SkillInfo] = {
            guard let json = selectedSkillsJSON,
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([SkillInfo].self, from: data) else { return [] }
            return decoded
        }()
        return ChatSession(
            id: id,
            title: title,
            systemPrompt: systemPrompt,
            messages: sortedMessages,
            currentModel: model,
            selectedSkills: skills,
            createdAt: createdAt,
            updatedAt: updatedAt,
            parentSessionID: parentSessionID,
            forkedFromMessageID: forkedFromMessageID,
            isIncognito: isIncognito,
            archivedAt: archivedAt,
            deletedAt: deletedAt,
            themeID: themeID
        )
    }
}

@Model final class ChatMessageEntity {
    @Attribute(.unique) var id: UUID
    var roleRaw: String
    var content: String
    var providerRaw: String?
    var modelID: String?
    var timestamp: Date
    var isError: Bool
    var promptTokens: Int?
    var completionTokens: Int?
    var attachmentsData: Data?
    /// MCP 도구 실행 카드 (v2.4 T-120) — [ExecutionRecord] JSON
    var toolRunsData: Data?
    var session: ChatSessionEntity?

    init(id: UUID = UUID(), roleRaw: String, content: String, providerRaw: String? = nil, modelID: String? = nil, timestamp: Date, isError: Bool = false, promptTokens: Int? = nil, completionTokens: Int? = nil, attachmentsData: Data? = nil, toolRunsData: Data? = nil, session: ChatSessionEntity? = nil) {
        self.id = id
        self.roleRaw = roleRaw
        self.content = content
        self.providerRaw = providerRaw
        self.modelID = modelID
        self.timestamp = timestamp
        self.isError = isError
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.attachmentsData = attachmentsData
        self.toolRunsData = toolRunsData
        self.session = session
    }

    convenience init(from message: ChatMessage, session: ChatSessionEntity?) {
        let attachmentsData: Data? = {
            guard let attachments = message.attachments, !attachments.isEmpty else { return nil }
            return try? JSONEncoder().encode(attachments)
        }()
        let toolRunsData: Data? = {
            guard let runs = message.toolRuns, !runs.isEmpty else { return nil }
            return try? JSONEncoder().encode(runs)
        }()
        self.init(
            id: message.id,
            roleRaw: message.role.rawValue,
            content: message.content,
            providerRaw: message.provider?.rawValue,
            modelID: message.modelID,
            timestamp: message.timestamp,
            isError: message.isError,
            promptTokens: message.promptTokens,
            completionTokens: message.completionTokens,
            attachmentsData: attachmentsData,
            toolRunsData: toolRunsData,
            session: session
        )
    }

    func toChatMessage() -> ChatMessage {
        let role = ChatRole(rawValue: roleRaw) ?? .user
        let provider = providerRaw.flatMap { Provider(rawValue: $0) }
        let attachments: [MessageAttachment]? = attachmentsData.flatMap {
            try? JSONDecoder().decode([MessageAttachment].self, from: $0)
        }
        let toolRuns: [ToolLoopService.ExecutionRecord]? = toolRunsData.flatMap {
            try? JSONDecoder().decode([ToolLoopService.ExecutionRecord].self, from: $0)
        }
        return ChatMessage(
            id: id,
            role: role,
            content: content,
            provider: provider,
            modelID: modelID,
            timestamp: timestamp,
            isError: isError,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            attachments: attachments,
            toolRuns: toolRuns
        )
    }
}
