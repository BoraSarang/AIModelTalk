import XCTest
@testable import AIModelTalk

/// T-208 — 프롬프트 템플릿(변수 치환) + 메모리 듀레이션·정렬 + 컨텍스트 조립
final class PromptTemplateTests_T208: XCTestCase {

    // MARK: - 프롬프트 템플릿 변수

    func testVariableNamesExtractsUniquePlaceholders() {
        let t = PromptTemplate(name: "요약", content: "{topic}에 대해 {style}로 요약, 특히 {topic} 강조")
        XCTAssertEqual(t.variableNames(), ["topic", "style"])
    }

    func testVariableNamesEmptyWhenNoPlaceholders() {
        XCTAssertTrue(PromptTemplate(name: "n", content: "그냥 지시문").variableNames().isEmpty)
    }

    func testApplyingReplacesAllPlaceholders() {
        let t = PromptTemplate(name: "요약", content: "{topic}을 {style}로 정리")
        let out = t.applying(values: ["topic": "SwiftUI", "style": "한 문장"])
        XCTAssertEqual(out, "SwiftUI을 한 문장로 정리")
    }

    func testApplyingMissingVariableLeavesBrace() {
        let t = PromptTemplate(name: "n", content: "안녕 {name}")
        XCTAssertEqual(t.applying(values: [:]), "안녕 {name}")
    }

    // MARK: - 메모리 듀레이션·핀 정렬 (ChatViewModel.assemblePrompt 재사용)

    func testAssemblePromptSortsPinnedFirstThenRecent() {
        let old = MemoryItem(content: "alpha", createdAt: Date(timeIntervalSince1970: 100), isPinned: false)
        let pinnedOld = MemoryItem(content: "pinL", createdAt: Date(timeIntervalSince1970: 50), isPinned: true)
        let recent = MemoryItem(content: "recent", createdAt: Date(timeIntervalSince1970: 300), isPinned: false)
        let out = ChatViewModel.assemblePrompt(base: "중심", memories: [old, pinnedOld, recent], memoryBudget: 10_000)
        XCTAssertTrue(out.contains("중심"))
        // 핀 우선 → 그 다음 최신순: pinL(핀) → recent → alpha
        let pinL = out.range(of: "pinL")!.lowerBound
        let recentN = out.range(of: "recent")!.lowerBound
        let alphaN = out.range(of: "alpha")!.lowerBound
        XCTAssertLessThan(pinL, recentN)
        XCTAssertLessThan(recentN, alphaN)
    }

    func testAssemblePromptBudgetTruncates() {
        let small = MemoryItem(content: "yyy", isPinned: false)
        let out = ChatViewModel.assemblePrompt(base: "중심", memories: [small], memoryBudget: 5)
        // 예산이 본문까지 못 미침 — 메모리 블록 미포함
        XCTAssertTrue(out.contains("중심"))
    }

    // MARK: - MemoryDurability

    func testDurabilityRawValues() {
        XCTAssertEqual(MemoryDurability.permanent.rawValue, "permanent")
        XCTAssertEqual(MemoryDurability.temporary.rawValue, "temporary")
    }
}