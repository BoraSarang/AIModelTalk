import XCTest
import SwiftData
@testable import AIModelTalk

/// v1.8 T-70b — SwiftData 스키마 확장 필드 저장/복원 테스트 (인메모리 컨테이너 격리)
@MainActor
final class PersistenceSchemaV18Tests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() {
        super.setUp()
        let schema = Schema([ChatSessionEntity.self, ChatMessageEntity.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    private let sampleAttachment = MessageAttachment(
        fileName: "chart.png",
        mimeType: "image/png",
        imageData: Data("fake-png-bytes".utf8)
    )

    func testSessionForkAndSchemaFieldsRoundTrip() throws {
        let parentID = UUID()
        let forkedMessageID = UUID()

        let session = ChatSession(
            title: "포크 세션",
            parentSessionID: parentID,
            forkedFromMessageID: forkedMessageID
        )
        let entity = ChatSessionEntity(from: session)
        context.insert(entity)
        try context.save()

        let sessionID = entity.id
        let descriptor = FetchDescriptor<ChatSessionEntity>(
            predicate: #Predicate { $0.id == sessionID }
        )
        let fetched = try XCTUnwrap(try context.fetch(descriptor).first)
        XCTAssertEqual(fetched.parentSessionID, parentID)
        XCTAssertEqual(fetched.forkedFromMessageID, forkedMessageID)

        let restored = fetched.toChatSession()
        XCTAssertEqual(restored.parentSessionID, parentID)
        XCTAssertEqual(restored.forkedFromMessageID, forkedMessageID)
    }

    func testMessageTokensAndAttachmentsRoundTrip() throws {
        let message = ChatMessage(
            role: .assistant,
            content: "토큰/첨부 테스트",
            promptTokens: 120,
            completionTokens: 456,
            attachments: [sampleAttachment]
        )
        let session = ChatSession(title: "토큰 세션", messages: [message])
        let entity = ChatSessionEntity(from: session)
        context.insert(entity)
        try context.save()

        let descriptor = FetchDescriptor<ChatMessageEntity>()
        let fetched = try XCTUnwrap(try context.fetch(descriptor).first)

        XCTAssertEqual(fetched.promptTokens, 120)
        XCTAssertEqual(fetched.completionTokens, 456)
        XCTAssertNotNil(fetched.attachmentsData)

        let restored = fetched.toChatMessage()
        XCTAssertEqual(restored.promptTokens, 120)
        XCTAssertEqual(restored.completionTokens, 456)
        XCTAssertEqual(restored.attachments?.first?.fileName, "chart.png")
        XCTAssertEqual(restored.attachments?.first?.mimeType, "image/png")
        XCTAssertEqual(restored.attachments?.first?.imageData, Data("fake-png-bytes".utf8))
    }

    func testLegacyStyleMessageDecodesWithNilNewFields() throws {
        // 신규 필드 없이 생성한 메시지도 정상 저장/복원되는지 확인 (기존 데이터 호환)
        let message = ChatMessage(role: .user, content: "레거시 호환")
        XCTAssertNil(message.promptTokens)
        XCTAssertNil(message.attachments)

        let session = ChatSession(messages: [message])
        let entity = ChatSessionEntity(from: session)
        context.insert(entity)
        try context.save()

        let fetched = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessageEntity>()).first)
        XCTAssertNil(fetched.promptTokens)
        XCTAssertNil(fetched.completionTokens)
        XCTAssertNil(fetched.attachmentsData)
    }
}

// MARK: - v2.4 T-120: 도구 실행 카드 영속화

@MainActor
final class ToolRunsPersistenceV120Tests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() {
        super.setUp()
        let schema = Schema([ChatSessionEntity.self, ChatMessageEntity.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    func testToolRunsRoundTrip() throws {
        let runs = [
            ToolLoopService.ExecutionRecord(
                toolName: "search_docs",
                argumentsJSON: #"{"query":"swift"}"#,
                resultPreview: "문서 3건 발견",
                isError: false,
                durationMS: 123.4,
                permissionDecision: "allowed"
            ),
            ToolLoopService.ExecutionRecord(
                toolName: "run_report",
                argumentsJSON: "{}",
                resultPreview: "연결된 서버 없음",
                isError: true,
                durationMS: nil,
                permissionDecision: "denied"
            )
        ]
        let message = ChatMessage(role: .assistant, content: "검색 결과입니다.", toolRuns: runs)

        let entity = ChatMessageEntity(from: message, session: nil)
        context.insert(entity)
        try context.save()

        let descriptor = FetchDescriptor<ChatMessageEntity>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        let restored = try XCTUnwrap(fetched.first?.toChatMessage())
        let restoredRuns = try XCTUnwrap(restored.toolRuns)
        XCTAssertEqual(restoredRuns.count, 2)
        XCTAssertEqual(restoredRuns[0].toolName, "search_docs")
        XCTAssertEqual(restoredRuns[0].durationMS ?? 0, 123.4, accuracy: 0.01)
        XCTAssertFalse(restoredRuns[0].isError)
        XCTAssertTrue(restoredRuns[1].isError)
        XCTAssertEqual(restoredRuns[1].permissionDecision, "denied")
        XCTAssertNil(restoredRuns[1].durationMS)
    }

    func testMessageWithoutToolRunsStaysNil() throws {
        let message = ChatMessage(role: .assistant, content: "일반 응답")
        let entity = ChatMessageEntity(from: message, session: nil)
        context.insert(entity)
        try context.save()

        let restored = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessageEntity>()).first?.toChatMessage())
        XCTAssertNil(restored.toolRuns)
        XCTAssertNil(entity.toolRunsData)
    }
}
