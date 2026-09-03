import XCTest
@testable import AIModelTalk

/// StreamManager 세션별 병렬 스트리밍 수명주기 검증 (v3.0 T-002)
final class StreamManagerTestsV30: XCTestCase {

    @MainActor
    func testStartAndStopSession() async {
        let manager = StreamManager()
        let sessionID = UUID()

        let expectation = expectation(description: "스트리밍 종료")

        manager.start(sessionID) {
            await Task.yield()
            expectation.fulfill()
        }

        XCTAssertTrue(manager.isStreaming(sessionID))

        manager.stop(sessionID)
        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertFalse(manager.isStreaming(sessionID))
    }

    @MainActor
    func testRestartSameSessionCancelsPrevious() async {
        let manager = StreamManager()
        let sessionID = UUID()

        var firstCancelled = false
        let firstExp = expectation(description: "첫 번째 스트리밍 취소")

        manager.start(sessionID) {
            await Task.yield()
            if Task.isCancelled {
                firstCancelled = true
            }
            firstExp.fulfill()
        }

        // 동일 세션 재시작 — 첫 번째 취소 후 덮어씀
        manager.start(sessionID) {
            await Task.yield()
        }

        await fulfillment(of: [firstExp], timeout: 2)
        XCTAssertTrue(firstCancelled, "동일 세션 재시작 시 이전 작업이 취소되어야 한다")
    }

    @MainActor
    func testParallelSessionsBothStream() async {
        let manager = StreamManager()
        let sessionA = UUID()
        let sessionB = UUID()

        manager.start(sessionA) {
            await Task.yield()
        }
        manager.start(sessionB) {
            await Task.yield()
        }

        XCTAssertTrue(manager.isStreaming(sessionA))
        XCTAssertTrue(manager.isStreaming(sessionB))
        XCTAssertEqual(manager.activeSessions.count, 2)

        manager.stop(sessionA)
        XCTAssertFalse(manager.isStreaming(sessionA))
        XCTAssertTrue(manager.isStreaming(sessionB))
    }

    @MainActor
    func testStopAllCancelsEverything() async {
        let manager = StreamManager()
        let sessionA = UUID()
        let sessionB = UUID()

        manager.start(sessionA) { await Task.yield() }
        manager.start(sessionB) { await Task.yield() }

        manager.stopAll()

        XCTAssertFalse(manager.isStreaming(sessionA))
        XCTAssertFalse(manager.isStreaming(sessionB))
        XCTAssertTrue(manager.activeSessions.isEmpty)
    }
}
