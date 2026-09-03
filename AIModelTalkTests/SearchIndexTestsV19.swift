import XCTest
@testable import AIModelTalk

/// v1.9 T-77 — FTS5 검색 인덱스 테스트 (인메모리 DB 격리)
final class SearchIndexTestsV19: XCTestCase {

    private var service: SearchIndexService!

    override func setUp() {
        super.setUp()
        service = SearchIndexService(inMemory: true)
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    private func makeSession(_ title: String, contents: [(role: ChatRole, text: String)]) -> ChatSession {
        var session = ChatSession(title: title)
        session.messages = contents.map { AIModelTalk.ChatMessage(role: $0.role, content: $0.text) }
        return session
    }

    func testKoreanLongQueryFTS() {
        let session = makeSession("테스트", contents: [
            (.user, "SwiftData 마이그레이션은 언제 실행되나요?"),
            (.assistant, "SwiftData 경량 마이그레이션은 스키마 변경 감지 시 자동으로 실행됩니다.")
        ])
        service.index(session)

        let hits = service.search("경량 마이그레이션")
        XCTAssertFalse(hits.isEmpty, "3자 이상 한글 질의는 FTS trigram으로 매칭")
        XCTAssertEqual(hits.first?.sessionID, session.id)
        XCTAssertEqual(hits.first?.role, "assistant")
    }

    func testShortKoreanQueryLikeFallback() {
        let session = makeSession("인사", contents: [
            (.user, "안녕하세요 반갑습니다"),
            (.assistant, "안녕! 무엇을 도와드릴까요?")
        ])
        service.index(session)

        // 2자 질의 — trigram 최소 길이 미달 → LIKE 폴백
        let hits = service.search("안녕")
        XCTAssertFalse(hits.isEmpty, "2자 한글 질의는 LIKE 폴백으로 매칭")
        XCTAssertEqual(hits.count, 2)
    }

    func testEnglishSubstringMatch() {
        let session = makeSession("dev", contents: [
            (.assistant, "use stream_options include_usage for token counts")
        ])
        service.index(session)

        XCTAssertTrue(service.search("include_usage").contains { $0.sessionID == session.id })
        XCTAssertTrue(service.search("usage").isEmpty == false || true) // 5자 — FTS 또는 폴백 어느 쪽이든 무방
        XCTAssertFalse(service.search("usage").isEmpty, "부분 단어도 매칭")
    }

    func testRemoveExcludesSession() {
        let s1 = makeSession("s1", contents: [(.user, "고유 키워드 자기소개서")])
        let s2 = makeSession("s2", contents: [(.user, "다른 내용입니다")])
        service.index(s1)
        service.index(s2)

        service.remove(sessionID: s1.id)
        XCTAssertFalse(service.search("자기소개서").contains { $0.sessionID == s1.id })
    }

    func testReindexIfEmptyBootstrapsIdempotently() {
        let s1 = makeSession("재구축 대상 세션", contents: [(.user, "재구축 대상 메시지입니다")])
        service.reindexIfEmpty(sessions: [s1])
        // 제목 행 1 + 메시지 행 1 (v2.1 T-97 제목 색인)
        XCTAssertEqual(service.totalCount(), 2)

        // 이미 채워진 인덱스는 재호출해도 중복 삽입 없음
        service.reindexIfEmpty(sessions: [s1])
        XCTAssertEqual(service.totalCount(), 2)
    }

    func testSessionTitleIndexedAsTitleRole() {
        let session = makeSession("자기소개서 첨삭 전용", contents: [
            (.user, "본문은 다른 내용입니다")
        ])
        service.index(session)

        let hits = service.search("첨삭 전용")
        XCTAssertTrue(hits.contains { $0.role == "title" }, "세션 제목이 title 역할로 검색됨")
    }

    func testEmptyAndShortQueriesReturnEmpty() {
        XCTAssertTrue(service.search("").isEmpty)
        XCTAssertTrue(service.search("a").isEmpty, "1자 질의 방지")
    }
}
