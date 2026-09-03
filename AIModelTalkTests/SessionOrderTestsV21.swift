import XCTest
@testable import AIModelTalk

/// v2.1 T-99 — 사이드바 세션 드래그 재배치 로직 테스트 (순수 함수 중심)
final class SessionOrderTestsV21: XCTestCase {

    private func session(_ title: String, daysAgo: Double = 0) -> ChatSession {
        let date = Date(timeIntervalSinceNow: -daysAgo * 86_400)
        return ChatSession(title: title, createdAt: date, updatedAt: date)
    }

    // 같은 그룹 내 앞/뒤 삽입 — 순서 변경 핵심 동작
    func testReorderWithinSameGroupBeforeAndAfter() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let order = [a, b, c, d]

        XCTAssertEqual(
            SessionOrderStore.reorderedIDs(order, moving: c, relativeTo: a, placeBefore: true),
            [c, a, b, d],
            "c를 a 앞에 삽입"
        )
        XCTAssertEqual(
            SessionOrderStore.reorderedIDs(order, moving: c, relativeTo: a, placeBefore: false),
            [a, c, b, d],
            "c를 a 뒤에 삽입"
        )
        XCTAssertEqual(
            SessionOrderStore.reorderedIDs(order, moving: a, relativeTo: d, placeBefore: false),
            [b, c, d, a],
            "a를 목록 끝(d 뒤)으로 이동"
        )
    }

    // 자기 자신 드롭·미등록 ID 무시 — 원본 보존
    func testReorderIgnoresSelfAndMissingIDs() {
        let a = UUID(), b = UUID()
        let order = [a, b]
        let ghost = UUID()

        XCTAssertEqual(SessionOrderStore.reorderedIDs(order, moving: a, relativeTo: a, placeBefore: true), order)
        XCTAssertEqual(SessionOrderStore.reorderedIDs(order, moving: a, relativeTo: ghost, placeBefore: true), order)
        XCTAssertEqual(SessionOrderStore.reorderedIDs(order, moving: ghost, relativeTo: b, placeBefore: true), order)
    }

    // 정규화: 삭제된 ID 프루닝 + 중복 제거 + 미등록은 updatedAt 최신순 뒤에 추가
    func testNormalizedOrderPrunesDedupesAndAppendsByRecency() {
        let old = session("오래됨", daysAgo: 3)
        let mid = session("중간", daysAgo: 2)
        let fresh = session("최신", daysAgo: 1)
        let removed = UUID()

        let normalized = SessionOrderStore.normalizedOrder(
            [removed, old.id, old.id, mid.id],
            sessions: [old, mid, fresh]
        )

        XCTAssertEqual(normalized, [old.id, mid.id, fresh.id])
    }
}
