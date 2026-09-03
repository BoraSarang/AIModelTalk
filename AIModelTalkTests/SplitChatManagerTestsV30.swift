import XCTest
@testable import AIModelTalk

/// SplitChatManager 분기 CRUD·병렬 스트리밍·정식 세션 저장 검증 (v3.0 T-130)
final class SplitChatManagerTestsV30: XCTestCase {

    // MARK: - 목 클라이언트

    private struct MockSplitClient: ChatClient {
        let chunks: [String]
        var supportsTools: Bool { false }

        func stream(messages: [ChatMessage], systemPrompt: String?,
                    onUsage: ((Int?, Int?) -> Void)?) -> AsyncThrowingStream<String, Error> {
            AsyncThrowingStream { continuation in
                for c in chunks { continuation.yield(c) }
                onUsage?(10, 20)
                continuation.finish()
            }
        }

        func rawStreamWithTools(messages: [ChatMessage], systemPrompt: String?, temperature: Double?,
                                tools: [LLMToolDefinition],
                                onUsage: ((Int?, Int?) -> Void)?) -> AsyncThrowingStream<ChatStreamEvent, Error> {
            AsyncThrowingStream { $0.finish() }
        }
    }

    @MainActor
    private func makeManager(chunks: [String] = ["안녕", "하세요"]) -> SplitChatManager {
        let manager = SplitChatManager()
        manager.clientFactory = { _, _ in MockSplitClient(chunks: chunks) }
        manager.importSessionHandler = { _ in } // 목 — 실제 저장소 미접촉
        return manager
    }

    /// 상태 폴링 대기 — 임의 sleep 없이 (AGENTS.min AI 테스트 규칙)
    @MainActor
    private func waitUntil(_ timeout: TimeInterval = 3,
                           _ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("조건 충족 대기 시간 초과", file: file, line: line)
    }

    // MARK: - 슬롯 CRUD

    @MainActor
    func testAddAndRemoveSlot() {
        let manager = makeManager()
        XCTAssertEqual(manager.slots.count, 0)

        let id = manager.addSlot(model: .init(id: "m1", provider: .openAI, displayName: "모델1"))
        XCTAssertEqual(manager.slots.count, 1)
        XCTAssertEqual(manager.slots[0].id, id)
        XCTAssertEqual(manager.slots[0].model.displayName, "모델1")

        manager.removeSlot(at: 0)
        XCTAssertEqual(manager.slots.count, 0)
    }

    @MainActor
    func testRemoveSlotInvalidIndexIgnored() {
        let manager = makeManager()
        manager.addSlot()
        manager.removeSlot(at: 5) // 범위 밖 — 크래시 없이 무시
        XCTAssertEqual(manager.slots.count, 1)
    }

    @MainActor
    func testSetModelUpdatesAndRefusesWhileLoading() {
        let manager = makeManager()
        manager.addSlot(model: .init(id: "a", provider: .openAI, displayName: "A"))
        let newModel = AIModel(id: "b", provider: .anthropic, displayName: "B")

        manager.setModel(newModel, at: 0)
        XCTAssertEqual(manager.slots[0].model, newModel)

        // 로딩 중이면 모델 변경 거부
        manager.slots[0].isLoading = true
        manager.setModel(.init(id: "c", provider: .gemini, displayName: "C"), at: 0)
        XCTAssertEqual(manager.slots[0].model, newModel)
    }

    // MARK: - 병렬 스트리밍

    @MainActor
    func testSendToAllStreamsToEverySlot() async {
        let manager = makeManager(chunks: ["헬로", "월드"])
        manager.addSlot(model: .init(id: "m1", provider: .openAI, displayName: "M1"))
        manager.addSlot(model: .init(id: "m2", provider: .anthropic, displayName: "M2"))

        manager.sendToAll(text: "질문")

        await waitUntil { !manager.slots.contains(where: { $0.isLoading }) }

        for slot in manager.slots {
            XCTAssertEqual(slot.messages.count, 2, "user + 어시스턴트(스트리밍 누적)")
            XCTAssertEqual(slot.messages[0].role, .user)
            XCTAssertEqual(slot.messages[0].content, "질문")
            XCTAssertEqual(slot.messages[1].role, .assistant)
            XCTAssertEqual(slot.messages[1].content, "헬로월드")
            XCTAssertEqual(slot.promptTokens, 10)
            XCTAssertEqual(slot.completionTokens, 20)
        }
    }

    @MainActor
    func testSendToSlotOnlyTargetsOneSlot() async {
        let manager = makeManager(chunks: ["독", "립"])
        manager.addSlot(model: .init(id: "m1", provider: .openAI, displayName: "M1"))
        manager.addSlot(model: .init(id: "m2", provider: .anthropic, displayName: "M2"))

        manager.sendToSlot("질문", at: 0)
        await waitUntil { !manager.slots[0].isLoading }

        // 대상 분기만 메시지 존재
        XCTAssertEqual(manager.slots[0].messages.count, 2)
        XCTAssertEqual(manager.slots[0].messages[1].content, "독립")
        XCTAssertEqual(manager.slots[1].messages.count, 0, "비대상 분기는 이력 없음")
    }

    @MainActor
    func testMCPMissingKeyShowsErrorInSlot() async {
        let manager = SplitChatManager()
        // factory가 throw → 에러 메시지 경로
        manager.clientFactory = { _, _ in throw AppError.missingKey(.openAI) }
        manager.addSlot(model: .init(id: "m1", provider: .openAI, displayName: "M1"))

        manager.sendToAll(text: "질문")
        await waitUntil { !manager.slots[0].isLoading }

        XCTAssertTrue(manager.slots[0].messages.last?.content.hasPrefix("⚠️") == true)
        XCTAssertEqual(manager.slots[0].messages.last?.isError, true)
    }

    @MainActor
    func testStopSlotOnlyStopsTarget() async {
        let manager = makeManager(chunks: ["A", "B", "C", "D"])
        manager.addSlot(model: .init(id: "m1", provider: .openAI, displayName: "M1"))
        manager.addSlot(model: .init(id: "m2", provider: .anthropic, displayName: "M2"))

        manager.sendToAll(text: "질문")

        // 두 분기 모두 로딩 시작 확인 후 대상만 중지
        await waitUntil { manager.slots.allSatisfy { $0.isLoading } }
        manager.stopSlot(at: 0)

        // 대상 분기 즉시 중지 상태
        XCTAssertFalse(manager.slots[0].isLoading)
        // 비대상 분기는 이어서 완료될 때까지 대기 (중단되지 않음)
        await waitUntil { !manager.slots[1].isLoading }
        XCTAssertEqual(manager.slots[1].messages.count, 2)
    }

    // MARK: - 정식 세션 저장

    @MainActor
    func testSaveToSessionBuildsChatSession() {
        let manager = SplitChatManager()
        var captured: ChatSession? = nil
        manager.importSessionHandler = { captured = $0 }
        manager.addSlot(model: .init(id: "m1", provider: .openAI, displayName: "스플릿모델"))
        manager.sendToSlot("Q", at: 0)
        // 실제 스트리밍 없이 구조만 — 사용자+어시스턴트 자리표시자 상태로 저장 시도
        manager.slots[0].messages[1].content = "답변"
        manager.slots[0].messages[1].isStreaming = false

        manager.saveToSession(at: 0)

        XCTAssertNotNil(captured)
        XCTAssertEqual(captured?.messages.count, 2)
        XCTAssertEqual(captured?.messages[1].content, "답변")
        XCTAssertEqual(captured?.currentModel?.displayName, "스플릿모델")
    }
}
