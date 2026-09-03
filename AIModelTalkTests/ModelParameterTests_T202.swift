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

    // MARK: - ModelParams

    func testModelParamsHasAny() {
        XCTAssertFalse(ModelParams.none.hasAny)
        XCTAssertTrue(ModelParams(temperature: 0.7, topP: nil, maxTokens: nil).hasAny)
        XCTAssertTrue(ModelParams(temperature: nil, topP: 0.9, maxTokens: nil).hasAny)
        XCTAssertTrue(ModelParams(temperature: nil, topP: nil, maxTokens: 512).hasAny)
    }

    func testModelParamsEquatable() {
        let a = ModelParams(temperature: 0.7, topP: nil, maxTokens: 512)
        let b = ModelParams(temperature: 0.7, topP: nil, maxTokens: 512)
        let c = ModelParams(temperature: 0.7, topP: 0.9, maxTokens: 512)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - 비교 성능 메트릭 (T-202)

    func testTokensPerSecondComputed() {
        var r = ComparisonResult(model: AIModel(id: "m", provider: .groq, displayName: "m"))
        XCTAssertNil(r.tokensPerSecond) // completion/total 없음
        r.totalTime = 2.0
        r.completionTokens = 40
        XCTAssertEqual(r.tokensPerSecond!, 20.0, accuracy: 0.0001)
    }

    func testTokensPerSecondNilWhenMissing() {
        var r = ComparisonResult(model: AIModel(id: "m", provider: .groq, displayName: "m"))
        r.completionTokens = 0
        r.totalTime = 3.0
        XCTAssertNil(r.tokensPerSecond) // 토큰 0 → nil
        r.completionTokens = 30
        r.totalTime = 0
        XCTAssertNil(r.tokensPerSecond) // 시간 0 → nil
    }
}