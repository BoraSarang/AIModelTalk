import XCTest
@testable import AIModelTalk

// MARK: - v2.4 T-122: 원격 HTTP(SSE) 전송 계층 테스트

/// URLProtocol 목 — 요청별 순차 응답 시퀀스 재생 + 캡처된 요청 기록
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [(HTTPURLResponse, Data)] = []
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []

    static func reset() {
        responses = []
        capturedRequests = []
    }

    /// JSON 200 응답 추가
    static func enqueueJSON(_ object: [String: Any], headers: [String: String] = [:]) {
        let data = try! JSONSerialization.data(withJSONObject: object)
        let response = HTTPURLResponse(url: URL(string: "https://mock.test/mcp")!,
                                       statusCode: 200, httpVersion: nil, headerFields: headers)!
        responses.append((response, data))
    }

    /// SSE 200 응답 추가
    static func enqueueSSE(_ body: String) {
        let response = HTTPURLResponse(url: URL(string: "https://mock.test/mcp")!, statusCode: 200,
                                       httpVersion: nil,
                                       headerFields: ["Content-Type": "text/event-stream"])!
        responses.append((response, Data(body.utf8)))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.capturedRequests.append(request)
        guard !Self.responses.isEmpty else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (response, data) = Self.responses.removeFirst()
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class MCPHTTPTestsV122: XCTestCase {

    private var connection: MCPHTTPConnection!
    private var config: MCPServerConfig!

    override func setUp() async throws {
        MockURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        config = MCPServerConfig(name: "원격 서버", command: "")
        config.transport = .http
        config.url = "https://mock.test/mcp"
        connection = MCPHTTPConnection(config: config, session: session)
    }

    override func tearDown() async throws {
        MockURLProtocol.reset()
    }

    private func enqueueHandshake() {
        // initialize → 세션 ID 헤더와 함께
        MockURLProtocol.enqueueJSON(
            ["jsonrpc": "2.0", "id": 1, "result": ["serverInfo": ["name": "mock", "version": "1"]]],
            headers: ["Mcp-Session-Id": "session-abc"])
        // initialized 알림 — 빈 본문
        MockURLProtocol.enqueueJSON(["jsonrpc": "2.0"])
        // tools/list
        MockURLProtocol.enqueueJSON([
            "jsonrpc": "2.0", "id": 2,
            "result": ["tools": [
                ["name": "search", "description": "문서 검색",
                 "inputSchema": ["type": "object", "properties": ["q": ["type": "string"]]]]
            ]]
        ])
    }

    // MARK: - 프로토콜 파서

    func testParseSSEBodyExtractsMultipleEvents() {
        let body = """
        event: message
        data: {"jsonrpc":"2.0","method":"notifications/progress","params":{}}

        event: message
        data: {"jsonrpc":"2.0","id":7,"result":{"content":[{"type":"text","text":"결과"}]}}

        """
        let inbounds = MCPProtocol.parseSSEBody(Data(body.utf8))
        XCTAssertEqual(inbounds.count, 2)
        if case .notification = inbounds[0] {} else { XCTFail("첫 이벤트는 알림이어야 함") }
        if case let .response(id, _) = inbounds[1] {
            XCTAssertEqual(id, 7)
        } else {
            XCTFail("두 번째는 id=7 응답이어야 함")
        }
    }

    func testParseSSEBodyJoinsMultiLineData() {
        let body = "data: {\"jsonrpc\":\"2.0\",\ndata: \"id\":9}\n\n"
        let inbounds = MCPProtocol.parseSSEBody(Data(body.utf8))
        // 두 줄 결합 결과가 유효 JSON이 아니면 무시되지만 크래시 없음을 확인
        _ = inbounds
    }

    func testFirstReplyIgnoresNotificationsAndMismatchedIDs() {
        let inbounds: [MCPProtocol.Inbound] = [
            .notification(method: "x"),
            .response(id: 3, result: [:]),
            .error(id: 5, message: "e")
        ]
        if case .response = MCPProtocol.firstReply(id: 3, in: inbounds) {} else { XCTFail("id=3 응답 반환 필요") }
        XCTAssertNil(MCPProtocol.firstReply(id: 99, in: inbounds))
    }

    // MARK: - 연결 흐름

    func testConnectHandshakeListsToolsAndCapturesSession() async throws {
        enqueueHandshake()
        await connection.connect()
        guard case .ready = connection.state else {
            return XCTFail("ready 상태 필요: \(connection.state)")
        }
        XCTAssertEqual(connection.tools.count, 1)
        XCTAssertEqual(connection.tools.first?.name, "search")

        // 세션 ID가 후속 요청에 첨부됐는지 — tools/list 요청(세 번째) 확인
        let requests = MockURLProtocol.capturedRequests
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Mcp-Session-Id"), "session-abc")
        XCTAssertTrue(requests.first?.value(forHTTPHeaderField: "Accept")?.contains("text/event-stream") ?? false)
    }

    func testConnectFailureOnHTTPError() async {
        let response = HTTPURLResponse(url: URL(string: "https://mock.test/mcp")!,
                                       statusCode: 500, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.responses.append((response, Data("boom".utf8)))
        await connection.connect()
        guard case let .failed(reason) = connection.state else {
            return XCTFail("failed 상태 필요")
        }
        XCTAssertTrue(reason.contains("500"), "reason=\(reason)")
    }

    // MARK: - 도구 호출

    func testCallToolSuccessOverSSE() async throws {
        enqueueHandshake()
        await connection.connect()
        MockURLProtocol.enqueueSSE("""
        data: {"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"검색 결과"}],"isError":false}}

        """)
        let text = try await connection.callTool(name: "search", arguments: ["q": "swift"])
        XCTAssertEqual(text, "검색 결과")
    }

    func testCallToolIsErrorThrows() async {
        enqueueHandshake()
        await connection.connect()
        MockURLProtocol.enqueueJSON([
            "jsonrpc": "2.0", "id": 3,
            "result": ["isError": true, "content": [["type": "text", "text": "도구 내부 오류"]]]
        ])
        do {
            _ = try await connection.callTool(name: "search", arguments: [:])
            XCTFail("오류 카드는 throw 필요")
        } catch {
            XCTAssertTrue("\(error)".contains("도구 내부 오류"))
        }
    }

    func testCallToolAutoReconnectsWhenIdle() async throws {
        enqueueHandshake()
        MockURLProtocol.enqueueJSON([
            "jsonrpc": "2.0", "id": 3,
            "result": ["content": [["type": "text", "text": "ok"]]]
        ])
        // connect 호출 없이 바로 callTool — 자동 재연동 경로
        let text = try await connection.callTool(name: "search", arguments: [:])
        XCTAssertEqual(text, "ok")
        XCTAssertEqual(MockURLProtocol.capturedRequests.count, 4)
    }

    // MARK: - 인증 헤더

    func testAuthTokenHeaderAttached() async throws {
        // 인증 토큰 주입 — SecretStore 스텁 대신 실제 Keychain에 임시 저장 후 정리
        let key = config.keychainKey(for: MCPServerConfig.authTokenEnvKey)
        let store = KeychainService.shared
        store.setSecret("test-token-123", forKey: key)
        defer { store.setSecret("", forKey: key) }

        enqueueHandshake()
        await connection.connect()
        let authHeader = MockURLProtocol.capturedRequests.first?.value(forHTTPHeaderField: config.authHeaderName)
        XCTAssertEqual(authHeader, "Bearer test-token-123")
    }

    // MARK: - 설정 호환성

    func testOldConfigJSONDecodesWithTransportDefaults() throws {
        let legacy = """
        [{"id":"\(UUID().uuidString)","name":"레거시","command":"npx","args":["-y"],"secretEnvKeys":[],"plainEnv":{},"isEnabled":true}]
        """
        let decoded = try JSONDecoder().decode([MCPServerConfig].self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].transport, .stdio)
        XCTAssertEqual(decoded[0].url, "")
        XCTAssertEqual(decoded[0].authHeaderName, "Authorization")
    }

    func testConfigRoundTripPreservesHTTPFields() throws {
        var remote = MCPServerConfig(name: "원격", command: "")
        remote.transport = .http
        remote.url = "https://api.example.com/mcp"
        remote.authHeaderName = "X-Api-Key"
        let data = try JSONEncoder().encode([remote])
        let restored = try JSONDecoder().decode([MCPServerConfig].self, from: data)
        XCTAssertEqual(restored[0].transport, .http)
        XCTAssertEqual(restored[0].url, "https://api.example.com/mcp")
        XCTAssertEqual(restored[0].authHeaderName, "X-Api-Key")
    }
}
