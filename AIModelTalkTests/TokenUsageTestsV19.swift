import XCTest
@testable import AIModelTalk

/// v1.9 T-76 — 스트리밍 usage 파싱 + 세션 합계 테스트
final class TokenUsageTestsV19: XCTestCase {

    func testParseTextChunk() {
        let json = #"{"id":"x","choices":[{"delta":{"content":"안녕"},"finish_reason":null}]}"#
        let parsed = OpenAICompatibleClient.parseSSEPayload(json)
        XCTAssertEqual(parsed.text, "안녕")
        XCTAssertNil(parsed.promptTokens)
        XCTAssertNil(parsed.completionTokens)
    }

    func testParseFinalUsageChunk() {
        // usage-only 청크 (choices 빈 배열 — OpenAI include_usage 표준 형식)
        let json = #"{"choices":[],"usage":{"prompt_tokens":123,"completion_tokens":456}}"#
        let parsed = OpenAICompatibleClient.parseSSEPayload(json)
        XCTAssertEqual(parsed.text, nil)
        XCTAssertEqual(parsed.promptTokens, 123)
        XCTAssertEqual(parsed.completionTokens, 456)
    }

    func testParseGarbageReturnsNils() {
        let parsed = OpenAICompatibleClient.parseSSEPayload("<html>error</html>")
        XCTAssertNil(parsed.text)
        XCTAssertNil(parsed.promptTokens)
        XCTAssertNil(parsed.completionTokens)
    }

    func testSessionTotalsIgnoreMissingCounts() {
        let messages: [AIModelTalk.ChatMessage] = [
            AIModelTalk.ChatMessage(role: .user, content: "질문"),
            AIModelTalk.ChatMessage(role: .assistant, content: "답1", promptTokens: 100, completionTokens: 50),
            AIModelTalk.ChatMessage(role: .user, content: "질문2"),
            AIModelTalk.ChatMessage(role: .assistant, content: "답2", promptTokens: 30), // completion 미보고
            AIModelTalk.ChatMessage(role: .assistant, content: "답3")                    // 무실측(구세션 등)
        ]
        let totals = SessionTokens.total(for: messages)
        XCTAssertEqual(totals.prompt, 130)
        XCTAssertEqual(totals.completion, 50)
        XCTAssertEqual(totals.total, 180)
        XCTAssertFalse(totals.isEmpty)
    }

    func testCompactFormatting() {
        XCTAssertEqual(SessionTokens.compact(950), "950")
        XCTAssertEqual(SessionTokens.compact(1234), "1.2k")
        XCTAssertEqual(SessionTokens.compact(0), "0")
    }
}

// MARK: - v2.1 T-95 Gemini usageMetadata

extension TokenUsageTestsV19 {

    func testParseGeminiTextChunk() {
        let json = #"{"candidates":[{"content":{"parts":[{"text":"반갑습니다"}],"role":"model"}}]}"#
        let parsed = OpenAICompatibleClient.parseSSEPayload(json) == (nil, nil, nil)
            ? AIModelTalk.GeminiClient.parseGeminiPayload(json)
            : nil
        XCTAssertEqual(parsed?.text, "반갑습니다")
        XCTAssertNil(parsed?.promptTokens)
    }

    func testParseGeminiUsageChunk() {
        // 마지막 청차: 텍스트 없이 usageMetadata만 오는 경우 포함
        let json = #"{"usageMetadata":{"promptTokenCount":88,"candidatesTokenCount":240}}"#
        let parsed = AIModelTalk.GeminiClient.parseGeminiPayload(json)
        XCTAssertNil(parsed.text)
        XCTAssertEqual(parsed.promptTokens, 88)
        XCTAssertEqual(parsed.completionTokens, 240)
    }

    func testGeminiGarbageReturnsNils() {
        let parsed = AIModelTalk.GeminiClient.parseGeminiPayload("oops")
        XCTAssertNil(parsed.text)
        XCTAssertNil(parsed.promptTokens)
    }
}
