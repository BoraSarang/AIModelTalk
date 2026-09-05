import XCTest
@testable import AIModelTalk

/// v0.3.3 — 코드 하이라이트 엔진 선택 테스트 (T-320)
/// Splash 문법은 Swift 전용이라 Swift만 Splash, 나머지는 정규식 유지
final class SplashEngineTestsV36: XCTestCase {

    func testSwiftUsesSplash() {
        XCTAssertEqual(CodeHighlightProvider.engine(for: "swift"), .splash)
        XCTAssertEqual(CodeHighlightProvider.engine(for: "Swift"), .splash)
        XCTAssertEqual(CodeHighlightProvider.engine(for: "  swift  "), .splash)
    }

    func testOtherLanguagesUseRegex() {
        XCTAssertEqual(CodeHighlightProvider.engine(for: "python"), .regex)
        XCTAssertEqual(CodeHighlightProvider.engine(for: "javascript"), .regex)
        XCTAssertEqual(CodeHighlightProvider.engine(for: "typescript"), .regex)
        XCTAssertEqual(CodeHighlightProvider.engine(for: ""), .regex)
        XCTAssertEqual(CodeHighlightProvider.engine(for: "rust"), .regex)
    }
}
