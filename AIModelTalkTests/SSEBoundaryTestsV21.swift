import XCTest
@testable import AIModelTalk

/// v2.1 T-106 — SSE 파싱 경계값 계약 고정
/// parseSSEPayload(OpenAI 호환) / parseAnthropicEvent의 미커버 엣지 케이스.
final class SSEBoundaryTestsV21: XCTestCase {

    // MARK: - parseSSEPayload (OpenAI 호환)

    /// stream_options include_usage의 마지막 청크 — choices 없이 usage만 오는 형태
    func testUsageOnlyChunkWithoutChoices() {
        let payload = #"{"usage":{"prompt_tokens":10,"completion_tokens":5}}"#
        let r = OpenAICompatibleClient.parseSSEPayload(payload)
        XCTAssertNil(r.text)
        XCTAssertEqual(r.promptTokens, 10)
        XCTAssertEqual(r.completionTokens, 5)
    }

    /// choices가 빈 배열인 usage 전용 변형
    func testUsageOnlyChunkWithEmptyChoices() {
        let payload = #"{"choices":[],"usage":{"prompt_tokens":3,"completion_tokens":9}}"#
        let r = OpenAICompatibleClient.parseSSEPayload(payload)
        XCTAssertNil(r.text)
        XCTAssertEqual(r.promptTokens, 3)
        XCTAssertEqual(r.completionTokens, 9)
    }

    /// 빈 델타는 nil이 아니라 빈 문자열 — 호출부 스킵 로직과의 계약
    func testEmptyContentDeltaIsNotNil() {
        let payload = #"{"choices":[{"delta":{"content":""}}]}"#
        let r = OpenAICompatibleClient.parseSSEPayload(payload)
        XCTAssertNotNil(r.text, "빈 델타는 빈 문자열로 반환되어야 함")
        XCTAssertEqual(r.text, "")
        XCTAssertNil(r.promptTokens)
        XCTAssertNil(r.completionTokens)
    }

    /// 방어적 디코딩 계약 (T-106) — 일부 호환 서버의 문자열 숫자 usage는 변환 파싱,
    /// 텍스트 델타는 usage 형식과 무관하게 보존된다.
    func testStringNumberUsageIsCoerced() {
        let payload = #"{"choices":[{"delta":{"content":"안녕"}}],"usage":{"prompt_tokens":"12","completion_tokens":"3"}}"#
        let r = OpenAICompatibleClient.parseSSEPayload(payload)
        XCTAssertEqual(r.text, "안녕", "텍스트는 문자열 숫자와 무관하게 보존")
        XCTAssertEqual(r.promptTokens, 12, "문자열 숫자 usage는 변환 파싱")
        XCTAssertEqual(r.completionTokens, 3)
    }

    /// 깨진 JSON — 전체 nil 폴백
    func testBrokenJSONReturnsAllNils() {
        let r = OpenAICompatibleClient.parseSSEPayload("{not json")
        XCTAssertNil(r.text)
        XCTAssertNil(r.promptTokens)
        XCTAssertNil(r.completionTokens)
    }

    // MARK: - parseAnthropicEvent

    /// ping 및 미지의 이벤트 타입 — 무시 (전부 nil)
    func testAnthropicPingAndUnknownTypeReturnNils() {
        for payload in [#"{"type":"ping"}"#, #"{"type":"future_event_v99"}"#] {
            let r = AnthropicClient.parseAnthropicEvent(payload)
            XCTAssertNil(r.text)
            XCTAssertNil(r.inputTokens)
            XCTAssertNil(r.outputTokens)
        }
    }

    /// message_start — 입력토큰만 추출
    func testAnthropicMessageStartInputTokens() {
        let r = AnthropicClient.parseAnthropicEvent(
            #"{"type":"message_start","message":{"usage":{"input_tokens":21}}}"#)
        XCTAssertEqual(r.inputTokens, 21)
        XCTAssertNil(r.outputTokens)
        XCTAssertNil(r.text)
    }

    /// message_delta — 출력토큰만 추출 (delta.usage 경로)
    func testAnthropicMessageDeltaOutputTokens() {
        let r = AnthropicClient.parseAnthropicEvent(
            #"{"type":"message_delta","delta":{"usage":{"output_tokens":33}}}"#)
        XCTAssertEqual(r.outputTokens, 33)
        XCTAssertNil(r.inputTokens)
        XCTAssertNil(r.text)
    }

    /// 깨진 JSON — 전체 nil 폴백
    func testAnthropicBrokenJSONReturnsAllNils() {
        let r = AnthropicClient.parseAnthropicEvent("{broken")
        XCTAssertNil(r.text)
        XCTAssertNil(r.inputTokens)
        XCTAssertNil(r.outputTokens)
    }
}
