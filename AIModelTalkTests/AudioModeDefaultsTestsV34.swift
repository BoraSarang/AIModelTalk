import XCTest
@testable import AIModelTalk

/// v0.3.3 — 오디오 모드 기본값 테스트 (T-332)
/// audioModels 구성·추천 기본 활성화·NIM 오디오 경로 검증
@MainActor
final class AudioModeDefaultsTestsV34: XCTestCase {

    override func setUp() {
        super.setUp()
        ModelCatalog.shared.enabledOverrides = [:]
    }

    override func tearDown() {
        ModelCatalog.shared.enabledOverrides = [:]
        super.tearDown()
    }

    /// 오디오 모델 목록 — Magpie TTS 1종 이상, NVIDIA 공급자
    func testAudioModelsNotEmpty() {
        XCTAssertFalse(ModelCatalog.audioModels.isEmpty, "오디오 TTS 모델이 등록되어야 함")
        XCTAssertTrue(ModelCatalog.audioModels.allSatisfy { $0.provider == .nvidia })
    }

    /// 추천 세트는 오버라이드 없이 기본 ON
    func testRecommendedDefaultOn() {
        let catalog = ModelCatalog.shared
        let ids = [
            ("opencode/muse-spark-1.3-contributor-free", Provider.opencode),
            ("cohere/north-mini-code:free", Provider.openRouter),
            ("qwen/qwen3-coder-480b-a35b-instruct", Provider.nvidia),
            ("opencode/big-pickle", Provider.opencode),
        ]
        for (id, provider) in ids {
            guard let model = catalog.model(id: id, provider: provider) else {
                XCTFail("추천 모델 미등록: \(provider.rawValue):\(id)")
                continue
            }
            XCTAssertTrue(catalog.isEnabled(model), "\(id)는 기본 활성화되어야 함")
        }
    }

    /// 추천 밖 모델은 여전히 기본 OFF (v0.2.2 opt-in 유지)
    func testNonRecommendedDefaultOff() {
        let catalog = ModelCatalog.shared
        guard let model = catalog.model(id: "llama-3.3-70b-versatile", provider: .groq) else {
            XCTFail("Groq 기준 모델 미등록")
            return
        }
        XCTAssertFalse(catalog.isEnabled(model), "추천 밖 모델은 기본 해제 유지")
    }

    /// 저장된 명시 OFF는 추천 기본 ON보다 우선
    func testStoredOverrideWinsOverDefault() {
        let catalog = ModelCatalog.shared
        guard let model = catalog.model(id: "opencode/big-pickle", provider: .opencode) else {
            XCTFail("Big Pickle 미등록")
            return
        }
        catalog.setEnabled(model, false)
        XCTAssertFalse(catalog.isEnabled(model), "사용자가 끈 모델은 꺼진 채 유지")
    }

    /// NIM 오디오 경로는 integrate base + /audio/speech (호출부가 조합)
    func testAudioBaseURL() {
        XCTAssertEqual(AudioClient.baseURL(for: .nvidia), "https://integrate.api.nvidia.com/v1")
    }

    /// NVIDIA 모델 ID는 wire 변환 없이 그대로 전송
    func testAudioWireModelIDPassthrough() {
        XCTAssertEqual(Provider.wireModelID("nvidia/magpie-tts", for: .nvidia), "nvidia/magpie-tts")
    }
}
