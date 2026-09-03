import XCTest
@testable import AIModelTalk

/// v2.0 T-80 — 브레인스토밍 파싱/중복 필터 테스트
final class BrainstormTestsV20: XCTestCase {

    func testParseNumberedAndBulletedLines() {
        let raw = """
        좋은 아이디어들을 소개합니다.
        1. 첫 번째 아이디어
        2. 두 번째 아이디어
        - 세 번째 아이디어
        • 네 번째 아이디어

        이상입니다!
        """
        let ideas = BrainstormService.parseIdeas(from: raw)
        XCTAssertEqual(ideas.count, 4, "번호/불릿 줄만 채택 — 서론·맺음말 제거")
        XCTAssertEqual(ideas[0], "첫 번째 아이디어")
        XCTAssertEqual(ideas[3], "네 번째 아이디어")
    }

    func testFilterNewRemovesDuplicates() {
        let existing = [
            BrainstormIdea(text: "AI 플래시카드 앱"),
            BrainstormIdea(text: "음성 퀴즈 봇")
        ]
        let candidates = [
            "AI 플래시카드 앱",          // 정확 중복
            "ai   플래시카드앱",         // 공백 정규화 중복
            "스터디 그룹 매칭 서비스",     // 신규
            ""                           // 빈 값 제외
        ]
        let fresh = BrainstormService.filterNew(candidates, against: existing)
        XCTAssertEqual(fresh, ["스터디 그룹 매칭 서비스"])
    }

    func testAngleRotationCycles() {
        XCTAssertEqual(BrainstormService.angles.count, 6)
        XCTAssertFalse(BrainstormService.angles.contains(""))
    }
}
