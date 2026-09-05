import XCTest
@testable import AIModelTalk

/// v0.3.3 — 후속질문 파싱 테스트 (T-337)
/// 번호·불릿·따옴표 제거, 최대 3개, 빈 줄 무시
final class FollowUpParseTestsV38: XCTestCase {

    func testNumberedList() {
        let out = ChatViewModel.parseFollowUps(from: "1. 오늘 뭐 했어?\n2. 도와줄까?\n3. 새로 시작할까?")
        XCTAssertEqual(out, ["오늘 뭐 했어?", "도와줄까?", "새로 시작할까?"])
    }

    func testBulletsAndQuotes() {
        let out = ChatViewModel.parseFollowUps(from: "- \"첫 번째?\"\n• 두 번째?\n* 세 번째?")
        XCTAssertEqual(out, ["첫 번째?", "두 번째?", "세 번째?"])
    }

    func testMaxThreeAndSkipsBlanks() {
        let out = ChatViewModel.parseFollowUps(from: "하나?\n\n둘?\n셋?\n넷?\n다섯?")
        XCTAssertEqual(out, ["하나?", "둘?", "셋?"])
    }

    func testEmptyReturnsEmpty() {
        XCTAssertEqual(ChatViewModel.parseFollowUps(from: ""), [])
        XCTAssertEqual(ChatViewModel.parseFollowUps(from: "\n  \n"), [])
    }

    func testLongLineTruncated() {
        let long = String(repeating: "가", count: 200)
        let out = ChatViewModel.parseFollowUps(from: long)
        XCTAssertEqual(out.count, 1)
        XCTAssertLessThanOrEqual(out[0].count, 120)
    }
}
