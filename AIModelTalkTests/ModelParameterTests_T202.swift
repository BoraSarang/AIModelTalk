import XCTest
@testable import AIModelTalk

/// v0.2.0 T-202 — topP/maxTokens 파라미터 전달 인프라 테스트
/// OpenAI 호환 인코딩에서 top_p/max_tokens가 요청 바디에 정확히 반영되는지 검증.
final class ModelParameterTests_T202: XCTestCase {

    func testEncodeBodyIncludesAllParams() throws {
        let data = try OpenAICompatibleClient.encodeRequestBody(
            model: "m", apiMessages: [],
            streamOptions: .init(include_usage: true),
            temperature: 0.7, topP: 0.9, maxTokens: 512)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["temperature"] as? Double, 0.7)
        XCTAssertEqual(json["top_p"] as? Double, 0.9)
        XCTAssertEqual(json["max_tokens"] as? Int, 512)
    }

    func testEncodeBodyOmitsUnsetParams() throws {
        let data = try OpenAICompatibleClient.encodeRequestBody(
            model: "m", apiMessages: [],
            streamOptions: .init(include_usage: true),
            temperature: nil, topP: nil, maxTokens: nil)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNil(json["temperature"])
        XCTAssertNil(json["top_p"])
        XCTAssertNil(json["max_tokens"])
    }

    func testEncodeBodyPartialParams() throws {
        // topP만 설정 → top_p만 나가고 temperature/max_tokens는 생략
        let data = try OpenAICompatibleClient.encodeRequestBody(
            model: "m", apiMessages: [],
            streamOptions: .init(include_usage: true),
            temperature: nil, topP: 0.9, maxTokens: nil)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNil(json["temperature"])
        XCTAssertEqual(json["top_p"] as? Double, 0.9)
        XCTAssertNil(json["max_tokens"])
    }

    /// 온도만(T-111 이전 동작) 설정해도 인코딩이 깨지지 않아야 한다 (회귀)
    func testEncodeBodyTemperatureOnly() throws {
        let data = try OpenAICompatibleClient.encodeRequestBody(
            model: "m", apiMessages: [],
            streamOptions: .init(include_usage: true),
            temperature: 1.0)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["temperature"] as? Double, 1.0)
        XCTAssertNil(json["top_p"])
    }
}