import XCTest
@testable import AIModelTalk

/// v1.8 T-72 — 웹 검색 서비스 (포맷/가드) 테스트
final class WebSearchServiceTestsV18: XCTestCase {

    private let sampleResults = [
        WebSearchResult(title: "SwiftData 마이그레이션 가이드", url: "https://example.com/swiftdata", content: "SwiftData는 경량 마이그레이션을 지원합니다."),
        WebSearchResult(title: "Tavily API 문서", url: "https://docs.example.com/tavily", content: "POST /search 엔드포인트를 제공합니다.")
    ]

    func testFormatResultsIncludesHeaderAndSources() {
        let block = WebSearchService.formatResults(sampleResults, query: "swiftdata")
        XCTAssertTrue(block.contains("## 웹 검색 결과"))
        XCTAssertTrue(block.contains("\"swiftdata\""))
        XCTAssertTrue(block.contains("[1] SwiftData 마이그레이션 가이드"))
        XCTAssertTrue(block.contains("출처: https://example.com/swiftdata"))
        XCTAssertTrue(block.contains("[2] Tavily API 문서"))
    }

    func testFormatEmptyResultsReturnsEmptyString() {
        XCTAssertEqual(WebSearchService.formatResults([], query: "test"), "")
    }

    func testSearchRejectsMissingAPIKey() async {
        do {
            _ = try await WebSearchService.search(query: "테스트", apiKey: "")
            XCTFail("missingAPIKey 에러가 발생해야 합니다")
        } catch let error as WebSearchError {
            XCTAssertEqual(error.errorCode, "E-MAC-KEY-1003")
        } catch {
            XCTFail("예상치 못한 에러 타입: \(error)")
        }
    }

    func testSearchRejectsEmptyQuery() async {
        do {
            _ = try await WebSearchService.search(query: "   ", apiKey: "tvly-test")
            XCTFail("emptyQuery 에러가 발생해야 합니다")
        } catch let error as WebSearchError {
            XCTAssertEqual(error.errorCode, "E-MAC-VALID-1002")
        } catch {
            XCTFail("예상치 못한 에러 타입: \(error)")
        }
    }
}
