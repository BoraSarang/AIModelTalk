import XCTest
@testable import AIModelTalk

/// v3.2 — OpenCode Zen 모델 ID wire 변환 테스트 (T-153)
/// `opencode/big-pickle` → API에는 `big-pickle`만 전송해야 함.
@MainActor
final class ProviderWireModelIDTestsV32: XCTestCase {

    // MARK: - OpenCode Zen: 프리픽스 제거

    func testOpenCodeStripsProviderPrefix() {
        XCTAssertEqual(Provider.wireModelID("opencode/big-pickle", for: .opencode), "big-pickle")
        XCTAssertEqual(Provider.wireModelID("opencode/nemotron-3-ultra-free", for: .opencode), "nemotron-3-ultra-free")
        XCTAssertEqual(Provider.wireModelID("opencode/deepseek-v4-pro", for: .opencode), "deepseek-v4-pro")
    }

    func testOpenCodeNoPrefixLeftUnchanged() {
        // 프리픽스 없는 ID(사용자 직접 추가 등)는 그대로
        XCTAssertEqual(Provider.wireModelID("big-pickle", for: .opencode), "big-pickle")
    }

    func testOpenCodeEnterprisePathUnchangedIfNotPrefixed() {
        // 엔터프라이즈/커스텀 네임스페이스 ID는 그대로 두어야 함
        XCTAssertEqual(Provider.wireModelID("my-org/big-pickle", for: .opencode), "my-org/big-pickle")
    }

    // MARK: - 타 공급자: 불변

    func testOtherProvidersUnchanged() {
        XCTAssertEqual(Provider.wireModelID("google/gemini-2.5-flash-preview:free", for: .openRouter), "google/gemini-2.5-flash-preview:free")
        XCTAssertEqual(Provider.wireModelID("nvidia/llama-3.3-nemotron-super-49b-v1.5", for: .nvidia), "nvidia/llama-3.3-nemotron-super-49b-v1.5")
        XCTAssertEqual(Provider.wireModelID("deepseek-chat", for: .deepseek), "deepseek-chat")
        XCTAssertEqual(Provider.wireModelID("gpt-4o", for: .openAI), "gpt-4o")
        XCTAssertEqual(Provider.wireModelID("gemini-3.6-flash", for: .gemini), "gemini-3.6-flash")
        XCTAssertEqual(Provider.wireModelID("llama3.2:latest", for: .ollama), "llama3.2:latest")
    }

    func testWireModelIDNotEmptyAndNoLeadingWhitespace() {
        for m in ["opencode/big-pickle", "opencode/deepseek-v4-flash"] {
            let wired = Provider.wireModelID(m, for: .opencode)
            XCTAssertFalse(wired.isEmpty)
            XCTAssertEqual(wired, wired.trimmingCharacters(in: .whitespaces))
        }
    }

    // MARK: - 팩토리 통합 (전송 시점 반영)

    func testFactoryForwardsStrippedModelToOpenAIClient() throws {
        AppSettings.shared.setAPIKey("sk-test-opencode-key-abcdef1234567890", for: .opencode)
        defer { AppSettings.apiKeyDefaults.removeObject(forKey: "opencodeAPIKey") }

        let client = try AIClientFactory.client(provider: .opencode, modelID: "opencode/big-pickle")
        guard let openAI = client as? OpenAICompatibleClient else {
            return XCTFail("opencode 클라이언트는 OpenAICompatibleClient여야 함")
        }
        XCTAssertEqual(openAI.model, "big-pickle")
    }

    func testFactoryLeavesOpenRouterPrefixedModelUnchanged() throws {
        // OpenRouter는 프리픽스(provider/model)가 wire ID 그대로 — 변환 없음
        AppSettings.shared.setAPIKey("sk-test-openrouter-key-abcdef1234567890", for: .openRouter)
        defer { AppSettings.apiKeyDefaults.removeObject(forKey: "openRouterAPIKey") }

        let client = try AIClientFactory.client(provider: .openRouter, modelID: "google/gemini-2.5-flash-preview:free")
        guard let openAI = client as? OpenAICompatibleClient else {
            return XCTFail("openRouter 클라이언트는 OpenAICompatibleClient여야 함")
        }
        XCTAssertEqual(openAI.model, "google/gemini-2.5-flash-preview:free")
    }
}
