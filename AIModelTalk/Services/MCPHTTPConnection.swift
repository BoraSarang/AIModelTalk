import Foundation

/// MCP Streamable HTTP 연결 (v2.4 T-122) — POST JSON-RPC, 응답은 JSON 또는 SSE
/// 흐름: initialize(POST) → Mcp-Session-Id 캡처 → initialized 알림 → tools/list → ready
@MainActor
final class MCPHTTPConnection: ObservableObject {

    @Published private(set) var state: MCPConnection.State = .idle
    @Published private(set) var tools: [MCPTool] = []
    @Published private(set) var logLines: [String] = []

    private let config: MCPServerConfig
    private let session: URLSession
    private let clientName = "AIModelTalk"
    private let clientVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.4"

    private var sessionID: String?
    private var nextID = 1

    init(config: MCPServerConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    private var endpointURL: URL? {
        URL(string: config.url.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - 생명주기

    func connect() async {
        guard state != .ready, state != .connecting else { return }
        guard let url = endpointURL, url.scheme == "http" || url.scheme == "https" else {
            state = .failed("잘못된 URL: \(config.url)")
            return
        }
        state = .connecting
        appendLog("[FEATURE] HTTP 서버 연결 시작: \(config.url)")
        do {
            // 1) initialize — 세션 ID는 응답 헤더에서 캡처
            let initID = issueID()
            let initReplies = try await exchange(body: MCPProtocol.initializeRequest(
                id: initID, clientName: clientName, clientVersion: clientVersion), timeout: 20)
            guard case let .response(_, result)? = MCPProtocol.firstReply(id: initID, in: initReplies.inbounds) else {
                throw MCPProtocol.ProtocolError.serverError("initialize 응답 없음")
            }
            _ = result // serverInfo 등 — 현재 미사용

            // 2) initialized 알림 — 응답 본문 없음(202) 허용
            _ = try? await exchange(body: MCPProtocol.initializedNotification(), timeout: 10)

            // 3) tools/list
            let listID = issueID()
            let listReplies = try await exchange(body: MCPProtocol.toolsListRequest(id: listID), timeout: 15)
            guard case let .response(_, listResult)? = MCPProtocol.firstReply(id: listID, in: listReplies.inbounds) else {
                throw MCPProtocol.ProtocolError.serverError("tools/list 응답 없음")
            }
            tools = MCPProtocol.parseTools(fromResult: listResult)
            state = .ready
            DebugLogger.shared.info("MCP", "[FEATURE] HTTP 연결 완료 '\(config.name)' 도구 \(tools.count)개")
        } catch {
            disconnectState()
            state = .failed("연결 실패: \(error.localizedDescription)")
            DebugLogger.shared.error("MCP", "E-MAC-NET-1003 HTTP 연결 실패 '\(config.name)': \(error.localizedDescription)")
        }
    }

    func disconnect() {
        disconnectState()
        appendLog("연결 종료")
    }

    /// 수동 재시작 — failed/idle에서 호출
    func restart() async {
        disconnect()
        await connect()
    }

    // MARK: - 도구 호출

    /// 도구 실행 — 미연결이면 먼저 connect. 성공 시 결과 텍스트, 실패 시 throw.
    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        if state != .ready {
            await connect()
            guard case .ready = state else {
                throw MCPProtocol.ProtocolError.serverError("서버 미연결 — 도구 호출 불가")
            }
        }
        let id = issueID()
        let replies = try await exchange(body: try MCPProtocol.toolsCallRequest(id: id, name: name, arguments: arguments), timeout: 60)
        switch MCPProtocol.firstReply(id: id, in: replies.inbounds) {
        case let .response(_, result):
            let outcome = MCPProtocol.parseCallResult(fromResult: result)
            if outcome.isError {
                appendLog("도구 '\(name)' 오류: \(outcome.text)")
                throw MCPProtocol.ProtocolError.serverError(outcome.text)
            }
            appendLog("도구 '\(name)' 성공 (\(outcome.text.count)자)")
            return outcome.text
        case let .error(_, message):
            throw MCPProtocol.ProtocolError.serverError(message)
        case .notification, nil:
            throw MCPProtocol.ProtocolError.serverError("도구 응답 수신 실패")
        }
    }

    // MARK: - 전송

    private struct ExchangeResult {
        let inbounds: [MCPProtocol.Inbound]
        let response: URLResponse
    }

    /// JSON-RPC POST — Content-Type에 따라 JSON/SSE 파싱, 세션·인증 헤더 부착
    private func exchange(body: Data, timeout: TimeInterval) async throws -> ExchangeResult {
        guard let url = endpointURL else {
            throw MCPProtocol.ProtocolError.serverError("잘못된 URL")
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let sid = sessionID {
            request.setValue(sid, forHTTPHeaderField: "Mcp-Session-Id")
        }
        if let token = config.authToken(), !token.isEmpty {
            let value = token.lowercased().hasPrefix("bearer ") ? token : "Bearer \(token)"
            request.setValue(value, forHTTPHeaderField: config.authHeaderName)
        }
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        captureSessionID(from: response)
        try checkStatus(response, data: data)

        let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
        if contentType.contains("text/event-stream") {
            let inbounds = MCPProtocol.parseSSEBody(data)
            if inbounds.isEmpty {
                // 이벤트 없이 닫히는 스트림(알림 전송용) — 정상 처리
                return ExchangeResult(inbounds: [], response: response)
            }
            return ExchangeResult(inbounds: inbounds, response: response)
        }
        if let inbound = MCPProtocol.parseJSONBody(data) {
            return ExchangeResult(inbounds: [inbound], response: response)
        }
        // 빈 본문 (예: 202 Accepted 알림 응답)
        return ExchangeResult(inbounds: [], response: response)
    }

    private func captureSessionID(from response: URLResponse) {
        guard sessionID == nil,
              let httpResponse = response as? HTTPURLResponse,
              let sid = httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id"),
              !sid.isEmpty else { return }
        sessionID = sid
        appendLog("세션 ID 획득")
    }

    private func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode >= 400 else { return }
        let preview = String(data: data.prefix(200), encoding: .utf8) ?? ""
        throw MCPProtocol.ProtocolError.serverError("HTTP \(http.statusCode) — \(preview)")
    }

    private func disconnectState() {
        sessionID = nil
        tools = []
        state = .idle
    }

    private func issueID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    private func appendLog(_ line: String) {
        logLines.append("\(Self.timestampText) \(line)")
        if logLines.count > 300 {
            logLines.removeFirst(logLines.count - 300)
        }
    }

    nonisolated private static var timestampText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}
