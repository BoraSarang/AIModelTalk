import XCTest
@testable import AIModelTalk

/// v2.1 T-104 — AI 요청 이력에서 에러 자리표시자 제외 검증
@MainActor
final class EffectiveHistoryTestsV21: XCTestCase {

    func testFiltersErrorPlaceholderAssistantMessages() {
        let messages: [AIModelTalk.ChatMessage] = [
            AIModelTalk.ChatMessage(role: .user, content: "질문 A"),
            AIModelTalk.ChatMessage(role: .assistant, content: "⚠️ Apple Intelligence 응답 생성에 실패했습니다."),
            AIModelTalk.ChatMessage(role: .user, content: "질문 B"),
            AIModelTalk.ChatMessage(role: .assistant, content: "정상 답변")
        ]
        let filtered = ChatViewModel.effectiveHistory(from: messages)
        XCTAssertEqual(filtered.count, 3, "⚠️ 자리표시자만 제외")
        XCTAssertFalse(filtered.contains { $0.content.hasPrefix("⚠️") })
        XCTAssertTrue(filtered.contains { $0.content == "정상 답변" }, "정상 응답은 유지")
    }

    func testKeepsUserMessagesContainingWarningEmoji() {
        // 사용자가 ⚠️를 입력한 경우는 제외 대상 아님 — 어시스턴트 역할만 필터
        let messages: [AIModelTalk.ChatMessage] = [
            AIModelTalk.ChatMessage(role: .user, content: "⚠️ 포함 질문"),
            AIModelTalk.ChatMessage(role: .assistant, content: "답변")
        ]
        let filtered = ChatViewModel.effectiveHistory(from: messages)
        XCTAssertEqual(filtered.count, 2)
    }
}
