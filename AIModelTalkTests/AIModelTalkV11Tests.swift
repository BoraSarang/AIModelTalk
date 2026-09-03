import XCTest
@testable import AIModelTalk

final class TokenEstimatorTests: XCTestCase {

    func testEmptyString() {
        XCTAssertEqual(TokenEstimator.estimate(""), 0)
    }

    func testKoreanEstimation() {
        // 한글 5글자 ≈ 5 토큰
        let count = TokenEstimator.estimate("안녕하세요")
        XCTAssertGreaterThanOrEqual(count, 5)
        XCTAssertLessThanOrEqual(count, 7)
    }

    func testEnglishEstimation() {
        // 영문 단어는 대략 1.3배
        let count = TokenEstimator.estimate("hello world swift")
        XCTAssertGreaterThanOrEqual(count, 3)
        XCTAssertLessThanOrEqual(count, 5)
    }

    func testConversationIncludesOverhead() {
        let messages = [
            ChatMessage(role: .user, content: "안녕"),
            ChatMessage(role: .assistant, content: "반갑습니다")
        ]
        let total = TokenEstimator.estimateConversation(systemPrompt: "너는 도우미야", messages: messages)
        XCTAssertGreaterThan(total, 0)
    }
}

final class SessionExportTests: XCTestCase {

    func testJSONRoundTrip() throws {
        var session = ChatSession(title: "테스트 대화")
        session.messages = [
            ChatMessage(role: .user, content: "안녕"),
            ChatMessage(role: .assistant, content: "반갑습니다")
        ]
        session.systemPrompt = "시스템 프롬프트"

        let data = try SessionExportService.exportJSON(session)
        let imported = try SessionExportService.importJSON(data)

        XCTAssertEqual(imported.title, session.title)
        XCTAssertEqual(imported.messages.count, 2)
        XCTAssertEqual(imported.systemPrompt, session.systemPrompt)
        XCTAssertEqual(imported.id, session.id)
    }

    func testMarkdownExport() {
        let session = ChatSession(title: "마크다운 테스트")
        let md = SessionExportService.exportMarkdown(session)
        XCTAssertTrue(md.contains("# 마크다운 테스트"))
    }
}

@MainActor
final class UpdateCheckTests: XCTestCase {

    func testCurrentVersion() {
        let version = UpdateCheckService.shared.currentVersion
        XCTAssertFalse(version.isEmpty)
    }

    func testHasUpdateFalseWhenNoRelease() {
        // latestRelease가 없으면 업데이트 없음
        XCTAssertFalse(UpdateCheckService.shared.hasUpdate)
    }
}

final class ChatSessionTests: XCTestCase {

    func testIdMutableForImport() {
        var session = ChatSession(title: "원본")
        let oldID = session.id
        session.id = UUID()
        XCTAssertNotEqual(session.id, oldID)
    }
}
