import XCTest
@testable import AIModelTalk

/// v3.2 — HTTP 429(요청 한도/속도 초과) 사용자 메시지·코드 구분 테스트 (T-154)
final class AppErrorRateLimitTestsV32: XCTestCase {

    func testServerError429HasRateLimitMessage() {
        let err = AppError.serverError(429, "FreeUsageLimitError")
        XCTAssertTrue((err.localizedDescription ?? "").contains("429"))
        XCTAssertTrue((err.localizedDescription ?? "").lowercased().contains("다시 시도"))
    }

    func testServerError429HasDistinctCode() {
        let err = AppError.serverError(429, "rate limit")
        XCTAssertEqual(err.errorCode, "E-MAC-NET-1005")
    }

    func testOtherServerErrorsKeepGenericCodeAndMessage() {
        let err = AppError.serverError(500, "internal")
        XCTAssertEqual(err.errorCode, "E-MAC-API-1001")
        let msg = err.localizedDescription ?? ""
        XCTAssertTrue(msg.contains("500"))
        XCTAssertFalse(msg.contains("429"))
    }
}
