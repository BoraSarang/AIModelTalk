import XCTest
@testable import AIModelTalk

/// T-207 — 미드스위치 재전송·포크 재실행 대상 결정 순수 로직
final class MidSwitchForkTests_T207: XCTestCase {

    private func user(_ text: String) -> ChatMessage {
        ChatMessage(role: .user, content: text)
    }
    private func assistant(_ text: String) -> ChatMessage {
        ChatMessage(role: .assistant, content: text)
    }

    // MARK: - midSwitchProxy

    func testMidSwitchSelectsLastUserWhenAssistantPresent() {
        let msgs = [user("Q1"), assistant("A1"), user("Q2"), assistant("A2")]
        let aborted = msgs[3].id
        let r = ChatViewModel.midSwitchProxy(in: msgs, abortedAssistantID: aborted)
        XCTAssertEqual(r?.text, "Q2")
        XCTAssertEqual(r?.attachments, [])
    }

    func testMidSwitchWithAbortedEmptyAssistantFallsBackToLastUser() {
        let empty = ChatMessage(role: .assistant, content: "")
        let msgs = [user("Q1"), assistant("A1"), empty]
        let r = ChatViewModel.midSwitchProxy(in: msgs, abortedAssistantID: empty.id)
        XCTAssertEqual(r?.text, "Q1")
    }

    func testMidSwitchWithoutAbortedIDAndEmptyTrailing() {
        let msgs = [user("Q1"), assistant("A1"), user("Q2"), assistant("")]
        let r = ChatViewModel.midSwitchProxy(in: msgs, abortedAssistantID: nil)
        XCTAssertEqual(r?.text, "Q2")
    }

    func testMidSwitchNoUserReturnsNil() {
        let msgs = [assistant("A1"), assistant("A2")]
        XCTAssertNil(ChatViewModel.midSwitchProxy(in: msgs, abortedAssistantID: nil))
    }

    func testMidSwitchDoesNotMutateOriginal() {
        let msgs = [user("Q1"), assistant("A1"), user("Q2"), assistant("A2")]
        _ = ChatViewModel.midSwitchProxy(in: msgs, abortedAssistantID: msgs[3].id)
        XCTAssertEqual(msgs.count, 4) // 원본 불변
        XCTAssertEqual(msgs[3].content, "A2")
    }

    // MARK: - forkRerunProxy

    func testForkRerunFindsLastUserUpToCutpoint() {
        let msgs = [user("Q1"), assistant("A1"), user("Q2"), assistant("A2"), user("Q3")]
        let cut = msgs[2].id // Q2 자리
        let r = ChatViewModel.forkRerunProxy(in: msgs, cutMessageID: cut)
        XCTAssertEqual(r?.text, "Q2")
    }

    func testForkRerunCutAtAssistant() {
        let msgs = [user("Q1"), assistant("A1")]
        let r = ChatViewModel.forkRerunProxy(in: msgs, cutMessageID: msgs[1].id)
        XCTAssertEqual(r?.text, "Q1")
    }

    func testForkRerunUnknownCutReturnsNil() {
        let msgs = [user("Q1")]
        XCTAssertNil(ChatViewModel.forkRerunProxy(in: msgs, cutMessageID: UUID()))
    }

    func testForkRerunNoUserBeforeCutReturnsNil() {
        let msgs = [assistant("A1"), user("Q1")]
        XCTAssertNil(ChatViewModel.forkRerunProxy(in: msgs, cutMessageID: msgs[0].id))
    }
}