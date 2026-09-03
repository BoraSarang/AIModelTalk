import XCTest
@testable import AIModelTalk

/// v0.2.0 T-203 — 평가(Eval) 그리드 서비스 로직 테스트
@MainActor
final class EvalTests_T203: XCTestCase {

    private func makeModel(_ id: String) -> AIModel {
        AIModel(id: id, provider: .openRouter, displayName: id)
    }

    // MARK: - 셀 메트릭

    func testTokensPerSecondComputed() {
        var cell = EvalCell(prompt: "p", model: makeModel("m"))
        XCTAssertNil(cell.tokensPerSecond) // 미측정
        cell.totalTime = 2.0
        cell.completionTokens = 40
        XCTAssertEqual(cell.tokensPerSecond!, 20.0, accuracy: 0.0001)
    }

    func testTokensPerSecondNilWhenIncomplete() {
        var cell = EvalCell(prompt: "p", model: makeModel("m"))
        cell.completionTokens = 0
        cell.totalTime = 3.0
        XCTAssertNil(cell.tokensPerSecond)
    }

    func testStateHelpers() {
        XCTAssertTrue(EvalCell.EvalState.done.isDone)
        XCTAssertFalse(EvalCell.EvalState.done.isFailed)
        XCTAssertTrue(EvalCell.EvalState.failed("x").isFailed)
        XCTAssertFalse(EvalCell.EvalState.idle.isFailed)
        XCTAssertFalse(EvalCell.EvalState.run.isDone)
    }

    // MARK: - 필터·정렬

    func testFilterByModelAndPrompt() {
        let s = EvalService.shared
        let m1 = makeModel("a")
        let m2 = makeModel("b")
        s.cells = [
            EvalCell(prompt: "첫", model: m1),
            EvalCell(prompt: "둘", model: m1),
            EvalCell(prompt: "첫", model: m2),
        ]
        // 모델 필터
        var f = EvalService.EvalFilter()
        f.modelID = "a"
        let onlyA = s.filteredCells(filter: f)
        XCTAssertEqual(onlyA.count, 2)

        // 프롬프트 키워드 필터
        var kf = EvalService.EvalFilter()
        kf.promptContains = "첫"
        XCTAssertEqual(s.filteredCells(filter: kf).count, 2)
    }

    func testSortByTTFT() {
        let s = EvalService.shared
        let m = makeModel("m")
        s.cells = [
            EvalCell(prompt: "a", model: m, state: .done, ttft: 3, totalTime: 5),
            EvalCell(prompt: "b", model: m, state: .done, ttft: 0.5, totalTime: 2),
            EvalCell(prompt: "c", model: m, state: .done, ttft: 8, totalTime: 9),
        ]
        let sorted = s.filteredCells(sort: .ttft)
        XCTAssertEqual(sorted.map(\.prompt), ["b", "a", "c"])
    }

    // MARK: - 점수

    func testScoreClampedToOneToTen() {
        let s = EvalService.shared
        let id = UUID()
        s.setScore(cellID: id, value: 100)
        XCTAssertEqual(s.scores[id], 10)
        s.setScore(cellID: id, value: 0)
        XCTAssertEqual(s.scores[id], 1)
        s.setScore(cellID: id, value: nil)
        XCTAssertNil(s.scores[id])
    }

    // MARK: - 회귀 추적

    func testPreviousScoreFromOlderRecord() {
        let m = makeModel("m")
        // 검색과 동일한 기록 2개 삽입 (최신 = 0, 이전 = 1)
        let previous = EvalRunRecord(timestamp: Date().addingTimeInterval(-60), cells: [
            EvalRunRecord.CellRecord(prompt: "p", modelID: "m", providerRaw: "openRouter", score: 7)
        ])
        let latest = EvalRunRecord(timestamp: Date(), cells: [
            EvalRunRecord.CellRecord(prompt: "p", modelID: "m", providerRaw: "openRouter", score: 9)
        ])
        let records = [latest, previous]

        XCTAssertEqual(EvalService.latestScore(from: records, prompt: "p", modelID: "m", providerRaw: "openRouter"), 9)
        XCTAssertEqual(EvalService.previousScore(from: records, prompt: "p", modelID: "m", providerRaw: "openRouter"), 7)
    }

    func testPreviousScoreNilWhenOnlyOneRecord() {
        let m = makeModel("m")
        let records = [EvalRunRecord(timestamp: Date(), cells: [
            EvalRunRecord.CellRecord(prompt: "p", modelID: "m", providerRaw: "openRouter", score: 5)
        ])]
        XCTAssertNil(EvalService.previousScore(from: records, prompt: "p", modelID: "m", providerRaw: "openRouter"))
    }

    // MARK: - 내보내기

    func testExportCSVHasHeader() {
        let s = EvalService.shared
        let csv = s.exportCSV()
        XCTAssertTrue(csv.hasPrefix("프롬프트,모델,점수,TTFT"))
    }

    func testExportMarkdownRows() {
        let s = EvalService.shared
        let m = makeModel("m")
        s.prompts = ["p1"]
        s.cells = [EvalCell(prompt: "p1", model: m, state: .done, ttft: nil, totalTime: 1)]
        let md = s.exportMarkdown()
        XCTAssertTrue(md.contains("| 프롬프트 | m |"))
        XCTAssertTrue(md.contains("p1"))
    }
}