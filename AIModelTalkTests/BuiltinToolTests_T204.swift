import XCTest
@testable import AIModelTalk

/// T-204 — 내장 도구(web_search/fetch_url/calculator) 순수 로직 및 ToolLoopService 분기
/// 네트워크 호출(fetch_url/web_search)은 실기기 확인 대상 — SSRF 가드·HTML 정제·계산기는 순수 검증
@MainActor
final class BuiltinToolTests_T204: XCTestCase {

    // MARK: - calculator

    func testCalculatorBasicArithmetic() throws {
        XCTAssertEqual(try WebSearchService.evaluateCalculator("2 + 3 * 4"), 14.0)
        XCTAssertEqual(try WebSearchService.evaluateCalculator("(2 + 3) * 4"), 20.0)
        XCTAssertEqual(try WebSearchService.evaluateCalculator("10 / 4"), 2.5)
    }

    func testCalculatorRejectsNonWhitelist() {
        XCTAssertThrowsError(try WebSearchService.evaluateCalculator("2 ** 3"))
        XCTAssertThrowsError(try WebSearchService.evaluateCalculator("sqrt(9)"))
        XCTAssertThrowsError(try WebSearchService.evaluateCalculator("1 + mission"))
        XCTAssertThrowsError(try WebSearchService.evaluateCalculator("2 +"))
    }

    func testCalculatorRejectsEmpty() {
        XCTAssertThrowsError(try WebSearchService.evaluateCalculator("   "))
    }

    func testCalculatorAllowsThousandsSeparator() throws {
        XCTAssertEqual(try WebSearchService.evaluateCalculator("1,000 + 500"), 1500.0)
    }

    // MARK: - HTML 정제

    func testStripHTMLRemovesTagsAndScripts() {
        let html = "<html><head><script>var x=1;</script><style>body{}</style></head><body>안녕 <b>세상</b> &amp; TEST</body></html>"
        let text = WebSearchService.stripHTML(html)
        XCTAssertFalse(text.contains("<"))
        XCTAssertFalse(text.contains("var x=1"))
        XCTAssertTrue(text.contains("안녕"))
        XCTAssertTrue(text.contains("세상"))
        XCTAssertTrue(text.contains("&"))
    }

    // MARK: - SSRF 가드

    func testSSRFBlocksPrivateLoopback() {
        XCTAssertFalse(WebSearchService.isSafeFetchURL(URL(string: "http://127.0.0.1:3000")!))
        XCTAssertFalse(WebSearchService.isSafeFetchURL(URL(string: "http://localhost:8080")!))
        XCTAssertFalse(WebSearchService.isSafeFetchURL(URL(string: "http://10.0.0.5/x")!))
        XCTAssertFalse(WebSearchService.isSafeFetchURL(URL(string: "http://192.168.1.10")!))
        XCTAssertFalse(WebSearchService.isSafeFetchURL(URL(string: "ftp://example.com/file")!))
    }

    func testSSRFAllowsPublic() {
        // 공개 도메인과 공개 리터럴 IP는 허용
        XCTAssertTrue(WebSearchService.isSafeFetchURL(URL(string: "https://example.com/path")!))
        XCTAssertTrue(WebSearchService.isSafeFetchURL(URL(string: "https://93.184.216.34/x")!))
    }

    // MARK: - ToolLoopService 내장 도구 분기

    func testExecuteRunsCalculatorBuiltin() async throws {
        let call = LLMToolCall(id: "c1", name: "calculator", argumentsJSON: #"{"expression":"6 * 7"}"#)
        let record = try await ToolLoopService.execute(call: call, connections: [])
        XCTAssertFalse(record.isError, "내장 도구는 연결 없이 성공")
        XCTAssertEqual(record.toolName, "calculator")
        XCTAssertTrue(record.resultPreview?.contains("42") ?? false)
    }

    func testBuiltinToolNames() {
        XCTAssertTrue(ToolLoopService.builtinToolNames.contains("web_search"))
        XCTAssertTrue(ToolLoopService.builtinToolNames.contains("fetch_url"))
        XCTAssertTrue(ToolLoopService.builtinToolNames.contains("calculator"))
    }

    func testUnknownToolGoesToConnectionLookup() async throws {
        // 알 수 없는 도구는 연결 없으면 "연결되지 않았습니다" 오류
        let call = LLMToolCall(id: "x", name: "unknown_tool", argumentsJSON: "{}")
        let record = try await ToolLoopService.execute(call: call, connections: [])
        XCTAssertTrue(record.isError)
        XCTAssertTrue(record.resultPreview?.contains("연결되지 않았습니다") ?? false)
    }
}