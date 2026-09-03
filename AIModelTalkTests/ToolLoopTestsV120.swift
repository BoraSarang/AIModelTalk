import XCTest
@testable import AIModelTalk

/// v2.4 T-120 — 도구 실행 파이프라인 (루프·권한 게이트·한도)
@MainActor
final class ToolLoopTestsV120: XCTestCase {

    /// 스트림 위임 분기(빈 도구 목록 = 도구 없음 처리)를 피하기 위한 실제 정의
    private let sampleTools = [
        LLMToolDefinition(name: "read_file", description: "", parametersJSON: "{}"),
        LLMToolDefinition(name: "delete_file", description: "", parametersJSON: "{}"),
        LLMToolDefinition(name: "loop", description: "", parametersJSON: "{}")
    ]

    /// 시나리오 주입형 가짜 클라이언트 — 라운드별 이벤트 시퀀스 반환
    private final class FakeToolClient: ChatClient {
        var supportsTools: Bool { true }
        private let rounds: [[ChatStreamEvent]]

        init(rounds: [[ChatStreamEvent]]) {
            self.rounds = rounds
        }

        func stream(messages: [ChatMessage], systemPrompt: String?, onUsage: ((Int?, Int?) -> Void)?) -> AsyncThrowingStream<String, Error> {
            AsyncThrowingStream { $0.finish() }
        }

        func rawStreamWithTools(messages: [ChatMessage], systemPrompt: String?, temperature: Double?,
                                tools: [LLMToolDefinition], onUsage: ((Int?, Int?) -> Void)?) -> AsyncThrowingStream<ChatStreamEvent, Error> {
            let index = min(callCount, rounds.count - 1)
            let events = rounds[index]
            callCount += 1
            return AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        }

        private var callCount = 0
    }

    func testLoopExecutesToolsAndFinishes() async throws {
        // 1라운드: 도구 호출 → 2라운드: 최종 답변
        let client = FakeToolClient(rounds: [
            [.text("도구를 확인해 볼게요. "), .toolCalls([LLMToolCall(id: "t1", name: "read_file", argumentsJSON: #"{"path":"/tmp/a"}"#)])],
            [.text("완료했습니다.")]
        ])
        var texts = ""
        var records: [ToolLoopService.ExecutionRecord] = []

        let result = try await ToolLoopService.run(
            client: client,
            messages: [ChatMessage(role: .user, content: "파일 읽어줘")],
            systemPrompt: nil, temperature: nil, tools: sampleTools,
            connections: [],
            permissionGate: { _ in .allowed },
            onText: { texts += $0 },
            onToolRun: { records.append($0) },
            onUsage: nil)

        let first = try XCTUnwrap(result.first, "실행 기록 1건 필요")
        XCTAssertEqual(first.toolName, "read_file")
        XCTAssertTrue(first.isError, "연결 없는 환경이므로 오류 카드")
        XCTAssertTrue(first.resultPreview?.contains("연결되지 않았습니다") ?? false, "연결 없으면 오류 카드")
        XCTAssertEqual(records.count, 1)
        XCTAssertTrue(texts.contains("도구를 확인해"), "1라운드 텍스트 전달")
    }

    func testLoopRespectsRoundLimit() async {
        // 매 라운드 도구 호출만 반복 → 한도 초과 오류
        let infiniteCalls: [[ChatStreamEvent]] = (0..<8).map { _ in
            [.toolCalls([LLMToolCall(id: "x", name: "loop", argumentsJSON: "{}")])]
        }
        let client = FakeToolClient(rounds: infiniteCalls)

        do {
            _ = try await ToolLoopService.run(
                client: client,
                messages: [ChatMessage(role: .user, content: "반복")],
                systemPrompt: nil, temperature: nil, tools: sampleTools,
                connections: [],
                permissionGate: { _ in .allowed },
                onText: { _ in }, onToolRun: { _ in }, onUsage: nil)
            XCTFail("한도 초과 예외 누락")
        } catch {
            XCTAssertTrue(error is ToolLoopService.LoopError)
        }
    }

    func testPermissionDenyRecordsCard() async throws {
        let client = FakeToolClient(rounds: [
            [.toolCalls([LLMToolCall(id: "d1", name: "delete_file", argumentsJSON: "{}")])],
            [.text("거부되었습니다.")]
        ])
        var records: [ToolLoopService.ExecutionRecord] = []
        _ = try await ToolLoopService.run(
            client: client,
            messages: [ChatMessage(role: .user, content: "삭제해줘")],
            systemPrompt: nil, temperature: nil, tools: sampleTools,
            connections: [],
            permissionGate: { _ in .denied },
            onText: { _ in },
            onToolRun: { records.append($0) },
            onUsage: nil)

        let first = try XCTUnwrap(records.first, "거부 카드 1건 필요")
        XCTAssertEqual(first.permissionDecision, "denied")
        XCTAssertEqual(first.resultPreview, "사용자가 실행을 거부했습니다.")
    }

    // MARK: - OpenAI 도구 프래그먼트 인코딩

    func testAPIToolSchemaEncoding() throws {
        let definition = LLMToolDefinition(
            name: "read_file",
            description: "파일 읽기",
            parametersJSON: #"{"type":"object","properties":{"path":{"type":"string","description":"경로"}}}"#)
        let apiTool = OpenAICompatibleClient.APITool(from: definition)
        let data = try JSONEncoder().encode(apiTool)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["type"] as? String, "function")
        let function = try XCTUnwrap(obj["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, "read_file")
        let schema = try XCTUnwrap(function["parameters"] as? [String: Any])
        XCTAssertEqual(schema["type"] as? String, "object")

        // 잘못된 스키마 → 최소 스키마 폴백
        let broken = LLMToolDefinition(name: "x", description: "", parametersJSON: "not-json")
        let fallback = OpenAICompatibleClient.APITool(from: broken)
        let fbData = try JSONEncoder().encode(fallback)
        let fbObj = try XCTUnwrap((try XCTUnwrap(JSONSerialization.jsonObject(with: fbData) as? [String: Any]))["function"] as? [String: Any])
        let fbSchema = try XCTUnwrap(fbObj["parameters"] as? [String: Any])
        XCTAssertEqual(fbSchema["type"] as? String, "object", "폴백 최소 스키마")
    }
}
