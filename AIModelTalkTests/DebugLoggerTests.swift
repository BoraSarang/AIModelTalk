import XCTest
@testable import AIModelTalk

final class DebugLoggerTests: XCTestCase {

    func testLogEntryCreation() {
        let logger = DebugLogger.shared
        let countBefore = logger.entries.count

        logger.info("TEST", "테스트 메시지")

        // 비동기이므로 잠시 대기
        let expectation = XCTestExpectation(description: "Log added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertGreaterThan(logger.entries.count, countBefore)
    }

    func testDumpContainsLog() {
        let logger = DebugLogger.shared
        logger.clear()
        logger.info("DUMP_TEST", "덤프 테스트")

        let expectation = XCTestExpectation(description: "Log added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        let dump = logger.dump()
        XCTAssertTrue(dump.contains("DUMP_TEST"))
    }

    func testClearLogs() {
        let logger = DebugLogger.shared
        logger.info("CLEAR_TEST", "클리어 테스트")

        let expectation = XCTestExpectation(description: "Log added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        logger.clear()
        XCTAssertTrue(logger.entries.isEmpty)
    }
}

final class AppErrorTests: XCTestCase {

    func testErrorCodeFormat() {
        let error = AppError.missingKey(.nvidia)
        XCTAssertEqual(error.errorCode, "E-MAC-KEY-1001")
    }

    func testErrorDescription() {
        let error = AppError.network("test")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("네트워크"))
    }
}
