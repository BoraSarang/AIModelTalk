import XCTest
@testable import AIModelTalk

/// v1.7 모델 사용 플래그 + 스킬 플래그 저장소 테스트 (T-57)
final class ModelAndSkillFlagTestsV17: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: - 모델 사용 플래그 (T-53)

    @MainActor
    func testEnabledOverrideRoundTripAndPersistence() {
        let defaults = makeDefaults()
        let catalog = ModelCatalog(defaults: defaults)
        let model = AIModel(id: "flag-test-model", provider: .gemini, displayName: "플래그 테스트")

        // 미등록 모델은 기본 OFF (v0.2.2 — 기본값 해제, Apple Intelligence만 예외)
        XCTAssertFalse(catalog.isEnabled(model))

        catalog.addModel(model)
        XCTAssertEqual(catalog.visibleModels(for: .gemini).filter { $0.id == "flag-test-model" }.count, 0)

        // OFF → 피커에서 숨김
        catalog.setEnabled(model, false)
        XCTAssertFalse(catalog.isEnabled(model))
        XCTAssertEqual(catalog.visibleModels(for: .gemini).filter { $0.id == "flag-test-model" }.count, 0)

        // UserDefaults 영속성 — 새 인스턴스에서도 유지
        let reloaded = ModelCatalog(defaults: defaults)
        XCTAssertFalse(reloaded.isEnabled(model))

        // 다시 ON
        reloaded.setEnabled(model, true)
        XCTAssertTrue(reloaded.isEnabled(model))
    }

    @MainActor
    func testNewModelDefaultsToDisabled() {
        let defaults = makeDefaults()
        let catalog = ModelCatalog(defaults: defaults)

        // 목록에만 추가(갱신으로 들어온 신규 모델 상황) — 플래그 없으면 자동 OFF (v0.2.2 기본값 해제)
        let fresh = AIModel(id: "fresh-model", provider: .openRouter, displayName: "신규")
        catalog.addModel(fresh)
        XCTAssertFalse(catalog.isEnabled(fresh))
        XCTAssertFalse(catalog.visibleModels(for: .openRouter).contains { $0.id == "fresh-model" })

        // 활성화하면 노출
        catalog.setEnabled(fresh, true)
        XCTAssertTrue(catalog.isEnabled(fresh))
        XCTAssertTrue(catalog.visibleModels(for: .openRouter).contains { $0.id == "fresh-model" })
    }

    @MainActor
    func testDefaultOverridePolicy() {
        let defaults = makeDefaults()
        let catalog = ModelCatalog(defaults: defaults)

        // 기본값 해제(v0.2.2): 명시하지 않은 일반 모델은 OFF
        let nvidia = AIModel(id: "openai/gpt-oss-20b", provider: .nvidia, displayName: "GPT-OSS")
        XCTAssertFalse(catalog.isEnabled(nvidia))
        XCTAssertFalse(catalog.visibleModels(for: .nvidia).contains { $0.id == "openai/gpt-oss-20b" })

        // Apple Intelligence는 시스템 모델이 가용할 때 기본 ON (미가용이면 게이트로 false)
        let ai = AIModel(id: "apple-intelligence", provider: .appleIntelligence, displayName: "Apple Intelligence")
        if ModelCatalog.appleAvailable(model: ai, modelAvailable: AppleIntelligenceSupport.modelAvailable) {
            XCTAssertTrue(catalog.isEnabled(ai))
        }

        // 명시 활성화하면 일반 모델도 노출
        catalog.setEnabled(nvidia, true)
        XCTAssertTrue(catalog.isEnabled(nvidia))
        XCTAssertTrue(catalog.visibleModels(for: .nvidia).contains { $0.id == "openai/gpt-oss-20b" })
    }

    // MARK: - 스킬 플래그 저장소 (T-55~56)

    func testSkillFlagStoreRoundTrip() {
        let defaults = makeDefaults()
        var store = SkillFlagStore(defaults: defaults)

        XCTAssertTrue(store.hiddenIDs.isEmpty)
        XCTAssertTrue(store.defaultIDs.isEmpty)

        store.hiddenIDs = ["skill-a", "skill-b"]
        store.defaultIDs = ["skill-a"]

        let reloaded = SkillFlagStore(defaults: defaults)
        XCTAssertEqual(reloaded.hiddenIDs, ["skill-a", "skill-b"])
        XCTAssertEqual(reloaded.defaultIDs, ["skill-a"])
    }
}
