import XCTest
@testable import AIModelTalk

/// v0.2.0 T-201 — 대화 내 병렬 모델 비교 채택 변환 테스트
final class ParallelComparisonTests_T201: XCTestCase {

    func testAssistantMessageConverterPreservesLane() {
        let model = AIModel(id: "model-a", provider: .gemini, displayName: "모델 A")
        let lane = AIModelTalk.ComparisonResult(
            model: model,
            text: "비교 결과 답변",
            isStreaming: false,
            ttft: 0.5,
            totalTime: 2.0,
            error: nil,
            promptTokens: 120,
            completionTokens: 88
        )

        let msg = ChatViewModel.assistantMessage(fromLane: lane)

        XCTAssertEqual(msg.role, .assistant)
        XCTAssertEqual(msg.content, "비교 결과 답변")
        XCTAssertEqual(msg.provider, .gemini)
        XCTAssertEqual(msg.modelID, "model-a")
        XCTAssertFalse(msg.isStreaming)
        XCTAssertEqual(msg.promptTokens, 120)
        XCTAssertEqual(msg.completionTokens, 88)
    }

    func testAssistantMessageConverterCapturesEmptyText() {
        let model = AIModel(id: "m", provider: .ollama, displayName: "로컬")
        let lane = AIModelTalk.ComparisonResult(model: model, text: "", isStreaming: false, ttft: nil, totalTime: nil, error: nil, promptTokens: nil, completionTokens: nil)
        let msg = ChatViewModel.assistantMessage(fromLane: lane)
        XCTAssertEqual(msg.content, "")
        XCTAssertNil(msg.promptTokens)
    }

    func testRankedEntriesOrdersBySpeedWhenNoScores() {
        // 채점 전 — 오류 없는 래인이 먼저, 이후 총시간 오름차순
        let fast = AIModelTalk.ComparisonResult(model: AIModel(id: "f", provider: .nvidia, displayName: "빠름"), text: "x", isStreaming: false, ttft: 0.1, totalTime: 1.0, error: nil, promptTokens: nil, completionTokens: nil)
        let slow = AIModelTalk.ComparisonResult(model: AIModel(id: "s", provider: .nvidia, displayName: "느림"), text: "x", isStreaming: false, ttft: 0.5, totalTime: 5.0, error: nil, promptTokens: nil, completionTokens: nil)
        let failed = AIModelTalk.ComparisonResult(model: AIModel(id: "e", provider: .nvidia, displayName: "실패"), text: "", isStreaming: false, ttft: nil, totalTime: nil, error: "[E-MAC-KEY-1001] 키 없음", promptTokens: nil, completionTokens: nil)

        let ranked = ComparisonService.rankedResults([failed, slow, fast], scores: [])
        XCTAssertEqual(ranked.map(\.model.id), ["f", "s", "e"])
    }
}