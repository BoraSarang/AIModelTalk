import XCTest
@testable import AIModelTalk

/// v3.1 — OpenCode(Zen)·DeepSeek 공급자 추가 + 무료 우선순위 정렬 테스트
@MainActor
final class ProviderAndModelSortTestsV31: XCTestCase {

    // MARK: - 신규 공급자 메타데이터

    func testOpenCodeAndDeepSeekRequireKeysAndHaveBaseURLs() {
        let newOnes: [Provider] = [.opencode, .deepseek]
        for provider in newOnes {
            XCTAssertTrue(provider.requiresAPIKey, "\(provider.rawValue)는 API 키 필수")
            XCTAssertFalse(provider.baseURL.isEmpty, "\(provider.rawValue) baseURL 등록됨")
            XCTAssertTrue(provider.baseURL.hasPrefix("https://"))
            XCTAssertTrue(provider.isOpenAICompatible, "\(provider.rawValue)는 OpenAI 호환 예상")
        }
    }

    func testOpenCodeAndDeepSeekBaseURLs() {
        XCTAssertEqual(Provider.opencode.baseURL, "https://opencode.ai/zen/v1")
        XCTAssertEqual(Provider.deepseek.baseURL, "https://api.deepseek.com")
    }

    func testOpenCodeAndDeepSeekSettingsKeysUnique() {
        let all = Provider.allCases.map(\.settingsKey).filter { !$0.isEmpty }
        XCTAssertEqual(Set(all).count, all.count, "저장 키 중복 없음")
        XCTAssertEqual(Provider.opencode.settingsKey, "opencodeAPIKey")
        XCTAssertEqual(Provider.deepseek.settingsKey, "deepseekAPIKey")
    }

    func testOpenCodeAndDeepSeekAPIKeyURLsPresent() {
        XCTAssertEqual(Provider.opencode.apiKeyURL, "https://opencode.ai/auth")
        XCTAssertEqual(Provider.deepseek.apiKeyURL, "https://platform.deepseek.com")
    }

    func testNewProviderKeysPersistViaAppSettings() {
        let settings = AppSettings.shared
        settings.setAPIKey("sk-test-opencode-key-abcdef1234567890", for: .opencode)
        settings.setAPIKey("sk-test-deepseek-key-abcdef1234567890", for: .deepseek)
        XCTAssertEqual(settings.apiKey(for: .opencode), "sk-test-opencode-key-abcdef1234567890")
        XCTAssertEqual(settings.apiKey(for: .deepseek), "sk-test-deepseek-key-abcdef1234567890")
        // 테스트 값 직접 삭제 — setAPIKey("")는 didSet 가드로 인해 정리 안 됨
        AppSettings.apiKeyDefaults.removeObject(forKey: "opencodeAPIKey")
        AppSettings.apiKeyDefaults.removeObject(forKey: "deepseekAPIKey")
    }

    // MARK: - 기본 모델 등록

    func testDeepSeekDefaultModelsRegistered() {
        let chat = ModelCatalog.defaultModels.first { $0.id == "deepseek-chat" && $0.provider == .deepseek }
        let reasoner = ModelCatalog.defaultModels.first { $0.id == "deepseek-reasoner" && $0.provider == .deepseek }
        XCTAssertNotNil(chat)
        XCTAssertNotNil(reasoner)
        XCTAssertEqual(chat?.isFree, false, "DeepSeek 유료 모델")
        XCTAssertEqual(reasoner?.isFree, false)
    }

    func testOpenCodeZenDefaultModelsRegistered() {
        let freeIDs: [String] = [
            "opencode/big-pickle",
            "opencode/nemotron-3-ultra-free",
            "opencode/mimo-v2.5-free",
        ]
        for id in freeIDs {
            let model = ModelCatalog.defaultModels.first { $0.id == id && $0.provider == .opencode }
            XCTAssertNotNil(model, "\(id) 등록됨")
            XCTAssertEqual(model?.isFree, true, "\(id)는 무료 모델")
        }

        let paidIDs: [String] = ["opencode/deepseek-v4-flash", "opencode/deepseek-v4-pro"]
        for id in paidIDs {
            let model = ModelCatalog.defaultModels.first { $0.id == id && $0.provider == .opencode }
            XCTAssertNotNil(model, "\(id) 등록됨")
            XCTAssertEqual(model?.isFree, false, "\(id)는 유료 모델")
        }
    }

    // MARK: - 무료 우선순위 정렬 (안정 정렬)

    func testFreeFirstSortsFreeAbovePaid() {
        let paid = AIModel(id: "a-paid", provider: .openAI, displayName: "Paid", isFree: false, contextLimit: 128_000)
        let freeA = AIModel(id: "b-free", provider: .openAI, displayName: "FreeB", isFree: true, contextLimit: 128_000)
        let freeB = AIModel(id: "c-free", provider: .openAI, displayName: "FreeC", isFree: true, contextLimit: 128_000)
        let paid2 = AIModel(id: "d-paid", provider: .openAI, displayName: "PaidD", isFree: false, contextLimit: 128_000)

        let sorted = ModelCatalog.freeFirst([paid, freeA, freeB, paid2]).map(\.id)
        XCTAssertEqual(sorted, ["b-free", "c-free", "a-paid", "d-paid"])
    }

    func testFreeFirstIsStableWithinGroups() {
        let models: [AIModel] = [
            AIModel(id: "m1", provider: .openAI, displayName: "M1", isFree: true, contextLimit: 128_000),
            AIModel(id: "m2", provider: .openAI, displayName: "M2", isFree: false, contextLimit: 128_000),
            AIModel(id: "m3", provider: .openAI, displayName: "M3", isFree: true, contextLimit: 128_000),
        ]
        let ids = ModelCatalog.freeFirst(models).map(\.id)
        // 무료(m1, m3)는 원래 상대 순서 유지, 유료(m2)는 맨 뒤
        XCTAssertEqual(ids, ["m1", "m3", "m2"])
    }

    func testFreeFirstPreservesAllElements() {
        let models: [AIModel] = [
            AIModel(id: "x1", provider: .openAI, displayName: "X1", isFree: false, contextLimit: 1),
            AIModel(id: "x2", provider: .openAI, displayName: "X2", isFree: true, contextLimit: 1),
        ]
        XCTAssertEqual(Set(ModelCatalog.freeFirst(models).map(\.id)), Set(["x1", "x2"]))
    }
}
