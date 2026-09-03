import XCTest
@testable import AIModelTalk

/// v1.9 T-87 — 비교 리포트 루브릭 파싱/순위 테스트
final class JudgeReportTestsV19: XCTestCase {

    private func makeResult(_ name: String, totalTime: Double?, error: String? = nil) -> AIModelTalk.ComparisonResult {
        var result = AIModelTalk.ComparisonResult(model: AIModel(id: name, provider: .nvidia, displayName: name))
        result.totalTime = totalTime
        result.error = error
        return result
    }

    private func makeScore(_ model: String, overall: Double) -> JudgeScore {
        JudgeScore(model: model, accuracy: 8, clarity: 7, depth: 6, koreanFluency: 9, speedFeel: 7, overall: overall, comment: "한줄평")
    }

    // MARK: - parseVerdict

    func testParsePlainJSON() {
        let json = """
        {"summary":"전반적으로 A가 우수","scores":[{"model":"A","accuracy":9,"clarity":8,"depth":7,"korean_fluency":9,"speed_feel":8,"overall":8.5,"comment":"완결적"},{"model":"B","accuracy":7,"clarity":7,"depth":8,"korean_fluency":6,"speed_feel":5,"overall":7,"comment":"느림"}],"winner":"A"}
        """
        let payload = ComparisonService.parseVerdict(json)
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.scores.count, 2)
        XCTAssertEqual(payload?.winner, "A")
        XCTAssertEqual(payload?.summary, "전반적으로 A가 우수")
        XCTAssertEqual(payload?.scores[1].koreanFluency, 6, "snake_case 키 디코딩")
    }

    func testParseFencedJSON() {
        let fenced = """
        ```json
        {"summary":"요약","scores":[{"model":"A","accuracy":8,"clarity":8,"depth":8,"korean_fluency":8,"speed_feel":8,"overall":8,"comment":"c"}],"winner":"A"}
        ```
        """
        let payload = ComparisonService.parseVerdict(fenced)
        XCTAssertNotNil(payload, "코드펜스 제거 후 파싱 성공")
        XCTAssertEqual(payload?.scores.first?.model, "A")
    }

    func testParseGarbageReturnsNil() {
        XCTAssertNil(AIModelTalk.ComparisonService.parseVerdict("죄송합니다. JSON 형식으로 답변드리겠습니다..."))
        // 빈 scores는 파싱 자체는 성공 — 폴백 판단은 호출부(runJudge)의 !scores.isEmpty가 담당 (v1.9 T-88)
        let payload = AIModelTalk.ComparisonService.parseVerdict("{\"scores\": [] }")
        XCTAssertEqual(payload?.scores.count, 0)
    }

    // MARK: - rankedResults

    func testRankingByOverallScore() {
        let a = makeResult("A", totalTime: 5.0) // 느리지만 점수 높음
        let b = makeResult("B", totalTime: 1.0) // 빠르지만 점수 낮음
        let scores = [makeScore("B", overall: 6), makeScore("A", overall: 8.5)]

        let ranked = ComparisonService.rankedResults([b, a], scores: scores)
        XCTAssertEqual(ranked.map(\.model.displayName), ["A", "B"], "점수 순 정렬 — 속도보다 품질 우선")
    }

    func testRankingFallbackByTimeErrorsLast() {
        let slow = makeResult("느린모델", totalTime: 4.0)
        let fast = makeResult("빠른모델", totalTime: 1.2)
        let failed = makeResult("실패모델", totalTime: nil, error: "HTTP 401")

        let ranked = ComparisonService.rankedResults([failed, slow, fast], scores: [])
        XCTAssertEqual(ranked.map(\.model.displayName), ["빠른모델", "느린모델", "실패모델"],
                       "채점 없으면 시간순 + 오류는 마지막")
    }

    func testUnmatchedScoreGoesLast() {
        let known = makeResult("A", totalTime: 2.0)
        let unknown = makeResult("미지모델", totalTime: 1.0) // 채점에 없는 모델
        let scores = [makeScore("A", overall: 7)]

        let ranked = ComparisonService.rankedResults([unknown, known], scores: scores)
        XCTAssertEqual(ranked.first?.model.displayName, "A")
        XCTAssertEqual(ranked.last?.model.displayName, "미지모델")
    }
}

// MARK: - v1.9 T-88 인덱스 매칭·방어적 디코딩

extension JudgeReportTestsV19 {

    func testPureIndexRejectsModelNamesWithDigits() {
        XCTAssertNil(AIModelTalk.ComparisonService.pureIndexValue("GPT-OSS-20B"), "모델명 속 숫자는 인덱스 아님")
        XCTAssertEqual(AIModelTalk.ComparisonService.pureIndexValue("1"), 1)
        XCTAssertEqual(AIModelTalk.ComparisonService.pureIndexValue("[2]"), 2)
        XCTAssertEqual(AIModelTalk.ComparisonService.pureIndexValue("#3"), 3)
        XCTAssertNil(AIModelTalk.ComparisonService.pureIndexValue("abc"))
    }

    func testIndexBasedScoreMatching() {
        let a = makeResult("A모델", totalTime: 2.0)
        let b = makeResult("B모델", totalTime: 3.0)
        // 판정자가 번호로 회신한 경우
        let scores = [
            makeScore("1", overall: 6),
            makeScore("[2]", overall: 9)
        ]
        let s0 = AIModelTalk.ComparisonService.scoreFor(a, index: 0, scores: scores)
        let s1 = AIModelTalk.ComparisonService.scoreFor(b, index: 1, scores: scores)
        XCTAssertEqual(s0?.overall, 6)
        XCTAssertEqual(s1?.overall, 9)

        let ranked = AIModelTalk.ComparisonService.rankedResults([a, b], scores: scores)
        XCTAssertEqual(ranked.map(\.model.displayName), ["B모델", "A모델"], "번호 기반 정렬 동작")
    }

    func testResilientDecodeMissingCommentAndCamelKeys() {
        let json = """
        {"scores":[{"model":"[1]","accuracy":8,"clarity":7,"depth":"6","koreanFluency":9,"overall":8}],"winner":"[1]"}
        """
        let payload = AIModelTalk.ComparisonService.parseVerdict(json)
        XCTAssertNotNil(payload, "comment 누락 + depth 문자열 + camelCase 키여도 디코딩 성공")
        XCTAssertEqual(payload?.scores.first?.comment, "")
        XCTAssertEqual(payload?.scores.first?.koreanFluency, 9)
        XCTAssertEqual(payload?.scores.first?.depth, 6)
        XCTAssertEqual(payload?.summary, "", "summary 누락 허용")
    }

    func testResolveWinnerByIndexAndName() {
        let a = makeResult("알파", totalTime: 1.0)
        let b = makeResult("베타", totalTime: 2.0)

        XCTAssertEqual(AIModelTalk.ComparisonService.resolveWinnerName("2", results: [a, b]), "베타")
        XCTAssertEqual(AIModelTalk.ComparisonService.resolveWinnerName("[1]", results: [a, b]), "알파")
        XCTAssertEqual(AIModelTalk.ComparisonService.resolveWinnerName("베타", results: [a, b]), "베타")
        XCTAssertNil(AIModelTalk.ComparisonService.resolveWinnerName("", results: [a, b]))
    }
}
