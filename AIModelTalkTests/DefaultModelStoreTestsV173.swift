import XCTest
@testable import AIModelTalk

/// 기본 모델 저장소 테스트 (v1.7.3 T-66) — UserDefaults suite 격리
final class DefaultModelStoreTestsV173: XCTestCase {

    private func makeStore() -> (DefaultModelStore, String) {
        let name = "DefaultModelStoreTests-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return (DefaultModelStore(defaults: suite), name)
    }

    private var sampleA: AIModel {
        AIModel(id: "default-test-a", provider: .gemini, displayName: "기본 A")
    }

    private var sampleB: AIModel {
        AIModel(id: "default-test-b", provider: .openRouter, displayName: "기본 B")
    }

    func testSaveAndLoadRoundTrip() {
        var (store, domain) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }

        XCTAssertNil(store.model, "초기 상태는 기본 모델 없음")

        store.model = sampleA
        let loaded = store.model
        XCTAssertEqual(loaded?.provider, .gemini)
        XCTAssertEqual(loaded?.id, "default-test-a")
    }

    func testReplaceOverwritesPreviousDefault() {
        var (store, domain) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }

        store.model = sampleA
        store.model = sampleB

        XCTAssertEqual(store.model?.id, "default-test-b", "재지정 시 이전 기본 모델을 대체한다")
    }

    func testNilClearsStoredModel() {
        var (store, domain) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }

        store.model = sampleA
        XCTAssertNotNil(store.model)

        store.model = nil
        XCTAssertNil(store.model, "nil 저장으로 해제된다")
    }
}
