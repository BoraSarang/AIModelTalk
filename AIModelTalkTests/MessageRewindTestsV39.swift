import XCTest
import SwiftData
@testable import AIModelTalk

/// v0.3.3 — 메시지 되돌리기 테스트 (T-339)
/// retract 순수 함수 + 세션 잘라내기·기억 회수 통합
@MainActor
final class MessageRewindTestsV39: XCTestCase {

    // MARK: - retract (순수)

    func testRetractRemovesMatchingAutoMemory() {
        let items = [
            MemoryItem(content: "사용자는 78년생이다", isAuto: true),
            MemoryItem(content: "좋아하는 색은 파랑이다", isAuto: true),
        ]
        let out = MemoryService.retract(matchingDeletedText: "78년생이야", from: items)
        XCTAssertEqual(out.map(\.content), ["좋아하는 색은 파랑이다"])
    }

    func testRetractProtectsManualAndPinned() {
        var pinned = MemoryItem(content: "78년생이다", isAuto: true)
        pinned.isPinned = true
        let items = [
            pinned,
            MemoryItem(content: "78년생이다", isAuto: false),
        ]
        let out = MemoryService.retract(matchingDeletedText: "78년생", from: items)
        XCTAssertEqual(out.count, 2, "핀·수동 기억은 보호")
    }

    func testRetractEmptyDeletedKeepsAll() {
        let items = [MemoryItem(content: "무언가", isAuto: true)]
        XCTAssertEqual(MemoryService.retract(matchingDeletedText: "  ", from: items).count, 1)
    }

    // MARK: - rewindSession (통합)

    private var vm: ChatViewModel!
    private var container: ModelContainer!
    private var suite: UserDefaults!

    override func setUp() {
        super.setUp()
        let schema = Schema([ChatSessionEntity.self, ChatMessageEntity.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: [config])
        suite = UserDefaults(suiteName: "test-rewind-\(UUID().uuidString)")!
        vm = ChatViewModel(context: ModelContext(container), defaults: suite)
    }

    /// 격리 suite에 기억을 직접 심고 VM에 로드 (memoryItems는 private(set))
    private func seedMemories(_ items: [MemoryItem]) {
        suite.set(try! JSONEncoder().encode(items), forKey: "memories")
        vm.loadMemory()
    }

    override func tearDown() {
        vm = nil
        container = nil
        super.tearDown()
    }

    /// 3교환 중 2번째 사용자 메시지부터 되돌리기 → 이후 삭제 + 겹침 기억 회수
    @MainActor
    func testRewindTruncatesAndRetracts() {
        var session = ChatSession(title: "되돌리기 테스트")
        let u1 = ChatMessage(role: .user, content: "첫 질문")
        let a1 = ChatMessage(role: .assistant, content: "첫 답변")
        let u2 = ChatMessage(role: .user, content: "두 번째 질문")
        let a2 = ChatMessage(role: .assistant, content: "두 번째 답변 78년생")
        let u3 = ChatMessage(role: .user, content: "세 번째 질문")
        let a3 = ChatMessage(role: .assistant, content: "세 번째 답변")
        session.messages = [u1, a1, u2, a2, u3, a3]
        vm.sessions.append(session)
        vm.currentSessionID = session.id
        seedMemories([
            MemoryItem(content: "사용자는 78년생이다", isAuto: true),
            MemoryItem(content: "수동 메모 78년생", isAuto: false),
        ])

        vm.rewindSession(to: u2.id, from: session.id)

        let kept = vm.sessions.first(where: { $0.id == session.id })!.messages
        XCTAssertEqual(kept.map(\.id), [u1.id, a1.id, u2.id], "3번 이후 삭제, 2번까지 유지")
        XCTAssertEqual(vm.memoryItems.map(\.content), ["수동 메모 78년생"], "자동 기억만 회수")
        XCTAssertEqual(vm.inputText, "두 번째 질문", "잘라낸 메시지가 입력창에 (전송 없음)")
    }

    /// 마지막 메시지 되돌리기는 no-op
    @MainActor
    func testRewindAtLastMessageIsNoOp() {
        var session = ChatSession(title: "noop")
        let u1 = ChatMessage(role: .user, content: "질문")
        session.messages = [u1]
        vm.sessions.append(session)
        vm.rewindSession(to: u1.id, from: session.id)
        XCTAssertEqual(vm.sessions.first(where: { $0.id == session.id })!.messages.count, 1)
    }

    /// 어시스턴트 메시지 기준 되돌리기는 거부
    @MainActor
    func testRewindAtAssistantMessageIsNoOp() {
        var session = ChatSession(title: "noop2")
        let u1 = ChatMessage(role: .user, content: "질문")
        let a1 = ChatMessage(role: .assistant, content: "답변")
        session.messages = [u1, a1]
        vm.sessions.append(session)
        vm.rewindSession(to: a1.id, from: session.id)
        XCTAssertEqual(vm.sessions.first(where: { $0.id == session.id })!.messages.count, 2)
    }
}
