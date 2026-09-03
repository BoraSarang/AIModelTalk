import XCTest
@testable import AIModelTalk

/// v2.1 T-93 — 신규 공급자 4종 메타데이터 테스트
@MainActor
final class ProviderTestsV21: XCTestCase {

    func testNewProvidersRequireKeysAndHaveBaseURLs() {
        let newOnes: [Provider] = [.openAI, .anthropic, .vercelGateway, .tokenRouter]
        for provider in newOnes {
            XCTAssertTrue(provider.requiresAPIKey, "\(provider.rawValue)는 API 키 필수")
            XCTAssertFalse(provider.baseURL.isEmpty, "\(provider.rawValue) baseURL 등록됨")
            XCTAssertTrue(provider.baseURL.hasPrefix("https://"))
        }
    }

    func testCompatibilityFlags() {
        XCTAssertTrue(Provider.openAI.isOpenAICompatible)
        XCTAssertTrue(Provider.vercelGateway.isOpenAICompatible)
        XCTAssertTrue(Provider.tokenRouter.isOpenAICompatible)
        XCTAssertFalse(Provider.anthropic.isOpenAICompatible, "Anthropic은 전용 Messages API")
        XCTAssertFalse(Provider.gemini.isOpenAICompatible)
    }

    func testAPIKeyURLsPresent() {
        XCTAssertEqual(Provider.openAI.apiKeyURL, "https://platform.openai.com/api-keys")
        XCTAssertEqual(Provider.anthropic.apiKeyURL, "https://console.anthropic.com/settings/keys")
        XCTAssertNotNil(Provider.vercelGateway.apiKeyURL)
        XCTAssertNotNil(Provider.tokenRouter.apiKeyURL)
    }

    func testSettingsKeysUniqueAndPersistable() {
        let all = Provider.allCases.map(\.settingsKey).filter { !$0.isEmpty }
        XCTAssertEqual(Set(all).count, all.count, "저장 키 중복 없음")

        // AppSettings 스위치 정렬 확인 — 신규 키 getter가 기본값 반환
        let settings = AppSettings.shared
        settings.setAPIKey("sk-test-openai-key-1234567890abcdef", for: .openAI)
        XCTAssertEqual(settings.apiKey(for: .openAI), "sk-test-openai-key-1234567890abcdef")
        // 테스트 값 직접 삭제 — setAPIKey("")는 didSet 가드로 인해 정리 안 됨
        AppSettings.apiKeyDefaults.removeObject(forKey: "openAIAPIKey")
    }
}

// MARK: - v2.1 T-94 Anthropic SSE 이벤트 파싱

extension ProviderTestsV21 {

    func testParseAnthropicTextDelta() {
        let payload = #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"안녕하세요"}}"#
        let parsed = AIModelTalk.AnthropicClient.parseAnthropicEvent(payload)
        XCTAssertEqual(parsed.text, "안녕하세요")
        XCTAssertNil(parsed.inputTokens)
        XCTAssertNil(parsed.outputTokens)
    }

    func testParseAnthropicUsageEvents() {
        let start = #"{"type":"message_start","message":{"usage":{"input_tokens":25,"output_tokens":1}}}"#
        let delta = #"{"type":"message_delta","delta":{"stop_reason":"end_turn","usage":{"output_tokens":180}}}"#
        let ping  = #"{"type":"ping"}"#

        XCTAssertEqual(AIModelTalk.AnthropicClient.parseAnthropicEvent(start).inputTokens, 25)
        XCTAssertEqual(AIModelTalk.AnthropicClient.parseAnthropicEvent(delta).outputTokens, 180)
        XCTAssertNil(AIModelTalk.AnthropicClient.parseAnthropicEvent(ping).text, "ping 등 기타 이벤트 무시")
        XCTAssertNil(AIModelTalk.AnthropicClient.parseAnthropicEvent("not json").text)
    }
}
