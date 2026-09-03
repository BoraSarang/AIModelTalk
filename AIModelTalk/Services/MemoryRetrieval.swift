import Foundation
import NaturalLanguage

/// 메모리 시맨틱 검색 — 관련 기억만 골라 주입 (v2.3 T-117)
/// NLEmbedding(온디바이스·무료) 가능 시 cosine, 아니면 문자 bigram Dice 폴백.
enum MemoryRetrieval {
    /// 검색 결과 기본 상한 — Alma의 Max Retrieved=10 참고, 예산 절단 전 단계
    static let defaultLimit = 8

    // MARK: - 유사도

    nonisolated static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in a.indices {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / ((na * nb).squareRoot())
    }

    /// 문자 bigram Dice 계수 — 사전 불필요, 한국어 무설정 폴백 (순수)
    nonisolated static func bigramScore(_ query: String, _ text: String) -> Double {
        func bigrams(_ s: String) -> Set<String> {
            let chars = Array(s.lowercased().filter { !$0.isWhitespace })
            guard chars.count > 1 else { return chars.isEmpty ? [] : [String(chars[0])] }
            return Set((0...(chars.count - 2)).map { String(chars[$0...$0 + 1]) })
        }
        let a = bigrams(query), b = bigrams(text)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count * 2) / Double(a.count + b.count)
    }

    // MARK: - 랭킹

    /// 쿼리와 관련 높은 순으로 정렬 — 유사도 + 중요도 + 핀 가산 (순수, 임베더 주입형)
    /// embedder가 nil이거나 벡터 미산출 시 bigram 폴백.
    nonisolated static func rank(
        query: String,
        items: [MemoryItem],
        limit: Int = defaultLimit,
        embedder: ((String) -> [Double]?)? = nil
    ) -> [MemoryItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !items.isEmpty else { return Array(items.prefix(limit)) }

        let queryVector = embedder?(q)

        func score(_ item: MemoryItem) -> Double {
            let sim: Double
            if let qv = queryVector, let iv = embedder?(item.content), !qv.isEmpty, !iv.isEmpty {
                sim = max(0, cosine(qv, iv))
            } else {
                sim = bigramScore(q, item.content)
            }
            // 유사도 우위 유지 + 중요도·핀 소폭 가산 (최대 가산 0.1 — 순위 뒤집기 방지)
            return sim + item.importance * 0.05 + (item.isPinned ? 0.05 : 0)
        }

        return items
            .sorted { score($0) > score($1) }
            .prefix(limit)
            .map { $0 }
    }
}

/// NLEmbedding 래퍼 — 벡터 캐시 동반 (온디바이스 임베딩, v2.3 T-117)
/// 한국어 문장 임베딩 미지원 환경이면 nil을 반환해 bigram 폴백으로 동작한다.
final class SemanticEmbedder {
    static let shared = SemanticEmbedder()

    private let embedding: NLEmbedding?
    private var cache: [String: [Double]] = [:]
    private let lock = NSLock()

    private init() {
        // 한국어 우선, 미지원이면 nil → 폴백 경로
        embedding = NLEmbedding.sentenceEmbedding(for: .korean)
        if embedding != nil {
            DebugLogger.shared.info("MEMORY", "[FEATURE] 시맨틱 검색 활성화: NLEmbedding(ko)")
        } else {
            DebugLogger.shared.info("MEMORY", "[FEATURE] NLEmbedding(ko) 미지원 — bigram 폴백 검색 사용")
        }
    }

    var isSemanticAvailable: Bool { embedding != nil }

    /// 텍스트 벡터 — 캐시 히트 우선, 미산출 시 nil (호출부가 폴백 판단)
    func vector(for text: String) -> [Double]? {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        guard let embedding, let vector = embedding.vector(for: key) else { return nil }
        let doubles = vector.map { Double($0) }
        lock.lock()
        // 캐시 상한 — 과대 방지 (기억 20개 상한이라 실질 여유)
        if cache.count > 500 { cache.removeAll(keepingCapacity: true) }
        cache[key] = doubles
        lock.unlock()
        return doubles
    }
}
