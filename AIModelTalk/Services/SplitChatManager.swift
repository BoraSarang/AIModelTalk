import Foundation
import Combine

/// Split Chat 분기(슬롯) 하나의 런타임 상태 — 독립 이력/모델/로딩/스트리밍 대상 (v3.0 T-126~127)
struct SplitSlot: Identifiable {
    let id: UUID
    /// 분기별 모델 — 발송 시점에 고정, 이후 변경 가능
    var model: AIModel
    /// 독립 대화 이력 (연속 대화 지원)
    var messages: [ChatMessage]
    var isLoading: Bool
    var streamingMessageID: UUID?
    /// 실측 토큰 (v1.9 T-76 파이프라인 재사용)
    var promptTokens: Int = 0
    var completionTokens: Int = 0

    init(
        id: UUID = UUID(),
        model: AIModel,
        messages: [ChatMessage] = [],
        isLoading: Bool = false,
        streamingMessageID: UUID? = nil
    ) {
        self.id = id
        self.model = model
        self.messages = messages
        self.isLoading = isLoading
        self.streamingMessageID = streamingMessageID
    }

    /// 분기 메시지를 정식 세션으로 승격하기 위한 복사본 생성
    var asChatSession: ChatSession {
        ChatSession(
            title: "스플릿 채팅 · \(model.displayName)",
            messages: messages,
            currentModel: model
        )
    }
}

/// Split Chat(다중 모델 병렬 대화) 전용 매니저 (v3.0 T-126)
///
/// 기존 ComparisonService가 "단발 Q&A 병렬 비교"라면, 이 매니저는
/// **분기별 연속 대화**(독립 이력 유지) + **병렬 수신** + **정식 세션 저장**을 담당한다.
/// 스트리밍 작업 수명주기는 StreamManager(세션 키 = 슬롯 id)에게 위임해
/// 슬롯별 독립 취소·병렬 수신을 보장한다.
@MainActor
final class SplitChatManager: ObservableObject {
    static let shared = SplitChatManager()

    @Published var slots: [SplitSlot] = []
    /// 공유 입력 모드 — true면 모든 분기에 같은 텍스트 전송
    @Published var isSharedInput: Bool = true
    /// 공유 입력 필드 (공유 모드)
    @Published var sharedInput: String = ""

    /// 슬롯별 스트리밍 작업 수명주기 (병렬 수신 — T-002 StreamManager 재사용)
    private let streamManager = StreamManager()
    private let usageCaptures: [UUID: UsageCapture] = [:]

    /// 클라이언트 생성 주입점 — 테스트에서 목 대체 (기본: 실제 팩토리)
    var clientFactory: (Provider, String) throws -> ChatClient = { provider, modelID throws in
        try AIClientFactory.client(provider: provider, modelID: modelID)
    }
    /// 정식 세션 저장 주입점 — 테스트에서 목 대체 (기본: ChatViewModel.shared)
    var importSessionHandler: (ChatSession) -> Void = { session in
        ChatViewModel.shared.importSplitSession(session)
    }

    /// 현재 슬롯 수
    var slotCount: Int { slots.count }

    // MARK: - 슬롯 관리

    /// 새 분기 추가 — 기본 슬롯이 없으면 첫 모델로 초기화
    @discardableResult
    func addSlot(model: AIModel? = nil) -> UUID {
        let resolved = model ?? defaultModel()
        let slot = SplitSlot(model: resolved)
        slots.append(slot)
        DebugLogger.shared.info("SPLIT", "[FEATURE] 슬롯 추가: \(resolved.displayName) (총 \(slots.count)개)")
        return slot.id
    }

    /// 지정 인덱스 분기 제거 — 진행 중이면 취소
    func removeSlot(at index: Int) {
        guard slots.indices.contains(index) else { return }
        streamManager.stop(slots[index].id)
        slots.remove(at: index)
        DebugLogger.shared.info("SPLIT", "[FEATURE] 슬롯 제거 (인덱스 \(index), 총 \(slots.count)개)")
    }

    /// 분기 모델 변경 — 진행 중이면 무시 (스트리밍 중 모델 급변 방지)
    func setModel(_ model: AIModel, at index: Int) {
        guard slots.indices.contains(index), !slots[index].isLoading else { return }
        slots[index].model = model
    }

    // MARK: - 전송

    /// 공유 모드 기준 보낼 대상 — 모든 분기
    func sendToAll(text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !slots.isEmpty else { return }
        for index in slots.indices {
            stream(index: index, userText: text)
        }
    }

    /// 개별 분기 전송
    func sendToSlot(_ text: String, at index: Int) {
        guard slots.indices.contains(index),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        stream(index: index, userText: text)
    }

    /// 특정 분기 스트리밍 중지
    func stopSlot(at index: Int) {
        guard slots.indices.contains(index) else { return }
        let slotID = slots[index].id
        streamManager.stop(slotID)
        slots[index].isLoading = false
        slots[index].streamingMessageID = nil
        DebugLogger.shared.info("SPLIT", "슬롯 \(index) 스트리밍 중지")
    }

    // MARK: - 정식 세션 저장

    /// 지정 분기를 정식 세션으로 저장 — ChatViewModel에 주입 (v3.0 T-129)
    func saveToSession(at index: Int) {
        guard slots.indices.contains(index), !slots[index].messages.isEmpty else { return }
        let session = slots[index].asChatSession
        importSessionHandler(session)
        DebugLogger.shared.info("SPLIT", "[FEATURE] 스플릿 결과 정식 세션 저장: '\(session.title)' (\(session.messages.count)개 메시지)")
    }

    // MARK: - 스트리밍 코어 (슬롯별 병렬)

    private func stream(index: Int, userText: String) {
        guard slots.indices.contains(index), !slots[index].isLoading else { return }

        let slotID = slots[index].id
        let model = slots[index].model

        // 사용자 메시지 + 빈 어시스턴트 메시지 추가
        let userMessage = ChatMessage(role: .user, content: userText)
        slots[index].messages.append(userMessage)
        let assistant = ChatMessage(
            role: .assistant,
            content: "",
            provider: model.provider,
            modelID: model.id,
            isStreaming: true
        )
        slots[index].messages.append(assistant)
        slots[index].isLoading = true
        slots[index].streamingMessageID = assistant.id

        // StreamManager에 슬롯 id 키로 등록 — 동일 슬롯 재발송 시 이전 작업 취소 + 병렬 독립 보장
        _ = streamManager.start(slotID) { @MainActor [weak self] in
            guard let self else { return }
            await self.run(slotID: slotID, index: index, model: model, assistantID: assistant.id)
        }
    }

    private func run(slotID: UUID, index: Int, model: AIModel, assistantID: UUID) async {
        guard let client = try? clientFactory(model.provider, model.id) else {
            setSlotError(index: index, assistantID: assistantID,
                         message: "[E-MAC-KEY-1001] \(model.provider.rawValue) API 키가 없습니다.")
            finishStreaming(index: index, assistantID: assistantID)
            return
        }

        let capture = UsageCapture()
        guard slots.indices.contains(index) else { return }
        let history = slots[index].messages.map { $0 }
        do {
            let stream = client.stream(messages: history, systemPrompt: nil) { prompt, completion in
                capture.promptTokens = prompt
                capture.completionTokens = completion
            }
            for try await chunk in stream {
                if Task.isCancelled { break }
                appendChunk(chunk, to: assistantID, at: index)
            }
            setAssistantFinal(index: index, assistantID: assistantID)
            slots[index].isLoading = false
            slots[index].streamingMessageID = nil
            if index < slots.count {
                slots[index].promptTokens += capture.promptTokens ?? 0
                slots[index].completionTokens += capture.completionTokens ?? 0
            }
            DebugLogger.shared.perf("SPLIT", "슬롯 완료: \(model.id) tokens=\(capture.promptTokens ?? 0)/\(capture.completionTokens ?? 0)")
        } catch let error as AppError {
            setSlotError(index: index, assistantID: assistantID,
                         message: "[\(error.errorCode)] \(error.localizedDescription ?? "")")
            finishStreaming(index: index, assistantID: assistantID)
        } catch {
            setSlotError(index: index, assistantID: assistantID, message: "알 수 없는 오류")
            finishStreaming(index: index, assistantID: assistantID)
        }
    }

    // MARK: - 메시지 변형 헬퍼

    private func appendChunk(_ chunk: String, to messageID: UUID, at index: Int) {
        guard slots.indices.contains(index) else { return }
        if let i = slots[index].messages.firstIndex(where: { $0.id == messageID }) {
            slots[index].messages[i].content += chunk
        }
    }

    private func setAssistantFinal(index: Int, assistantID: UUID) {
        guard slots.indices.contains(index) else { return }
        if let i = slots[index].messages.firstIndex(where: { $0.id == assistantID }) {
            slots[index].messages[i].isStreaming = false
        }
    }

    private func setSlotError(index: Int, assistantID: UUID, message: String) {
        guard slots.indices.contains(index) else { return }
        if let i = slots[index].messages.firstIndex(where: { $0.id == assistantID }) {
            slots[index].messages[i].content = "⚠️ \(message)"
            slots[index].messages[i].isError = true
            slots[index].messages[i].isStreaming = false
        }
    }

    private func finishStreaming(index: Int, assistantID: UUID) {
        guard slots.indices.contains(index) else { return }
        slots[index].isLoading = false
        slots[index].streamingMessageID = nil
    }

    private func defaultModel() -> AIModel {
        ModelCatalog.primaryFallbackModel()
    }
}
