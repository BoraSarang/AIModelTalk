import XCTest
@testable import AIModelTalk

/// v1.9 T-84 — 커스텀 다중 엔드포인트 테스트
final class CustomEndpointTestsV19: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: CustomEndpointStore!

    override func setUp() {
        super.setUp()
        suiteName = "CustomEndpointTestsV19-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = CustomEndpointStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        super.tearDown()
    }

    func testUpsertAndRemoveMultiple() {
        XCTAssertEqual(store.endpoints.count, 0)

        let lmStudio = CustomEndpoint(name: "LM Studio", baseURL: "http://localhost:1234/v1")
        let openai = CustomEndpoint(name: "OpenAI", baseURL: "https://api.openai.com/v1", apiKey: "sk-test")
        store.upsert(lmStudio)
        store.upsert(openai)
        XCTAssertEqual(store.endpoints.count, 2, "다중 엔드포인트 등록 가능")

        // 이름 수정 (같은 ID upsert)
        var renamed = openai
        renamed.name = "OpenAI 공식"
        store.upsert(renamed)
        XCTAssertEqual(store.endpoints.count, 2)
        XCTAssertEqual(store.endpoints.first { $0.id == openai.id }?.name, "OpenAI 공식")

        // 삭제
        store.remove(id: lmStudio.id)
        XCTAssertEqual(store.endpoints.map(\.name), ["OpenAI 공식"])
    }

    func testCompositeIDRoundTrip() {
        let endpointID = UUID()
        let rawModel = "gpt-4o-mini"
        let composite = CustomEndpoint.compositeID(endpointID: endpointID, modelID: rawModel)

        let parsed = CustomEndpoint.parse(composite)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.endpointID, endpointID)
        XCTAssertEqual(parsed?.rawModelID, rawModel)

        // 일반 모델 ID(프리픽스 없음)는 nil
        XCTAssertNil(CustomEndpoint.parse("gpt-4o"))
        // 프리픽스가 UUID가 아니면 nil
        XCTAssertNil(CustomEndpoint.parse("not-a-uuid:gpt-4o"))
    }

    func testLegacyMigrationSeedsFirstEndpoint() {
        // 레거시 단일 설정 시뮬레이션
        defaults.set("http://localhost:1234/v1/", forKey: "customBaseURL")
        defaults.set("sk-legacy", forKey: "customAPIKey")

        let migrated = store.migrateLegacyIfNeeded()
        XCTAssertTrue(migrated)
        XCTAssertEqual(store.endpoints.count, 1)
        XCTAssertEqual(store.endpoints.first?.name, "커스텀")
        XCTAssertEqual(store.endpoints.first?.baseURL, "http://localhost:1234/v1", "trailing slash 제거")
        XCTAssertEqual(store.endpoints.first?.apiKey, "sk-legacy")

        // 재호출 시 플래그로 스킵 — 중복 시드 없음
        XCTAssertFalse(store.migrateLegacyIfNeeded())
        XCTAssertEqual(store.endpoints.count, 1)

        // 사용자가 삭제한 뒤에도 재시드되지 않음
        store.remove(id: store.endpoints[0].id)
        XCTAssertFalse(store.migrateLegacyIfNeeded())
        XCTAssertTrue(store.endpoints.isEmpty)
    }

    func testMigrationSkipsWhenNoLegacyData() {
        XCTAssertFalse(store.migrateLegacyIfNeeded())
        XCTAssertTrue(store.endpoints.isEmpty)
        XCTAssertTrue(defaults.bool(forKey: CustomEndpointStore.migratedFlagKey))
    }
}

// MARK: - v1.9 T-92 커스텀 엔드포인트 모델 자동 편입

@MainActor
final class CustomSyncTestsV19: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var catalog: ModelCatalog!

    override func setUp() {
        super.setUp()
        suiteName = "CustomSyncTestsV19-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        catalog = ModelCatalog(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        catalog = nil
        defaults = nil
        super.tearDown()
    }

    func testMergeCreatesCompositeIDsWithDedup() {
        let ep = CustomEndpoint(name: "LM Studio", baseURL: "http://localhost:1234/v1")

        let first = catalog.syncCustomEndpoint(["gpt-4o", "", "qwen2.5"], endpoint: ep)
        XCTAssertEqual(first.added, 2, "빈 ID는 건너뛴다")
        XCTAssertEqual(first.removed, 0)
        XCTAssertTrue(catalog.models.contains {
            $0.id == CustomEndpoint.compositeID(endpointID: ep.id, modelID: "gpt-4o")
                && $0.displayName == "gpt-4o (LM Studio)"
        })

        // 재동기화 — 원격에서 사라진 qwen2.5 제거, 신규 new-model 추가
        let second = catalog.syncCustomEndpoint(["gpt-4o", "new-model"], endpoint: ep)
        XCTAssertEqual(second.added, 1)
        XCTAssertEqual(second.removed, 1, "원격에서 사라진 자동 동기화 모델은 제거")
        XCTAssertEqual(
            catalog.models.filter { $0.provider == .custom }.count,
            2,
            "gpt-4o/new-model"
        )
    }

    func testSameModelAcrossEndpointsCoexists() {
        let lm = CustomEndpoint(name: "LM Studio", baseURL: "http://localhost:1234/v1")
        let openai = CustomEndpoint(name: "OpenAI", baseURL: "https://api.openai.com/v1")

        _ = catalog.syncCustomEndpoint(["gpt-4o"], endpoint: lm)
        _ = catalog.syncCustomEndpoint(["gpt-4o"], endpoint: openai).added

        // 같은 raw ID라 엔드포인트별 복합 ID로 공존 — 비교 모드에서 각각 선택 가능
        let customModels = catalog.models.filter { $0.provider == .custom }
        XCTAssertEqual(customModels.count, 2)
        XCTAssertNotEqual(customModels[0].id, customModels[1].id)

        // ProviderEntry 매칭으로 각자의 섹션에 속하는지
        let entries = ProviderEntry.currentList(endpoints: [lm, openai])
        let fallbackID = entries.compactMap(\.endpoint).first?.id
        for entry in entries where entry.endpoint != nil {
            let own = catalog.models(in: entry, fallbackFirstEndpointID: fallbackID)
            XCTAssertEqual(own.count, 1, "\(entry.title) 섹션에 자기 모델만")
        }
    }
}


// MARK: - v2.1 T-98 원격 삭제 동기화

@MainActor
final class CustomSyncRemovalTestsV21: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var catalog: ModelCatalog!

    override func setUp() {
        super.setUp()
        suiteName = "CustomSyncRemovalV21-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        catalog = ModelCatalog(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        catalog = nil
        defaults = nil
        super.tearDown()
    }

    func testStaleRemoteModelRemovedOnResync() {
        let ep = CustomEndpoint(name: "LM Studio", baseURL: "http://localhost:1234/v1")

        _ = catalog.syncCustomEndpoint(["old-model", "kept-model"], endpoint: ep)
        XCTAssertEqual(catalog.models.filter { $0.provider == .custom }.count, 2)

        // 원격에서 old-model 사라짐 → 재동기화 시 제거
        let result = catalog.syncCustomEndpoint(["kept-model", "fresh-model"], endpoint: ep)
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.removed, 1)

        let ids = Set(catalog.models.filter { $0.provider == .custom }.map(\.id))
        XCTAssertFalse(ids.contains(CustomEndpoint.compositeID(endpointID: ep.id, modelID: "old-model")))
        XCTAssertTrue(ids.contains(CustomEndpoint.compositeID(endpointID: ep.id, modelID: "kept-model")))

        // 수동 추가 모델(스냅샷 밖)은 몇 번을 거쳐도 보호됨
        let manual = AIModel(
            id: CustomEndpoint.compositeID(endpointID: ep.id, modelID: "my-alias"),
            provider: .custom,
            displayName: "my-alias (LM Studio)"
        )
        catalog.models.append(manual)

        _ = catalog.syncCustomEndpoint(["kept-model", "fresh-model", "another"], endpoint: ep)
        XCTAssertTrue(catalog.models.contains { $0.id == manual.id }, "스냅샷 밖 수동 모델은 제거되지 않는다")
    }
}
