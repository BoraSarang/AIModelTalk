import XCTest
@testable import AIModelTalk

/// v2.4 T-119 — MCP 코어 (프로토콜 인코딩/파싱·등록소 영속화·env 조립)
final class MCPTestsV119: XCTestCase {

    // MARK: - 요청 인코딩

    func testInitializeRequestEncoding() throws {
        let data = MCPProtocol.initializeRequest(id: 1, clientName: "AIModelTalk", clientVersion: "2.4")
        let obj = try JSONSerialization.jsonObject(with: data.dropLast()) as? [String: Any]
        XCTAssertEqual(obj?["jsonrpc"] as? String, "2.0")
        XCTAssertEqual((obj?["id"] as? NSNumber)?.intValue, 1)
        XCTAssertEqual(obj?["method"] as? String, "initialize")
        let params = try XCTUnwrap(obj?["params"] as? [String: Any])
        XCTAssertEqual(params["protocolVersion"] as? String, MCPProtocol.protocolVersion)
    }

    func testToolsCallRequestEncoding() throws {
        let data = try MCPProtocol.toolsCallRequest(id: 7, name: "read_file", arguments: ["path": "/tmp/a.txt"])
        let obj = try JSONSerialization.jsonObject(with: data.dropLast()) as? [String: Any]
        let params = try XCTUnwrap(obj?["params"] as? [String: Any])
        XCTAssertEqual(params["name"] as? String, "read_file")
        XCTAssertEqual((params["arguments"] as? [String: Any])?["path"] as? String, "/tmp/a.txt")
        XCTAssertNotNil(data.last, "개행 프레이밍")
        XCTAssertEqual(data.last, 0x0A)
    }

    // MARK: - 응답 파싱

    func testParseResponseAndErrorAndNotification() {
        let response = MCPProtocol.parse(line: #"{"jsonrpc":"2.0","id":3,"result":{"tools":[]}}"#)
        guard case let .response(id, _) = response else { return XCTFail("응답 파싱 실패") }
        XCTAssertEqual(id, 3)

        let error = MCPProtocol.parse(line: #"{"jsonrpc":"2.0","id":5,"error":{"code":-1,"message":"boom"}}"#)
        guard case let .error(eid, message) = error else { return XCTFail("에러 파싱 실패") }
        XCTAssertEqual(eid, 5)
        XCTAssertEqual(message, "boom")

        let notif = MCPProtocol.parse(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        XCTAssertEqual(notif, .notification(method: "notifications/initialized"))

        XCTAssertNil(MCPProtocol.parse(line: "not json"))
        XCTAssertNil(MCPProtocol.parse(line: "   "))
    }

    func testParseToolsList() {
        let result: [String: Any] = [
            "tools": [
                ["name": "read_file", "description": "파일 읽기",
                 "inputSchema": ["type": "object", "properties": ["path": ["type": "string"]]]],
                ["name": "no_desc"],
                ["description": "이름 없음 — 제외"]
            ]
        ]
        let tools = MCPProtocol.parseTools(fromResult: result)
        XCTAssertEqual(tools.count, 2)
        XCTAssertEqual(tools[0].name, "read_file")
        XCTAssertEqual(tools[0].description, "파일 읽기")
        XCTAssertTrue(tools[0].inputSchemaJSON.contains(#""properties""#))
        XCTAssertEqual(tools[1].description, "", "설명 없으면 빈 문자열")
    }

    func testParseCallResultTextMergeAndError() {
        let ok: [String: Any] = [
            "content": [
                ["type": "text", "text": "첫째"],
                ["type": "image", "data": "..."],
                ["type": "text", "text": "둘째"]
            ]
        ]
        XCTAssertEqual(MCPProtocol.parseCallResult(fromResult: ok).text, "첫째\n둘째")
        XCTAssertFalse(MCPProtocol.parseCallResult(fromResult: ok).isError)

        let bad: [String: Any] = ["isError": true, "content": [["type": "text", "text": "실패함"]]]
        let outcome = MCPProtocol.parseCallResult(fromResult: bad)
        XCTAssertTrue(outcome.isError)
        XCTAssertEqual(outcome.text, "실패함")

        let emptyBad: [String: Any] = ["isError": true]
        XCTAssertEqual(MCPProtocol.parseCallResult(fromResult: emptyBad).text, "도구 실행 오류 (내용 없음)")
    }

    // MARK: - 등록소 영속화 + env 조립

    @MainActor
    private func makeStore() -> MCPServerStore {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return MCPServerStore(defaults: defaults)
    }

    @MainActor
    func testStoreUpsertRemovePersists() throws {
        let store = makeStore()
        var config = MCPServerConfig(name: "fs", command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"])
        config.secretEnvKeys = ["API_TOKEN"]

        store.upsert(config)
        XCTAssertEqual(store.servers.count, 1)

        config.name = "fs-renamed"
        store.upsert(config)
        XCTAssertEqual(store.servers.count, 1, "같은 ID면 갱신")
        XCTAssertEqual(store.servers[0].name, "fs-renamed")

        store.remove(config.id)
        XCTAssertTrue(store.servers.isEmpty)
    }

    @MainActor
    func testResolvedEnvMergesSecrets() {
        final class FakeSecrets: SecretStore {
            private var map: [String: String] = [:]
            func setSecret(_ value: String, forKey key: String) { map[key] = value }
            func secret(forKey key: String) -> String? { map[key] }
            func deleteSecret(forKey key: String) { map.removeValue(forKey: key) }
        }
        let secrets = FakeSecrets()
        var config = MCPServerConfig(name: "api", command: "node", args: ["server.js"])
        config.plainEnv = ["NODE_ENV": "production"]
        config.secretEnvKeys = ["API_TOKEN"]
        secrets.setSecret("sk-secret", forKey: config.keychainKey(for: "API_TOKEN"))

        let env = config.resolvedEnv(secrets: secrets)
        XCTAssertEqual(env["NODE_ENV"], "production")
        XCTAssertEqual(env["API_TOKEN"], "sk-secret")

        // 미설정 시크릿은 생략 (경고 로그만)
        var missing = MCPServerConfig(name: "x", command: "x")
        missing.secretEnvKeys = ["MISSING_KEY"]
        XCTAssertNil(missing.resolvedEnv(secrets: secrets)["MISSING_KEY"])
    }
}
