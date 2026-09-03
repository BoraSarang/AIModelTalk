import XCTest
@testable import AIModelTalk

/// v1.9 T-85 — ProviderEntry (내장 공급자 + 커스텀 엔드포인트 통합 목록) 테스트
@MainActor
final class ProviderEntryTestsV19: XCTestCase {

    private func makeEndpoint(_ name: String) -> CustomEndpoint {
        CustomEndpoint(name: name, baseURL: "http://localhost:1234/v1")
    }

    func testCurrentListExcludesCustomAndAppendsEndpoints() {
        let lm = makeEndpoint("LM Studio")
        let openai = makeEndpoint("OpenAI")
        let entries = ProviderEntry.currentList(endpoints: [lm, openai])

        // 내장 공급자 전체 (.custom 제외) — v2.1에서 4종 확장으로 동적 계산
        let expectedBuiltin = Provider.allCases.filter { $0 != .custom }.count
        XCTAssertEqual(entries.count, expectedBuiltin + 2)
        XCTAssertFalse(entries.contains { $0.endpoint == nil && $0.provider == .custom })
        XCTAssertTrue(entries.contains { $0.title == "NVIDIA" })

        // 엔드포인트는 목록 뒤에 추가, 회색 점
        XCTAssertEqual(entries.suffix(2).map(\.title), ["LM Studio", "OpenAI"])
        XCTAssertTrue(entries.suffix(2).allSatisfy { $0.colorHex == "#8E8E93" })

        // ID 충돌 없음 — 엔드포인트 id는 "custom:" 프리픽스
        XCTAssertNotEqual(entries[0].id, entries.last!.id)
    }

    func testBelongsToBuiltinAndComposite() {
        let ep = makeEndpoint("LM Studio")
        var entryList = ProviderEntry.currentList(endpoints: [ep])
        let fallbackID = entryList.compactMap(\.endpoint).first?.id

        // 내장 모델 ↔ 내장 엔트리
        let nvidiaModel = AIModel(id: "test-nv", provider: .nvidia, displayName: "NV")
        XCTAssertTrue(nvidiaModel.belongs(to: entryList.first { $0.provider == .nvidia }!, fallbackFirstEndpointID: fallbackID))
        XCTAssertFalse(nvidiaModel.belongs(to: entryList.first { $0.provider == .groq }!, fallbackFirstEndpointID: fallbackID))
        XCTAssertFalse(nvidiaModel.belongs(to: entryList.last!, fallbackFirstEndpointID: fallbackID), "내장 모델은 엔드포인트 엔트리에 속하지 않음")

        // 복합 ID 커스텀 모델 ↔ 해당 엔드포인트 엔트리
        let customModel = AIModel(
            id: CustomEndpoint.compositeID(endpointID: ep.id, modelID: "gpt-4o"),
            provider: .custom,
            displayName: "GPT-4o"
        )
        let epEntry = entryList.last!
        XCTAssertTrue(customModel.belongs(to: epEntry, fallbackFirstEndpointID: fallbackID))

        // 다른 엔드포인트 엔트리에는 미속속
        let other = makeEndpoint("다른 서버")
        entryList = ProviderEntry.currentList(endpoints: [ep, other])
        XCTAssertFalse(customModel.belongs(to: entryList.last!, fallbackFirstEndpointID: nil))
    }

    func testLegacyPrefixlessModelFallsBackToFirstEndpoint() {
        let ep = makeEndpoint("커스텀")
        let entries = ProviderEntry.currentList(endpoints: [ep])
        let fallbackID = entries.compactMap(\.endpoint).first?.id

        // 구형 모델: 프리픽스 없는 단순 ID
        let legacy = AIModel(id: "gpt-4o", provider: .custom, displayName: "GPT-4o")
        XCTAssertNil(legacy.customEndpointID)
        XCTAssertTrue(legacy.belongs(to: entries.last!, fallbackFirstEndpointID: fallbackID),
                      "프리픽스 없는 구형 모델은 첫 엔드포인트로 폴백 배정")

        // 폴백 대상이 없으면 어디에도 속하지 않음
        let builtinOnly = ProviderEntry.currentList(endpoints: [])
        XCTAssertFalse(legacy.belongs(to: builtinOnly[0], fallbackFirstEndpointID: nil))
    }

    func testCatalogModelsInEntry() {
        let suiteName = "ProviderEntryTestsV19-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let catalog = ModelCatalog(defaults: defaults)
        catalog.models = [
            AIModel(id: "nv-1", provider: .nvidia, displayName: "NV1"),
            AIModel(id: "gq-1", provider: .groq, displayName: "GQ1")
        ]
        let ep = makeEndpoint("LM Studio")
        catalog.addModel(AIModel(
            id: CustomEndpoint.compositeID(endpointID: ep.id, modelID: "local-model"),
            provider: .custom,
            displayName: "Local Model"
        ))
        catalog.addModel(AIModel(id: "legacy-model", provider: .custom, displayName: "Legacy"))

        let entries = ProviderEntry.currentList(endpoints: [ep])
        let fallbackID = entries.compactMap(\.endpoint).first?.id

        // NVIDIA 엔트리: nv-1만
        let nvidiaEntry = entries.first { $0.provider == .nvidia }!
        XCTAssertEqual(catalog.models(in: nvidiaEntry).map(\.id), ["nv-1"])

        // LM Studio 엔트리: 복합 ID + 구형 폴백 둘 다
        let epEntry = entries.last!
        let inEP = Set(catalog.models(in: epEntry, fallbackFirstEndpointID: fallbackID).map(\.id))
        XCTAssertTrue(inEP.contains(CustomEndpoint.compositeID(endpointID: ep.id, modelID: "local-model")))
        XCTAssertTrue(inEP.contains("legacy-model"), "구형 모델은 첫 엔드포인트 섹션에 표시됨")
    }
}
