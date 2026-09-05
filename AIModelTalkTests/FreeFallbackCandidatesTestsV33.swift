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

    /// 우선순위 순서: Zen Muse Spark → OpenRouter North Mini Code → Zen Ultra → NVIDIA → Gemini (T-331)
    func testPriorityOrder() {
        let candidates = ModelCatalog.freeFallbackCandidates()
        let ids = candidates.map { "\($0.provider.rawValue):\($0.id)" }
        XCTAssertEqual(ids, [
            "OpenCode:opencode/muse-spark-1.3-contributor-free",
            "OpenRouter:cohere/north-mini-code:free",
            "OpenCode:opencode/nemotron-3-ultra-free",
            "NVIDIA:openai/gpt-oss-20b",
            "Gemini:gemini-3.6-flash",
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
        XCTAssertEqual(ids.first, "opencode/muse-spark-1.3-contributor-free", "Zen Muse Spark가 새 1순위가 되어야 함")
    }

    /// excluding(현재 모델) — 현재 rate 실패 모델은 제외
    func testCurrentModelExcluded() {
        let current = ModelCatalog.shared.models.first { $0.id == "opencode/muse-spark-1.3-contributor-free" && $0.provider == .opencode }!
        let candidates = ModelCatalog.freeFallbackCandidates(excluding: current)
        let sparkPresent = candidates.contains { $0.id == "opencode/muse-spark-1.3-contributor-free" }
        XCTAssertFalse(sparkPresent, "현재(Zen Muse Spark) 모델은 후보에서 제외되어야 함")
        XCTAssertEqual(candidates.first?.id, "cohere/north-mini-code:free", "다음 순위는 OpenRouter North Mini Code여야 함")
    }

    /// excluding이 nil이면 현재 모델 제외하지 않음
    func testNoExcludingReturnsFullList() {
        let candidates = ModelCatalog.freeFallbackCandidates()
        XCTAssertEqual(candidates.count, 5)
    }

    /// primaryFallbackModel — 첫 활성 무료 모델(Zen Muse Spark). 전부 비활성 시 등록 목록 첫 모델로 폴백
    func testPrimaryFallbackModel() {
        let primary = ModelCatalog.primaryFallbackModel()
        XCTAssertEqual(primary.id, "opencode/muse-spark-1.3-contributor-free")
        XCTAssertEqual(primary.provider, .opencode)
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
