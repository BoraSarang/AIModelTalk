import XCTest
import NaturalLanguage
@testable import AIModelTalk

/// v2.3 T-117 스파이크 — NLEmbedding 한국어 문장 임베딩 가용성 확인
/// 결과는 로그로 기록하며 환경 의존이라 단정하지 않는다.
final class NLEmbeddingSpikeTests: XCTestCase {

    func testSentenceEmbeddingAvailability() {
        let languages: [(NLLanguage, String)] = [
            (.korean, "한국어"), (.english, "English"), (.japanese, "日本語"),
            (.simplifiedChinese, "中文"), (.german, "Deutsch")
        ]
        for (lang, label) in languages {
            let embedding = NLEmbedding.sentenceEmbedding(for: lang)
            DebugLogger.shared.info("SPIKE", "[NLEmbedding] \(label): \(embedding != nil ? "지원" : "미지원")")
            if let embedding, lang == .korean {
                let v1 = embedding.vector(for: "나는 표로 정리된 답변을 선호한다")
                let v2 = embedding.vector(for: "답변은 표로 정리해 줘")
                let v3 = embedding.vector(for: "오늘 날씨가 좋다")
                DebugLogger.shared.info("SPIKE", "[NLEmbedding] 한국어 벡터 차원: \(v1?.count ?? 0)")
                if let a = v1, let b = v2, let c = v3 {
                    let simRelated = MemoryRetrieval.cosine(a, b)
                    let simUnrelated = MemoryRetrieval.cosine(a, c)
                    DebugLogger.shared.info("SPIKE", "[NLEmbedding] 유사(표정리)=\(String(format: "%.3f", simRelated)) vs 무관(날씨)=\(String(format: "%.3f", simUnrelated))")
                    XCTAssertGreaterThan(simRelated, simUnrelated, "의미 유사도가 무관 쌍보다 높아야 함")
                }
            }
        }
    }
}
