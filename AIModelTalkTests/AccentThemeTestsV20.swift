import XCTest
import SwiftUI
@testable import AIModelTalk

/// v2.0 T-82 — 액센트 테마 매핑 테스트
final class AccentThemeTestsV20: XCTestCase {

    func testAllCasesHaveUniqueDisplayNames() {
        let names = AccentTheme.allCases.map(\.displayName)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(names.first, "시스템")
    }

    func testSystemReturnsNilColor() {
        XCTAssertNil(AccentTheme.system.color, "시스템은 앱 기본 액센트 유지")
    }

    func testColoredThemesResolveAndFallback() {
        for theme in AccentTheme.allCases where theme != .system {
            XCTAssertNotNil(theme.color)
        }
        // 미지원 raw 값 폴백
        XCTAssertEqual(AccentTheme.theme("unknown-key"), .system)
        XCTAssertEqual(AccentTheme.theme(nil), .system)
        XCTAssertEqual(AccentTheme.theme("purple"), .purple)
    }
}
