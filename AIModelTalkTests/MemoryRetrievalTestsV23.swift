import XCTest
@testable import AIModelTalk

/// v2.3 T-117 — 메모리 시맨틱 검색 테스트 (cosine·bigram·랭킹·폴백·eviction 내구성)
final class MemoryRetrievalTestsV23: XCTestCase {

    // MARK: - cosine

    func testCosineIdenticalAndOrthogonal() {
        XCTAssertEqual(MemoryRetrieval.cosine([1, 0], [1, 0]), 1.0, accuracy: 0.0001)
        XCTAssertEqual(MemoryRetrieval.cosine([1, 0], [0, 1]), 0.0, accuracy: 0.0001)
        XCTAssertEqual(MemoryRetrieval.cosine([], [1]), 0.0, "빈 벡터 방어")
    }

    // MARK: - bigram 폴백 (주력 경로 — NLEmbedding 한국어 미지원 확인됨)

    func testBigramScoreRelatedVsUnrelated() {
        let related = MemoryRetrieval.bigramScore("답변은 표로 정리해 줘", "표 정리 선호")
        let unrelated = MemoryRetrieval.bigramScore("답변은 표로 정리해 줘", "고양이 사료 브랜드")
        XCTAssertGreaterThan(related, unrelated)
        XCTAssertGreaterThan(related, 0.1, "어휘 겹침이 있으면 양의 점수")
    }

    func testBigramScoreIdentical() {
        XCTAssertEqual(MemoryRetrieval.bigramScore("표 정리", "표 정리"), 1.0, accuracy: 0.0001)
    }

    // MARK: - 랭킹

    func testRankWithEmbedderPutsRelevantFirst() {
        let memories = [
            MemoryItem(content: "고양이 사료는 A브랜드"),
            MemoryItem(content: "답변은 표로 정리 선호"),
            MemoryItem(content: "회의는 화요일")
        ]
        // 가짜 임베더 — "표" 관련 텍스트는 쿼리와 유사 벡터 반환
        let embedder: (String) -> [Double]? = { text in
            text.contains("표") ? [1, 0, 0] : [0, 1, 0]
        }
        let ranked = MemoryRetrieval.rank(query: "표로 정리해줘", items: memories, limit: 8, embedder: embedder)

        XCTAssertEqual(ranked.first?.content, "답변은 표로 정리 선호")
    }

    func testRankFallbackWithoutEmbedder() {
        let memories = [
            MemoryItem(content: "고양이 사료 브랜드"),
            MemoryItem(content: "표 정리 선호")
        ]
        let ranked = MemoryRetrieval.rank(query: "표 정리", items: memories, limit: 8, embedder: nil)

        XCTAssertEqual(ranked.first?.content, "표 정리 선호", "embedder nil이면 bigram 폴백")
    }

    func testRankRespectsLimitAndEmptyQuery() {
        let memories = (0..<12).map { MemoryItem(content: "기억\($0)") }

        let ranked = MemoryRetrieval.rank(query: "기억", items: memories, limit: 8)
        XCTAssertEqual(ranked.count, 8, "상위 K 선별")

        let empty = MemoryRetrieval.rank(query: "   ", items: memories, limit: 8)
        XCTAssertEqual(empty.count, 8, "빈 쿼리는 기존 순서 상위 반환")
    }

    func testRankImportanceAndPinBoost() {
        let memories = [
            MemoryItem(content: "표 정리 관련 내용", importance: 0.0),
            MemoryItem(content: "표 정리 관련 내용", isPinned: true, importance: 1.0)
        ]
        let ranked = MemoryRetrieval.rank(query: "표", items: memories, limit: 8, embedder: nil)
        XCTAssertEqual(ranked.first?.isPinned, true, "동점이면 중요도·핀 가산으로 결정")
    }

    // MARK: - eviction 내구성 (temporary 우선)

    func testEvictionPrefersTemporaryOverOlderPermanent() {
        let base = Date(timeIntervalSinceNow: -100_000)
        // 상한 20 채우기 — 19개 오래된 영구 + 최근 임시 1개
        var memories: [MemoryItem] = []
        for i in 0..<19 {
            memories.append(
                MemoryItem(content: "영구\(i)", createdAt: base.addingTimeInterval(Double(i)), durability: .permanent))
        }
        memories.append(
            MemoryItem(content: "최근 임시", createdAt: Date(), durability: .temporary))
        XCTAssertEqual(memories.count, MemoryService.maxMemories)

        let result = MemoryService.applying(["새 기억"], to: memories, now: Date())

        XCTAssertEqual(result.count, MemoryService.maxMemories, "상한 유지")
        XCTAssertFalse(result.contains { $0.content == "최근 임시" }, "임시가 영구보다 먼저 퇴출")
        XCTAssertTrue(result.contains { $0.content == "새 기억" })
        XCTAssertTrue(result.contains { $0.content == "영구0" }, "영구 항목은 보존")
    }
}
