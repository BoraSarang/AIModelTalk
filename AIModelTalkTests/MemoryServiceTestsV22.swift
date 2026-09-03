import XCTest
@testable import AIModelTalk

/// v2.2 T-112 — 자동 기억 엔진 테스트 (추출 프롬프트·파싱·중복제거·캡/eviction)
final class MemoryServiceTestsV22: XCTestCase {

    // MARK: - 트리거 판정

    func testShouldExtractEveryFourExchanges() {
        XCTAssertFalse(MemoryService.shouldExtract(userMessageCount: 0))
        XCTAssertFalse(MemoryService.shouldExtract(userMessageCount: 3))
        XCTAssertTrue(MemoryService.shouldExtract(userMessageCount: 4))
        XCTAssertFalse(MemoryService.shouldExtract(userMessageCount: 5))
        XCTAssertTrue(MemoryService.shouldExtract(userMessageCount: 8))
    }

    // MARK: - 프롬프트

    func testExtractionPromptContainsExistingAndTranscript() {
        let prompt = MemoryService.extractionPrompt(
            existing: ["표 정리 선호"],
            recentTranscript: "사용자: 앞으로 존댓말로\n캐릭터: 네 알겠습니다")

        XCTAssertTrue(prompt.contains("- 표 정리 선호"))
        XCTAssertTrue(prompt.contains("사용자: 앞으로 존댓말로"))
        XCTAssertTrue(prompt.contains("{\"memories\""))
    }

    func testExtractionPromptEmptyExisting() {
        let prompt = MemoryService.extractionPrompt(existing: [], recentTranscript: "대화")
        XCTAssertTrue(prompt.contains("(없음)"))
    }

    // MARK: - 파싱 (방어적 디코딩)

    func testParseNormalJSONObject() {
        let out = MemoryService.parseCandidates(#"{"memories": ["표 정리 선호", "고양이 키움"]}"#)
        XCTAssertEqual(out, ["표 정리 선호", "고양이 키움"])
    }

    func testParseCodeFencedJSON() {
        let out = MemoryService.parseCandidates("```json\n{\"memories\": [\"존댓말 사용\"]}\n```")
        XCTAssertEqual(out, ["존댓말 사용"])
    }

    func testParseObjectArrayForm() {
        // 일부 모델이 {"memories": [{"content": "..."}]} 형태로 출력하는 케이스
        let out = MemoryService.parseCandidates(#"{"memories": [{"content": "디자인 업무"}]}"#)
        XCTAssertEqual(out, ["디자인 업무"])
    }

    func testParseBareArrayFallback() {
        let out = MemoryService.parseCandidates(#"["첫 기억", "둘째 기억"]"#)
        XCTAssertEqual(out, ["첫 기억", "둘째 기억"])
    }

    func testParseJSONWithSurroundingNoise() {
        let out = MemoryService.parseCandidates("추출 결과입니다:\n{\"memories\": [\"회의는 화요일\"]}\n이상.")
        XCTAssertEqual(out, ["회의는 화요일"])
    }

    func testParseGarbageReturnsEmpty() {
        XCTAssertTrue(MemoryService.parseCandidates("기억할 것이 없습니다").isEmpty)
        XCTAssertTrue(MemoryService.parseCandidates("{broken json").isEmpty)
        XCTAssertTrue(MemoryService.parseCandidates("").isEmpty)
    }

    // MARK: - 중복 제거

    func testDeduplicateSubstringMatches() {
        let out = MemoryService.deduplicate(
            ["표 정리 선호", "사용자는 표 정리 선호", "  ", "새로운 사실"],
            existing: ["표 정리 선호"])
        XCTAssertEqual(out, ["새로운 사실"], "기존과 부분 포함 관계인 후보는 제외, 공백도 제외")
    }

    /// 조사 변형("선호"→"선호함") 같은 의미적 유사는 문자열 매칭 한계 — LLM 중복 판정에 위임(백로그)
    func testDeduplicateSubstringLimitation() {
        let out = MemoryService.deduplicate(
            ["사용자는 표 정리를 선호함"],
            existing: ["표 정리 선호"])
        XCTAssertEqual(out, ["사용자는 표 정리를 선호함"], "부분 문자열이 아니면 통과 — 문서화된 한계")
    }

    func testDeduplicateCandidateContainsExisting() {
        let out = MemoryService.deduplicate(["사용자 이름은 철수이며 개발자다"], existing: ["철수"])
        XCTAssertTrue(out.isEmpty, "후보가 기존을 포함해도 중복으로 제외")
    }

    // MARK: - 저장 적용 (캡 + eviction) — 전역 [MemoryItem] (v0.1.2)

    func testApplyingAddsAutoMemories() {
        let items: [MemoryItem] = []
        let result = MemoryService.applying(["기억1", "기억2"], to: items, now: Date())

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.isAuto && !$0.isPinned })
    }

    func testApplyingEvictsOldestUnpinnedBeyondCap() {
        let base = Date(timeIntervalSinceNow: -100_000)
        var items: [MemoryItem] = []
        for i in 0..<MemoryService.maxMemories {
            items.append(MemoryItem(content: "오래된\(i)", createdAt: base.addingTimeInterval(Double(i * 10))))
        }
        let result = MemoryService.applying(["새 기억"], to: items, now: Date())

        XCTAssertEqual(result.count, MemoryService.maxMemories, "상한 유지")
        XCTAssertFalse(result.contains { $0.content == "오래된0" }, "미핀 최오래된 항목 퇴출")
        XCTAssertTrue(result.contains { $0.content == "새 기억" })
    }

    func testApplyingProtectsPinnedFromEviction() {
        let base = Date(timeIntervalSinceNow: -100_000)
        // 전부 핀 — 퇴출 대상 없음 → 상한 초과 허용(핀 보호 우선)
        var items: [MemoryItem] = []
        for i in 0..<MemoryService.maxMemories {
            items.append(MemoryItem(content: "핀\(i)", createdAt: base.addingTimeInterval(Double(i * 10)), isPinned: true))
        }
        let result = MemoryService.applying(["새 기억"], to: items, now: Date())

        XCTAssertEqual(result.count, MemoryService.maxMemories + 1, "핀 보호로 초과 허용")
        XCTAssertTrue(result.contains { $0.content == "새 기억" })
    }
}
