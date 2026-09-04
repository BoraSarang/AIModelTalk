import Foundation

/// 원격 MCP 공급자 연결 관리자
/// - HTTP/SSE 연결, 도구 발견, OAuth 토큰 자동 갱신, 도구 네임스페이싱
@MainActor
final class MCPProviderManager: ObservableObject {

    static let shared = MCPProviderManager()

    @Published private(set) var connections: [UUID: MCPRemoteConnection] = [:]

    private let store = MCPProviderStore.shared
    private let keychain = KeychainService.shared

    private init() {}

    // MARK: - 연결 관리

    /// 공급자 연결 (자동 OAuth/토큰 갱신 포함)
    func connect(_ provider: MCPProviderConfiguration) async -> MCPRemoteConnection? {
        // 이미 연결된 경우 재사용
        if let existing = connections[provider.id], existing.state == .ready {
            DebugLogger.shared.debug("MCP", "이미 연결됨 (재사용): \(provider.displayName)")
            return existing
        }

        DebugLogger.shared.info("MCP", "[FEATURE] 연결 시도: \(provider.displayName) (\(provider.url))")
        let connection = MCPRemoteConnection(provider: provider, store: store)
        connections[provider.id] = connection

        await connection.connect()
        return connection
    }

    /// 모든 활성 공급자 연결
    func connectAllEnabled() async {
        DebugLogger.shared.info("MCP", "[FEATURE] 모든 활성 공급자 연결 시작: \(store.providers.filter(\.isEnabled).map(\.displayName))")
        for provider in store.providers where provider.isEnabled {
            _ = await connect(provider)
        }
    }

    /// 연결 해제
    func disconnect(_ providerID: UUID) {
        DebugLogger.shared.info("MCP", "[FEATURE] 연결 해제: \(providerID)")
        connections[providerID]?.disconnect()
        connections.removeValue(forKey: providerID)
    }

    /// 모든 연결 해제
    func disconnectAll() {
        for (_, conn) in connections { conn.disconnect() }
        connections.removeAll()
    }

    // MARK: - 도구 집계 (네임스페이싱 적용)

    /// 모든 연결된 공급자의 도구 통합 반환 (네임스페이스 적용)
    func allTools() -> [MCPTool] {
        connections.values
            .filter { $0.state == .ready }
            .flatMap { connection in
                connection.tools.map { tool in
                    // 네임스페이스 적용: "linear_issues", "github_repos" 등
                    let namespacedName = "\(connection.provider.templateID)_\(tool.name)"
                    return MCPTool(
                        name: namespacedName,
                        description: "[\(connection.provider.displayName)] \(tool.description)",
                        inputSchemaJSON: tool.inputSchemaJSON
                    )
                }
            }
    }

    /// 특정 공급자의 도구 반환
    func tools(for providerID: UUID) -> [MCPTool] {
        guard let conn = connections[providerID], conn.state == .ready else { return [] }
        return conn.tools.map { tool in
            let namespacedName = "\(conn.provider.templateID)_\(tool.name)"
            return MCPTool(
                name: namespacedName,
                description: "[\(conn.provider.displayName)] \(tool.description)",
                inputSchemaJSON: tool.inputSchemaJSON
            )
        }
    }

    // MARK: - 도구 실행 라우팅

    /// 네임스페이스된 도구명으로 실제 공급자 연결 찾아 실행
    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        // "linear_issues" → providerID: "linear", toolName: "issues"
        let parts = name.split(separator: "_", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            DebugLogger.shared.error("MCP", "[PERF] 잘못된 도구명 형식: \(name)")
            throw MCPProviderError.invalidToolName(name)
        }

        let templateID = parts[0]
        let toolName = parts[1]

        // 템플릿 ID로 공급자 찾기
        guard let provider = store.providers.first(where: { $0.templateID == templateID && $0.isEnabled }),
              let connection = connections[provider.id],
              connection.state == .ready else {
            DebugLogger.shared.error("MCP", "[PERF] 공급자 미연결: \(templateID)")
            throw MCPProviderError.providerNotConnected(templateID)
        }

        // 원래 도구명으로 호출
        DebugLogger.shared.debug("MCP", "[PERF] 도구 호출: \(toolName) (provider: \(provider.displayName))")
        return try await connection.callTool(name: toolName, arguments: arguments)
    }

    // MARK: - 토큰 자동 갱신 (백그라운드)

    /// 만료 임박 토큰 자동 갱신 (주기적 호출용)
    func refreshExpiringTokens() async {
        for provider in store.providers where provider.isEnabled && provider.authMode.requiresBrowserAuth {
            if store.isTokenExpired(provider) {
                await refreshToken(for: provider)
            }
        }
    }

    func refreshToken(for provider: MCPProviderConfiguration) async {
        guard let refreshToken = store.refreshToken(for: provider.id),
              let template = provider.template,
              let issuer = provider.issuer ?? template.issuer else { return }

        do {
            // 인증 서버 메타데이터에서 토큰 엔드포인트 재발견
            let asm = try await MCPOAuthDiscovery.discoverAuthorizationServer(issuer: issuer)
            let response = try await MCPOAuthService.refreshToken(
                tokenEndpoint: asm.tokenEndpoint,
                clientId: provider.clientId ?? "",
                refreshToken: refreshToken
            )

            // 새 토큰 저장
            store.setAccessToken(response.accessToken, for: provider.id)
            if let rt = response.refreshToken {
                store.setRefreshToken(rt, for: provider.id)
            }
            if let expiresIn = response.expiresIn {
                store.updateTokenExpiry(provider.id, expiresIn: TimeInterval(expiresIn))
            }

            // 연결된 경우 재연결로 토큰 적용
            if var conn = connections[provider.id] {
                conn.updateAccessToken(response.accessToken)
            }

            DebugLogger.shared.info("MCP", "[\(provider.displayName)] 토큰 자동 갱신 완료")
        } catch {
            DebugLogger.shared.error("MCP", "[\(provider.displayName)] 토큰 갱신 실패: \(error.localizedDescription)")
        }
    }
}

/// 원격 MCP 연결 (HTTP/SSE) — MCPTransportConnection 프로토콜 준수
@MainActor
final class MCPRemoteConnection: ObservableObject, MCPTransportConnection {

    @Published var state: MCPConnection.State = .idle
    @Published private(set) var tools: [MCPTool] = []
    @Published private(set) var logLines: [String] = []

    var provider: MCPProviderConfiguration
    private let store: MCPProviderStore

    private let session: URLSession
    private var sessionID: String?
    private var nextID = 1
    private var accessToken: String?

    init(provider: MCPProviderConfiguration, store: MCPProviderStore) {
        self.provider = provider
        self.store = store
        self.session = URLSession.shared
        self.accessToken = store.accessToken(for: provider.id)
    }

    // MARK: - MCPTransportConnection

    func connect() async {
        guard state != .ready, state != .connecting else { return }
        guard let url = endpointURL, url.scheme == "http" || url.scheme == "https" else {
            DebugLogger.shared.error("MCP", "[\(provider.displayName)] 잘못된 URL: \(provider.url)")
            state = .failed("잘못된 URL: \(provider.url)")
            return
        }
        DebugLogger.shared.info("MCP", "[FEATURE] [\(provider.displayName)] 연결 시작: \(url.absoluteString)")

        // 토큰 확인 (OAuth 모드)
        if provider.authMode.requiresBrowserAuth {
            if accessToken == nil {
                accessToken = store.accessToken(for: provider.id)
            }
            if accessToken == nil {
                // OAuth 플로우 필요 — 연결 실패 상태로 두고 UI에서 유도
                DebugLogger.shared.warn("MCP", "[\(provider.displayName)] 인증 토큰 없음")
                state = .failed("인증 필요 — 설정에서 '연결' 클릭")
                return
            }
        }

        state = .connecting
        appendLog("[FEATURE] 원격 공급자 연결: \(provider.displayName)")

        do {
            // 1) initialize — 세션 ID 캡처
            let initID = issueID()
            DebugLogger.shared.debug("MCP", "[\(provider.displayName)] initialize 요청")
            let initReplies = try await exchange(body: MCPProtocol.initializeRequest(
                id: initID, clientName: "Osaurus", clientVersion: "1.0"), timeout: 20)
            guard case .response? = MCPProtocol.firstReply(id: initID, in: initReplies.inbounds) else {
                throw MCPProtocol.ProtocolError.serverError("initialize 응답 없음")
            }
            DebugLogger.shared.debug("MCP", "[\(provider.displayName)] initialize 완료")

            // 2) initialized 알림
            _ = try? await exchange(body: MCPProtocol.initializedNotification(), timeout: 10)

            // 3) tools/list
            let listID = issueID()
            DebugLogger.shared.debug("MCP", "[\(provider.displayName)] tools/list 요청")
            let listReplies = try await exchange(body: MCPProtocol.toolsListRequest(id: listID), timeout: 15)
            guard case let .response(_, listResult)? = MCPProtocol.firstReply(id: listID, in: listReplies.inbounds) else {
                throw MCPProtocol.ProtocolError.serverError("tools/list 응답 없음")
            }

            // 도구 네임스페이싱 적용
            let rawTools = MCPProtocol.parseTools(fromResult: listResult)
            tools = rawTools.map { tool in
                MCPTool(
                    name: "\(provider.templateID)_\(tool.name)",
                    description: "[\(provider.displayName)] \(tool.description)",
                    inputSchemaJSON: tool.inputSchemaJSON
                )
            }
            DebugLogger.shared.info("MCP", "[\(provider.displayName)] 도구 \(tools.count)개 발견")

            state = .ready
            provider.lastConnectedAt = Date()
            provider.lastError = nil
            provider.toolCount = tools.count
            store.upsert(provider)
            appendLog("연결 완료 — 도구 \(tools.count)개")
            DebugLogger.shared.info("MCP", "[\(provider.displayName)] 연결 완료")
        } catch {
            handleConnectionError(error)
        }
    }

    func disconnect() {
        DebugLogger.shared.info("MCP", "[\(provider.displayName)] 연결 해제")
        sessionID = nil
        tools = []
        state = .idle
        appendLog("연결 해제")
    }

    func restart() async {
        disconnect()
        await connect()
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        // 네임스페이스 제거 — 원래 도구명 추출
        let parts = name.split(separator: "_", maxSplits: 1).map(String.init)
        let toolName = parts.count == 2 ? parts[1] : name

        if state != .ready {
            await connect()
            guard case .ready = state else {
                throw MCPProtocol.ProtocolError.serverError("공급자 미연결")
            }
        }

        // 토큰 만료 시 자동 갱신 시도
        if provider.authMode.requiresBrowserAuth, store.isTokenExpired(provider) {
            await MCPProviderManager.shared.refreshToken(for: provider)
            accessToken = store.accessToken(for: provider.id)
        }

        let id = issueID()
        let replies = try await exchange(body: try MCPProtocol.toolsCallRequest(id: id, name: toolName, arguments: arguments), timeout: 60)

        switch MCPProtocol.firstReply(id: id, in: replies.inbounds) {
        case let .response(_, result):
            let outcome = MCPProtocol.parseCallResult(fromResult: result)
            if outcome.isError { throw MCPProtocol.ProtocolError.serverError(outcome.text) }
            appendLog("도구 '\(toolName)' 성공 (\(outcome.text.count)자)")
            return outcome.text
        case let .error(_, message):
            // 401이면 토큰 갱신 후 재시도 1회
            if message.contains("401") || message.lowercased().contains("unauthorized") {
                await MCPProviderManager.shared.refreshToken(for: provider)
                accessToken = store.accessToken(for: provider.id)
                return try await callTool(name: name, arguments: arguments) // 재귀 1회
            }
            throw MCPProtocol.ProtocolError.serverError(message)
        case .notification, nil:
            throw MCPProtocol.ProtocolError.serverError("도구 응답 수신 실패")
        }
    }

    /// 액세스 토큰 업데이트 (갱신 후)
    func updateAccessToken(_ token: String) {
        accessToken = token
    }

    // MARK: - Private

    private var endpointURL: URL? {
        URL(string: provider.url.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private struct ExchangeResult {
        let inbounds: [MCPProtocol.Inbound]
        let response: URLResponse
    }

    private func exchange(body: Data, timeout: TimeInterval) async throws -> ExchangeResult {
        guard let url = endpointURL else { throw MCPProtocol.ProtocolError.serverError("잘못된 URL") }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")

        if let sid = sessionID {
            request.setValue(sid, forHTTPHeaderField: "Mcp-Session-Id")
        }

        // 인증 헤더
        if provider.authMode == .apiKey {
            if let apiKey = store.apiKey(for: provider.id) {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        } else if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        captureSessionID(from: response)
        try checkStatus(response, data: data)

        let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
        if contentType.contains("text/event-stream") {
            let inbounds = MCPProtocol.parseSSEBody(data)
            return ExchangeResult(inbounds: inbounds, response: response)
        }
        if let inbound = MCPProtocol.parseJSONBody(data) {
            return ExchangeResult(inbounds: [inbound], response: response)
        }
        return ExchangeResult(inbounds: [], response: response)
    }

    private func captureSessionID(from response: URLResponse) {
        guard sessionID == nil,
              let http = response as? HTTPURLResponse,
              let sid = http.value(forHTTPHeaderField: "Mcp-Session-Id"),
              !sid.isEmpty else { return }
        sessionID = sid
        appendLog("세션 ID 획득")
    }

    private func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode >= 400 else { return }
        let preview = String(data: data.prefix(200), encoding: .utf8) ?? ""
        throw MCPProtocol.ProtocolError.serverError("HTTP \(http.statusCode) — \(preview)")
    }

    private func handleConnectionError(_ error: Error) {
        let message = error.localizedDescription
        DebugLogger.shared.error("MCP", "[\(provider.displayName)] 연결 실패: \(message)")
        provider.lastError = message
        store.upsert(provider)
        state = .failed(message)
        appendLog("연결 실패: \(message)")
    }

    private func issueID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    private func appendLog(_ line: String) {
        logLines.append("\(Self.timestamp) \(line)")
        if logLines.count > 300 { logLines.removeFirst(logLines.count - 300) }
    }

    nonisolated private static var timestamp: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }
}

enum MCPProviderError: Error, LocalizedError {
    case invalidToolName(String)
    case providerNotConnected(String)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .invalidToolName(let name): return "잘못된 도구명 형식: \(name) (예: linear_issues)"
        case .providerNotConnected(let id): return "공급자 '\(id)' 연결되지 않음"
        case .notAuthenticated: return "인증 필요"
        }
    }
}