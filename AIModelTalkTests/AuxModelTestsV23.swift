import XCTest
@testable import AIModelTalk

/// v2.3 T-118 — 보조 모델 (자동 감지·스펙 해석·제목 정제)
final class AuxModelTestsV23: XCTestCase {

    private func model(_ id: String, provider: Provider = .openAI) -> AIModel {
        AIModel(id: id, provider: provider, displayName: id)
    }

    // MARK: - 자동 감지

    func testAutoDetectPrefersFlashThenMini() {
        let flash = ChatViewModel.autoDetectAuxiliaryModel(from: [model("gpt-4o"), model("gemini-2.0-flash", provider: .gemini)])
        XCTAssertEqual(flash?.id, "gemini-2.0-flash", "flash 우선")

        let mini = ChatViewModel.autoDetectAuxiliaryModel(from: [model("gpt-4o-mini"), model("llama-3.3")])
        XCTAssertEqual(mini?.id, "gpt-4o-mini", "flash 없으면 mini")

        XCTAssertNil(ChatViewModel.autoDetectAuxiliaryModel(from: [model("gpt-4o"), model("claude-opus")]), "둘 다 없으면 nil — 세션 모델 폴백")
    }

    // MARK: - 스펙 해석

    func testResolveModelSpec() {
        let catalog = [model("gpt-4o"), model("gemini-2.0-flash", provider: .gemini)]
        let resolved = ChatViewModel.resolveModel(spec: "gemini:gemini-2.0-flash", catalog: catalog)
        XCTAssertEqual(resolved?.provider, .gemini)

        XCTAssertNil(ChatViewModel.resolveModel(spec: "no-colon", catalog: catalog))
        XCTAssertNil(ChatViewModel.resolveModel(spec: "gemini:not-exist", catalog: catalog))
    }

    // MARK: - 제목 정제

    func testCleanedTitleStripsNoise() {
        XCTAssertEqual(ChatViewModel.cleanedTitle(from: "\"표 정리 선호 대화\""), "표 정리 선호 대화")
        XCTAssertEqual(ChatViewModel.cleanedTitle(from: "```제목```"), "제목")
        XCTAssertEqual(ChatViewModel.cleanedTitle(from: "줄바꿈\n포함 제목"), "줄바꿈 포함 제목")
        XCTAssertNil(ChatViewModel.cleanedTitle(from: "   "))
    }

    func testCleanedTitleLengthLimit() {
        let long = String(repeating: "가", count: 40)
        let cleaned = ChatViewModel.cleanedTitle(from: long)
        XCTAssertEqual(cleaned, String(repeating: "가", count: 24) + "…")
    }
}
