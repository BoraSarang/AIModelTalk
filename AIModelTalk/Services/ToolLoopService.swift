import Foundation

/// 도구 실행 루프 (v2.4 T-120) — 모델 ↔ MCP 도구 왕복 오케스트레이션
/// 최대 8라운드. 텍스트 델타는 즉시 onText로 전달해 기존 스트리밍 UX 유지.
@MainActor
enum ToolLoopService {

    /// 도구 호출 한도 — 무한 루프 방지 (로드맵: 호출 루프 최대 8회)
    static let maxRounds = 8

    /// 실행 카드 기록 — 말풍선에 첨부되어 영속화된다
    struct ExecutionRecord: Identifiable, Codable, Hashable {
        let id: UUID
        let toolName: String
        let argumentsJSON: String
        var resultPreview: String?
        var isError: Bool
        var durationMS: Double?
        /// 권한 결정 기록 — allowed / denied / alwaysAllowed / policyDeny
        var permissionDecision: String

        init(toolName: String, argumentsJSON: String, resultPreview: String? = nil,
             isError: Bool = false, durationMS: Double? = nil, permissionDecision: String = "allowed") {
            self.id = UUID()
            self.toolName = toolName
            self.argumentsJSON = argumentsJSON
            self.resultPreview = resultPreview
            self.isError = isError
            self.durationMS = durationMS
            self.permissionDecision = permissionDecision
        }
    }

    enum LoopError: Error {
        case roundLimitExceeded
    }

    /// 루프 실행 — 최종 답변(도구 호출 없는 라운드)까지 반복
    /// - Parameters:
    ///   - permissionGate: 도구 호출 허용 여부 판단 (UI 확인 프롬프트·정책 반영)
    static func run(
        client: ChatClient,
        messages: [ChatMessage],
        systemPrompt: String?,
        temperature: Double?,
        tools: [LLMToolDefinition],
        connections: [any MCPTransportConnection],
        permissionGate: @escaping (LLMToolCall) async -> PermissionDecision,
        onText: @escaping (String) -> Void,
        onToolRun: @escaping (ExecutionRecord) -> Void,
        onUsage: ((Int?, Int?) -> Void)?
    ) async throws -> [ExecutionRecord] {
        var allRecords: [ExecutionRecord] = []
        var roundMessages = messages

        for round in 0..<maxRounds {
            var collectedCalls: [LLMToolCall] = []
            for try await event in client.streamWithTools(
                messages: roundMessages, systemPrompt: systemPrompt,
                temperature: temperature, tools: tools, onUsage: onUsage) {
                switch event {
                case .text(let chunk):
                    onText(chunk)
                case .toolCalls(let calls):
                    collectedCalls = calls
                }
            }

            // 도구 호출 없이 종료 — 최종 답변 완료
            if collectedCalls.isEmpty { return allRecords }
            if round == maxRounds - 1 {
                DebugLogger.shared.warn("TOOLS", "E-MAC-AI-1006 도구 호출 한도 초과 (\(maxRounds)라운드)")
                throw LoopError.roundLimitExceeded
            }

            // 이번 라운드 도구들 실행 → 결과를 다음 라운드 컨텍스트에 합성 주입
            // (v2.4 1차: role:"tool" 전용 이력 대신 시스템 안내 user 메시지 방식)
            var followUp = "다음은 도구 실행 결과입니다. 이를 반영해 답변해 주세요.\n"
            for call in collectedCalls {
                let decision = await permissionGate(call)
                switch decision {
                case .denied:
                    let record = ExecutionRecord(
                        toolName: call.name, argumentsJSON: call.argumentsJSON,
                        resultPreview: "사용자가 실행을 거부했습니다.", isError: false,
                        durationMS: nil, permissionDecision: "denied")
                    allRecords.append(record)
                    onToolRun(record)
                    followUp += "- [\(call.name)] (사용자 거부)\n"
                case .allowed:
                    var record = try await execute(call: call, connections: connections)
                    record.permissionDecision = "allowed"
                    allRecords.append(record)
                    onToolRun(record)
                    followUp += "- [\(call.name)] \(record.resultPreview ?? "(결과 없음)")\n"
                }
            }
            roundMessages = messages + [
                ChatMessage(role: .user, content: followUp)
            ]
        }
        return allRecords
    }

    enum PermissionDecision {
        case allowed
        case denied
    }

    /// 단일 도구 실행 — 내장 도구 우선(web_search/fetch_url/calculator, T-204) → 담당 서버 탐색 → MCP 호출 → 카드 기록 생성
    static func execute(call: LLMToolCall, connections: [any MCPTransportConnection]) async throws -> ExecutionRecord {
        // 내장 도구 분기 (서버 연결 불필요)
        if let record = await runBuiltinIfMatches(call: call) {
            return record
        }
        guard let connection = connections.first(where: { conn in
            conn.tools.contains { $0.name == call.name }
        }) else {
            return ExecutionRecord(
                toolName: call.name, argumentsJSON: call.argumentsJSON,
                resultPreview: "해당 도구를 제공하는 서버가 연결되지 않았습니다.",
                isError: true, permissionDecision: "allowed")
        }
        let arguments = (try? JSONSerialization.jsonObject(with: Data(call.argumentsJSON.utf8)) as? [String: Any]) ?? [:]
        let start = Date()
        do {
            let text = try await connection.callTool(name: call.name, arguments: arguments)
            return ExecutionRecord(
                toolName: call.name, argumentsJSON: call.argumentsJSON,
                resultPreview: String(text.prefix(400)),
                isError: false,
                durationMS: Date().timeIntervalSince(start) * 1000)
        } catch {
            return ExecutionRecord(
                toolName: call.name, argumentsJSON: call.argumentsJSON,
                resultPreview: error.localizedDescription,
                isError: true,
                durationMS: Date().timeIntervalSince(start) * 1000)
        }
    }

    // MARK: - 내장 도구 실행 (T-204)

    /// 내장 도구 이름 집합 — 에이전트가 참조하는 툴 스키마와 매칭
    static var builtinToolNames: Set<String> {
        ["web_search", "fetch_url", "calculator"]
    }

    private static func runBuiltinIfMatches(call: LLMToolCall) async -> ExecutionRecord? {
        let name = call.name
        guard builtinToolNames.contains(name) else { return nil }
        let start = Date()
        let arguments = (try? JSONSerialization.jsonObject(with: Data(call.argumentsJSON.utf8)) as? [String: Any]) ?? [:]

        do {
            switch name {
            case "web_search":
                guard let query = arguments["query"] as? String, !query.isEmpty else {
                    throw WebSearchError.emptyQuery
                }
                let key = AppSettings.shared.tavilyAPIKey
                let results = try await WebSearchService.search(query: query, apiKey: key, maxResults: 5)
                let text = results.isEmpty
                    ? "검색 결과가 없습니다."
                    : WebSearchService.formatResults(results, query: query)
                DebugLogger.shared.info("TOOL", "[FEATURE] 내장 도구 web_search 실행: '\(query)' → \(results.count)건")
                return ExecutionRecord(
                    toolName: name, argumentsJSON: call.argumentsJSON,
                    resultPreview: text, isError: false,
                    durationMS: Date().timeIntervalSince(start) * 1000)

            case "fetch_url":
                let urlString = arguments["url"] as? String
                guard let urlString, let url = URL(string: urlString) else {
                    throw WebSearchError.fetchBlocked("올바른 URL이 아닙니다.")
                }
                let text = try await WebSearchService.fetchURL(url)
                DebugLogger.shared.info("TOOL", "[FEATURE] 내장 도구 fetch_url 실행: \(url.host ?? "?") → \(text.count)자")
                return ExecutionRecord(
                    toolName: name, argumentsJSON: call.argumentsJSON,
                    resultPreview: text, isError: false,
                    durationMS: Date().timeIntervalSince(start) * 1000)

            case "calculator":
                let expr = arguments["expression"] as? String ?? ""
                let result = try WebSearchService.evaluateCalculator(expr)
                DebugLogger.shared.info("TOOL", "[FEATURE] 내장 도구 calculator 실행: \(expr) = \(result)")
                return ExecutionRecord(
                    toolName: name, argumentsJSON: call.argumentsJSON,
                    resultPreview: "\(result)", isError: false,
                    durationMS: Date().timeIntervalSince(start) * 1000)

            default:
                return nil
            }
        } catch {
            DebugLogger.shared.error("TOOL", "내장 도구 \(name) 실패")
            return ExecutionRecord(
                toolName: name, argumentsJSON: call.argumentsJSON,
                resultPreview: error.localizedDescription,
                isError: true,
                durationMS: Date().timeIntervalSince(start) * 1000)
        }
    }
}
