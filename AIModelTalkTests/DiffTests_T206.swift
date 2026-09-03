import XCTest
@testable import AIModelTalk

final class DiffTests_T206: XCTestCase {
    func testDiffIdenticalTexts() {
        let d = ComparisonService.textDiff(before: "a\nb", after: "a\nb")
        XCTAssertEqual(d.map(\.kind), [.same, .same])
    }

    func testDiffAddedLines() {
        let d = ComparisonService.textDiff(before: "a", after: "a\nb")
        XCTAssertEqual(d.map(\.kind), [.same, .added])
        XCTAssertEqual(d.map(\.text), ["a", "b"])
    }

    func testDiffRemovedLines() {
        let d = ComparisonService.textDiff(before: "a\nb", after: "a")
        XCTAssertEqual(d.map(\.kind), [.same, .removed])
    }

    func testDiffReorderingKeepsLCS() {
        let d = ComparisonService.textDiff(before: "x\ny\nz", after: "y\nx\nz")
        // LCS 기반: 공통 라인이 최소 1개(\"x\") 보존되고 이동한 라인은 add/remove로 표시
        XCTAssertGreaterThanOrEqual(d.filter { $0.kind == .same }.count, 1)
        XCTAssertTrue(d.contains { $0.kind == .added })
        XCTAssertTrue(d.contains { $0.kind == .removed })
    }

    func testDiffEmptyAfter() {
        let d = ComparisonService.textDiff(before: "a\nb", after: "")
        // 빈 문자열은 [\"\"] 한 라인 — 대부분 제거로 표시
        XCTAssertTrue(d.contains { $0.kind == .removed })
        XCTAssertEqual(d.filter { $0.kind == .removed }.count, 2)
    }

    func testDiffEmptyBefore() {
        let d = ComparisonService.textDiff(before: "", after: "a\nb")
        XCTAssertTrue(d.contains { $0.kind == .added })
        XCTAssertEqual(d.filter { $0.kind == .added }.count, 2)
    }

    func testDiffSingleLineChanged() {
        let d = ComparisonService.textDiff(before: "안녕", after: "안녕하세요")
        // 서로 다른 라인 → added/removed 구성만 확인 (순서 무관)
        let kinds = Set(d.map(\.kind))
        XCTAssertEqual(kinds, Set([DiffKind.added, DiffKind.removed]))
    }
}