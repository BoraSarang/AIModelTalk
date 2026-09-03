import XCTest
import SwiftData
@testable import AIModelTalk

/// v1.8 T-73 — 대화 Fork 테스트 (인메모리 저장소로 ChatViewModel 격리)
@MainActor
final class ForkSessionTestsV18: XCTestCase {

    private var vm: ChatViewModel!
    private var container: ModelContainer!

    override func setUp() {
        super.setUp()
        let schema = Schema([ChatSessionEntity.self, ChatMessageEntity.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: [config])
        vm = ChatViewModel(context: ModelContext(container))
    }

    override func tearDown() {
        vm = nil
        container = nil
        super.tearDown()
    }

    private func makeSourceSession() -> ChatSession {
        var session = ChatSession(title: "원본 대화", systemPrompt: "테스트 프롬프트")
        session.messages = [
            ChatMessage(role: .user, content: "첫 번째 질문"),
            ChatMessage(role: .assistant, content: "첫 번째 답변"),
            ChatMessage(role: .user, content: "두 번째 질문"),
            ChatMessage(role: .assistant, content: "두 번째 답변")
        ]
        return session
    }

    /// init이 빈 저장소에 자동 생성한 기본 세션을 비우고 테스트용 원본만 남긴다
    private func installSource(_ source: ChatSession) {
        vm.sessions.removeAll()
        vm.sessions.append(source)
    }

    func testForkCopiesHistoryUpToMessage() {
        let source = makeSourceSession()
        installSource(source)

        // 두 번째 메시지(assistant) 지점에서 분기 → 2개 복사
        let forkAtID = source.messages[1].id
        vm.forkSession(at: forkAtID, from: source.id)

        XCTAssertEqual(vm.sessions.count, 2, "분기 세션이 추가됨")
        let forked = vm.sessions.last!
        XCTAssertNotEqual(forked.id, source.id)
        XCTAssertEqual(forked.title, "원본 대화 (분기)")
        XCTAssertEqual(forked.messages.count, 2)
        XCTAssertEqual(forked.messages[0].content, "첫 번째 질문")
        XCTAssertEqual(forked.messages[1].content, "첫 번째 답변")

        // 분기 메타데이터
        XCTAssertEqual(forked.parentSessionID, source.id)
        XCTAssertEqual(forked.forkedFromMessageID, forkAtID)

        // 선택 전환 확인
        XCTAssertEqual(vm.currentSessionID, forked.id)
    }

    func testForkAssignsNewMessageIDs() {
        let source = makeSourceSession()
        installSource(source)

        vm.forkSession(at: source.messages[0].id, from: source.id)
        let forked = vm.sessions.last!

        for copied in forked.messages {
            XCTAssertFalse(
                source.messages.contains { $0.id == copied.id },
                "복사된 메시지는 새 UUID여야 함 — SwiftData unique 충돌 방지"
            )
            XCTAssertTrue(source.messages.contains { $0.content == copied.content })
        }
    }

    func testForkWithInvalidMessageIDDoesNothing() {
        let source = makeSourceSession()
        installSource(source)

        vm.forkSession(at: UUID(), from: source.id) // 존재하지 않는 메시지
        XCTAssertEqual(vm.sessions.count, 1, "유효하지 않은 분기는 무시됨")
    }
}
