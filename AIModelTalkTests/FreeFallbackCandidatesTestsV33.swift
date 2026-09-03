import XCTest
@testable import AIModelTalk

/// v3.4 — 429 자동 폴백 우선순위 리스트 테스트 (T-162)
/// 순서·무료 필터·활성 필터·현재 모델 제외·primaryFallbackModel 폴백 검증
@MainActor
final class FreeFallbackCandidatesTestsV33: XCTestCase {

    override func setUp() {
        super.setUp()
        let catalog = ModelCatalog.shared
        // 기본값 해제(v0.2.2) — 리셋 후 fallbackPriority 후보들을 명시 활성화해 확정 순서 상태를 만든다
        catalog.enabledOverrides = [:]
        for priority in ModelCatalog.fallbackPriority {
            guard let model = catalog.model(id: priority.id, provider: priority.provider) else { continue }
            catalog.setEnabled(model, true)
        }
    }

    override func tearDown() {
        ModelCatalog.shared.enabledOverrides = [:]
        super.tearDown()
    }

    /// 우선순위 순서: Groq → NVIDIA → Gemini → OpenRouter → OpenRouter (활성+무료 기본)
    func testPriorityOrder() {
        let candidates = ModelCatalog.freeFallbackCandidates()
        let ids = candidates.map { "\($0.provider.rawValue):\($0.id)" }
        XCTAssertEqual(ids, [
            "Groq:llama-3.3-70b-versatile",
            "NVIDIA:openai/gpt-oss-20b",
            "Gemini:gemini-3.6-flash",
            "OpenRouter:google/gemini-2.5-flash-preview:free",
            "OpenRouter:deepseek/deepseek-chat-v3-0324:free",
        ])
    }

    /// 무료(유료) 모델만 포함 — 우선순위 리스트가 전부 isFree여야 함
    func testAllCandidatesAreFree() {
        for candidate in ModelCatalog.freeFallbackCandidates() {
            XCTAssertTrue(candidate.isFree, "\(candidate.id)는 무료 모델이어야 함")
        }
    }

    /// 활성 오버라이드=false인 모델은 후보에서 제외
    func testDisabledModelExcluded() {
        ModelCatalog.shared.enabledOverrides["NVIDIA:openai/gpt-oss-20b"] = false
        let ids = ModelCatalog.freeFallbackCandidates().map { $0.id }
        XCTAssertFalse(ids.contains("openai/gpt-oss-20b"), "비활성 NVIDIA 모델은 제외되어야 함")
        XCTAssertEqual(ids.first, "llama-3.3-70b-versatile", "Groq가 새 1순위가 되어야 함")
    }

    /// excluding(현재 모델) — 현재 rate 실패 모델은 제외
    func testCurrentModelExcluded() {
        let current = ModelCatalog.shared.models.first { $0.id == "llama-3.3-70b-versatile" && $0.provider == .groq }!
        let candidates = ModelCatalog.freeFallbackCandidates(excluding: current)
        let groqPresent = candidates.contains { $0.provider == .groq }
        XCTAssertFalse(groqPresent, "현재(Groq) 모델은 후보에서 제외되어야 함")
        XCTAssertEqual(candidates.first?.id, "openai/gpt-oss-20b", "다음 순위는 NVIDIA여야 함")
    }

    /// excluding이 nil이면 현재 모델 제외하지 않음
    func testNoExcludingReturnsFullList() {
        let candidates = ModelCatalog.freeFallbackCandidates()
        XCTAssertEqual(candidates.count, 5)
    }

    /// primaryFallbackModel — 첫 활성 무료 모델(Groq). 전부 비활성 시 등록 목록 첫 모델로 폴백
    func testPrimaryFallbackModel() {
        let primary = ModelCatalog.primaryFallbackModel()
        XCTAssertEqual(primary.id, "llama-3.3-70b-versatile")
        XCTAssertEqual(primary.provider, .groq)
    }

    /// 우선순위 전체 비활성 시 primaryFallbackModel은 등록 목록 첫 모델 폴백 (가드)
    func testPrimaryFallbackWhenAllDisabled() {
        let all = ModelCatalog.shared.models.filter { $0.isFree }
        for model in all {
            ModelCatalog.shared.enabledOverrides["\(model.provider.rawValue):\(model.id)"] = false
        }
        let primary = ModelCatalog.primaryFallbackModel()
        // 가드: freeFallbackCandidates()가 비면 defaultModels.first 사용
        XCTAssertEqual(primary.id, ModelCatalog.defaultModels.first!.id)
    }
}
