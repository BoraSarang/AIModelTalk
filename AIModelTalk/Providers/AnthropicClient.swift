import Foundation

/// Anthropic Claude 공식 Messages API 클라이언트 (v2.1 T-94)
/// OpenAI 호환이 아닌 전용 프로토콜 — x-api-key 헤더, 이벤트형 SSE.
/// usage는 네이티브 제공(message_start=입력 / message_delta=출력)으로 실측 배지 즉시 지원.
struct AnthropicClient: ChatClient {
    let apiKey: String
    let model: String

    /// Anthropic은 max_tokens 필수값 — 컨텍스트 한도와 별개의 응답 길이 상한.
    /// 사용자가 maxTokens를 지정하면 이 기본값을 대체 (v0.2.0 T-202)
    private static let maxTokens = 8192

    private struct RequestBody: Encodable {
        let model: String
        let max_tokens: Int
        let system: String?
        let messages: [Message]
        let stream: Bool
        /// 캐릭터별 샘플링 온도 — nil이면 생략 (v2.2 T-111)
        let temperature: Double?
        /// top-p(nucleus sampling) — nil이면 생략 (v0.2.0 T-202)
        let top_p: Double?
        /// 도구 목록 — nil이면 생략 (v2.4 T-120)
        let tools: [APITool]?

        init(model: String, max_tokens: Int, system: String?, messages: [Message],
             stream: Bool, temperature: Double?, topP: Double? = nil, tools: [APITool]? = nil) {
            self.model = model
            self.max_tokens = max_tokens
            self.system = system
            self.messages = messages
            self.stream = stream
            self.temperature = temperature
            self.top_p = topP
            self.tools = tools?.isEmpty == true ? nil : tools
        }

        struct Message: Codable {
            let role: String
            let content: String
        }
    }

    /// Anthropic 도구 정의 형식 — input_schema에 JSON Schema 객체 (v2.4 T-120)
    struct APITool: Encodable {
        let name: String
        let description: String
        let input_schema: OpenAICompatibleClient.APITool.SchemaValue

        init(from definition: LLMToolDefinition) {
            self.name = definition.name
            self.description = definition.description
            var parameters: [String: Any] = [:]
            if let data = definition.parametersJSON.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                parameters = obj
            }
            self.input_schema = parameters.isEmpty
                ? .object(["type": .string("object"), "properties": .object([:])])
                : OpenAICompatibleClient.APITool.SchemaValue.convertObject(parameters)
        }
    }

    var supportsTools: Bool { true }

    /// 도구 포함 스트리밍 (v2.4 T-120)
    /// content_block_start(tool_use) → input_json_delta 누적 → 종료 시 일괄 발행.
    func rawStreamWithTools(
        messages: [ChatMessage], systemPrompt: String?, temperature: Double?,
        tools: [LLMToolDefinition], onUsage: ((Int?, Int?) -> Void)?
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !apiKey.isEmpty else {
                        throw AppError.missingKey(.anthropic)
                    }
                    var chat = messages.filter { $0.role == .user || $0.role == .assistant }
                    if chat.first?.role != .user {
                        chat.insert(ChatMessage(role: .user, content: "이어서 답변해 주세요."), at: 0)
                    }
                    let body = RequestBody(
                        model: model,
                        max_tokens: Self.maxTokens,
                        system: (systemPrompt?.isEmpty == false) ? systemPrompt : nil,
                        messages: chat.map { .init(role: $0.role.rawValue, content: $0.content) },
                        stream: true,
                        temperature: temperature,
                        tools: tools.map { APITool(from: $0) })

                    var urlRequest = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    urlRequest.httpBody = try JSONEncoder().encode(body)
                    urlRequest.timeoutInterval = 120

                    DebugLogger.shared.info("API-ANTHROPIC", "[TOOLS] 요청 시작: model=\(model), 도구 \(tools.count)개")
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else {
                        throw AppError.network("응답 없음")
                    }
                    TokenQuotaStore.capture(headers: http.allHeaderFields, provider: .anthropic)
                    if !(200..<300).contains(http.statusCode) {
                        var errBody = Data()
                        for try await b in bytes { errBody.append(b) }
                        let text = String(data: errBody, encoding: .utf8) ?? ""
                        DebugLogger.shared.error("API-ANTHROPIC", "서버 에러 HTTP \(http.statusCode): \(text.prefix(500))")
                        throw AppError.serverError(http.statusCode, text)
                    }

                    // 블록 인덱스별 도구 호출 누적
                    var accumulated: [Int: (id: String, name: String, args: String)] = [:]
                    var inputTokens: Int?
                    var outputTokens: Int?

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if payload.isEmpty { continue }

                        switch Self.parseToolEvent(payload) {
                        case let .blockStart(index, id, name):
                            accumulated[index] = (id, name, "")
                        case let .jsonDelta(index, partial):
                            if accumulated[index] != nil {
                                accumulated[index]?.args += partial
                            }
                        case let .usage(input, output):
                            if input != nil { inputTokens = input }
                            if output != nil { outputTokens = output }
                        case .other:
                            break
                        }
                    }

                    let calls = accumulated
                        .sorted { $0.key < $1.key }
                        .compactMap { _, entry -> LLMToolCall? in
                            guard !entry.name.isEmpty else { return nil }
                            return LLMToolCall(
                                id: entry.id.isEmpty ? UUID().uuidString : entry.id,
                                name: entry.name,
                                argumentsJSON: entry.args.isEmpty ? "{}" : entry.args)
                        }
                    if !calls.isEmpty {
                        DebugLogger.shared.info("API-ANTHROPIC", "[FEATURE] 도구 호출 요청 수신: \(calls.map { $0.name }.joined(separator: ", "))")
                        continuation.yield(.toolCalls(calls))
                    }

                    if inputTokens != nil || outputTokens != nil {
                        onUsage?(inputTokens, outputTokens)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    DebugLogger.shared.warn("API-ANTHROPIC", "[TOOLS] 요청 취소됨")
                    continuation.finish()
                } catch let error as AppError {
                    continuation.finish(throwing: error)
                } catch {
                    if (error as NSError).code == NSURLErrorTimedOut {
                        continuation.finish(throwing: AppError.timeout)
                    } else {
                        continuation.finish(throwing: AppError.network(error.localizedDescription))
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func stream(messages: [ChatMessage], systemPrompt: String?, onUsage: ((Int?, Int?) -> Void)?) -> AsyncThrowingStream<String, Error> {
        stream(messages: messages, systemPrompt: systemPrompt, temperature: nil, onUsage: onUsage)
    }

    /// temperature/topP/maxTokens 지원 스트리밍 (v2.2 T-111, v0.2.0 T-202)
    func stream(messages: [ChatMessage], systemPrompt: String?, temperature: Double?,
                topP: Double? = nil, maxTokens: Int? = nil,
                onUsage: ((Int?, Int?) -> Void)?) -> AsyncThrowingStream<String, Error> {
        DebugLogger.shared.info("APP", "[FEATURE] Anthropic 스트리밍 진입: 메시지 \(messages.count)개")
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !apiKey.isEmpty else {
                        throw AppError.missingKey(.anthropic)
                    }

                    // Anthropic 규칙: 첫 메시지는 user 역할이어야 함
                    var chat = messages.filter { $0.role == .user || $0.role == .assistant }
                    if chat.first?.role != .user {
                        chat.insert(ChatMessage(role: .user, content: "이어서 답변해 주세요."), at: 0)
                    }

                    let body = RequestBody(
                        model: model,
                        max_tokens: maxTokens ?? Self.maxTokens,
                        system: (systemPrompt?.isEmpty == false) ? systemPrompt : nil,
                        messages: chat.map { .init(role: $0.role.rawValue, content: $0.content) },
                        stream: true,
                        temperature: temperature,
                        topP: topP
                    )

                    var urlRequest = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    urlRequest.httpBody = try JSONEncoder().encode(body)
                    urlRequest.timeoutInterval = 120

                    DebugLogger.shared.info("API-ANTHROPIC", "요청 시작: model=\(model), 메시지 \(chat.count)개")
                    let startTime = Date()
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else {
                        throw AppError.network("응답 없음")
                    }
                    DebugLogger.shared.info("API-ANTHROPIC", "응답 상태: HTTP \(http.statusCode)")
                    TokenQuotaStore.capture(headers: http.allHeaderFields, provider: .anthropic)

                    if !(200..<300).contains(http.statusCode) {
                        var errBody = Data()
                        for try await b in bytes { errBody.append(b) }
                        let text = String(data: errBody, encoding: .utf8) ?? ""
                        DebugLogger.shared.error("API-ANTHROPIC", "[E-MAC-API-1001] 서버 에러 HTTP \(http.statusCode): \(text.prefix(500))")
                        throw AppError.serverError(http.statusCode, text)
                    }

                    var lineCount = 0
                    var totalChars = 0
                    var inputTokens: Int?
                    var outputTokens: Int?

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue } // "event:" 라인은 무시
                        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if payload.isEmpty { continue }

                        let parsed = Self.parseAnthropicEvent(payload)
                        if let text = parsed.text {
                            totalChars += text.count
                            continuation.yield(text)
                            lineCount += 1
                        }
                        if let input = parsed.inputTokens { inputTokens = input }
                        if let output = parsed.outputTokens { outputTokens = output }
                    }

                    if inputTokens != nil || outputTokens != nil {
                        onUsage?(inputTokens, outputTokens)
                        DebugLogger.shared.info("API-ANTHROPIC", "[FEATURE] usage 수신됨: ↑\(inputTokens.map(String.init) ?? "-") ↓\(outputTokens.map(String.init) ?? "-")")
                    }

                    let elapsed = Date().timeIntervalSince(startTime) * 1000
                    DebugLogger.shared.info("API-ANTHROPIC", "스트리밍 완료: \(totalChars)자, \(lineCount)청크, \(Int(elapsed))ms")
                    continuation.finish()
                } catch is CancellationError {
                    DebugLogger.shared.warn("API-ANTHROPIC", "요청 취소됨")
                    continuation.finish()
                } catch let error as AppError {
                    DebugLogger.shared.error("API-ANTHROPIC", "[\(error.errorCode)] \(error.localizedDescription ?? "")")
                    continuation.finish(throwing: error)
                } catch {
                    if (error as NSError).code == NSURLErrorTimedOut {
                        continuation.finish(throwing: AppError.timeout)
                    } else {
                        continuation.finish(throwing: AppError.network(error.localizedDescription))
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Anthropic SSE 이벤트 파싱 — 텍스트/입력토큰/출력토큰 추출 (테스트 가능하도록 분리, v2.1 T-94)
    static func parseAnthropicEvent(_ payload: String) -> (text: String?, inputTokens: Int?, outputTokens: Int?) {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONDecoder().decode(Event.self, from: data) else { return (nil, nil, nil) }

        switch json.type {
        case "content_block_delta":
            return (json.delta?.text, nil, nil)
        case "message_start":
            return (nil, json.message?.usage?.input_tokens, nil)
        case "message_delta":
            return (nil, nil, json.delta?.usage?.output_tokens)
        default:
            return (nil, nil, nil) // ping / content_block_start / content_block_stop 등
        }
    }

    /// 도구 이벤트 파싱 — tool_use 블록 시작/JSON 델타/usage 분류 (v2.4 T-120, 테스트 가능하도록 분리)
    enum AnthropicToolEvent: Equatable {
        case blockStart(index: Int, id: String, name: String)
        case jsonDelta(index: Int, partialJSON: String)
        case usage(input: Int?, output: Int?)
        case other
    }

    static func parseToolEvent(_ payload: String) -> AnthropicToolEvent {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONDecoder().decode(Event.self, from: data) else { return .other }
        switch json.type {
        case "content_block_start":
            if let block = json.content_block, block.type == "tool_use",
               let index = json.index, let id = block.id, let name = block.name {
                return .blockStart(index: index, id: id, name: name)
            }
            return .other
        case "content_block_delta":
            if let index = json.index, let partial = json.delta?.partial_json {
                return .jsonDelta(index: index, partialJSON: partial)
            }
            return .other
        case "message_start":
            return .usage(input: json.message?.usage?.input_tokens, output: nil)
        case "message_delta":
            return .usage(input: nil, output: json.delta?.usage?.output_tokens)
        default:
            return .other
        }
    }

    private struct Event: Codable {
        let type: String?
        let index: Int?
        let delta: Delta?
        let message: MessageStart?
        let content_block: ContentBlock?

        struct Delta: Codable {
            let type: String?
            let text: String?
            let partial_json: String?
            let usage: Usage?
        }

        struct ContentBlock: Codable {
            let type: String?
            let id: String?
            let name: String?
        }

        struct MessageStart: Codable {
            let usage: Usage?
        }

        struct Usage: Codable {
            let input_tokens: Int?
            let output_tokens: Int?
        }
    }
}
