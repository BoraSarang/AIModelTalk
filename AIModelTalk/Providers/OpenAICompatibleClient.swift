import Foundation

protocol ChatClient {
    /// onUsage: 응답 완료 시 API가 보고한 (promptTokens, completionTokens) — 미지원 타입은 nil 전달 가능
    func stream(messages: [ChatMessage], systemPrompt: String?, onUsage: ((Int?, Int?) -> Void)?) -> AsyncThrowingStream<String, Error>
    /// 도구 호출 지원 여부 — 동적 디스패치를 위해 프로토콜 요구사항 (v2.4 T-120)
    var supportsTools: Bool { get }
    /// 도구 포함 실제 스트리밍 구현 — 미지원 클라이언트는 기본 구현이 오류로 종료
    func rawStreamWithTools(messages: [ChatMessage], systemPrompt: String?, temperature: Double?,
                            tools: [LLMToolDefinition], onUsage: ((Int?, Int?) -> Void)?) -> AsyncThrowingStream<ChatStreamEvent, Error>
}

extension ChatClient {
    /// 기존 2파라미터 호출부 호환 (v1.9 T-76)
    func stream(messages: [ChatMessage], systemPrompt: String?) -> AsyncThrowingStream<String, Error> {
        stream(messages: messages, systemPrompt: systemPrompt, onUsage: nil)
    }

    /// temperature 지원 호출 (v2.2 T-111) — 미지원 클라이언트는 온도를 무시하고 기존 경로로 폴백
    func stream(messages: [ChatMessage], systemPrompt: String?, temperature: Double?,
                onUsage: ((Int?, Int?) -> Void)?) -> AsyncThrowingStream<String, Error> {
        stream(messages: messages, systemPrompt: systemPrompt, onUsage: onUsage)
    }

    /// topP/maxTokens 지원 호출 (v0.2.0 T-202) — 미지원 클라이언트는 temperature만 쓰고 나머지를 무시하는 기본 폴백.
    /// 지원 클라이언트(OpenAICompatible/Gemini/Anthropic/Ollama)가 오버라이드한다.
    func stream(messages: [ChatMessage], systemPrompt: String?, temperature: Double?,
                topP: Double?, maxTokens: Int?,
                onUsage: ((Int?, Int?) -> Void)?) -> AsyncThrowingStream<String, Error> {
        stream(messages: messages, systemPrompt: systemPrompt, temperature: temperature, onUsage: onUsage)
    }
}

struct OpenAICompatibleClient: ChatClient {
    let provider: Provider
    let apiKey: String
    let baseURL: String
    let model: String

    struct StreamOptions: Encodable {
        let include_usage: Bool
    }

    private struct RequestBody: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool
        let stream_options: StreamOptions?
        /// 캐릭터별 샘플링 온도 — nil이면 키 자체를 생략 (v2.2 T-111)
        let temperature: Double?
        /// nucleus sampling (top-p) — nil이면 생략 (v0.2.0 T-202)
        let top_p: Double?
        /// 응답 최대 토큰 수 — nil이면 생략 (v0.2.0 T-202)
        let max_tokens: Int?
        /// 도구 목록 — nil이면 키 생략 (v2.4 T-120)
        let tools: [APITool]?
        let tool_choice: String?

        init(model: String, messages: [Message], stream: Bool, stream_options: StreamOptions?,
             temperature: Double?, topP: Double? = nil, maxTokens: Int? = nil,
             tools: [APITool]? = nil) {
            self.model = model
            self.messages = messages
            self.stream = stream
            self.stream_options = stream_options
            self.temperature = temperature
            self.top_p = topP
            self.max_tokens = maxTokens
            self.tools = tools?.isEmpty == true ? nil : tools
            self.tool_choice = tools?.isEmpty == false ? "auto" : nil
        }
    }

    /// OpenAI function 형식 도구 정의 (v2.4 T-120)
    struct APITool: Encodable {
        let type = "function"
        let function: FunctionDef

        init(from definition: LLMToolDefinition) {
            var parameters: [String: Any] = [:]
            if let data = definition.parametersJSON.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                parameters = obj
            }
            self.function = .init(
                name: definition.name,
                description: definition.description,
                // JSON Schema는 Any 트리라 재귀 변환 — 실패 시 최소 스키마
                parameters: parameters.isEmpty
                    ? .object(["type": .string("object"), "properties": .object([:])])
                    : SchemaValue.convertObject(parameters))
        }

        struct FunctionDef: Encodable {
            let name: String
            let description: String
            let parameters: SchemaValue
        }

        /// JSON 호환 재귀 값 — [String: Any]를 Encodable로 안전하게 통과
        enum SchemaValue: Encodable {
            case string(String)
            case number(Double)
            case bool(Bool)
            case array([SchemaValue])
            case object([String: SchemaValue])

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .string(let v): try container.encode(v)
                case .number(let v): try container.encode(v)
                case .bool(let v): try container.encode(v)
                case .array(let v): try container.encode(v)
                case .object(let v): try container.encode(v)
                }
            }

            static func convert(_ any: Any) -> SchemaValue {
                switch any {
                case let s as String: return .string(s)
                case let n as NSNumber:
                    // Bool은 NSNumber로도 도착 — CFBoolean 타입 ID 식별로 판별
                    if CFGetTypeID(n) == CFBooleanGetTypeID() {
                        return .bool(n.boolValue)
                    }
                    return .number(n.doubleValue)
                case let b as Bool: return .bool(b)
                case let a as [Any]: return .array(a.map { convert($0) })
                case let o as [String: Any]: return convertObject(o)
                default: return .string(String(describing: any))
                }
            }

            static func convertObject(_ object: [String: Any]) -> SchemaValue {
                .object(object.mapValues { convert($0) })
            }
        }
    }

    /// content는 문자열 또는 파트 배열 — 첨부 이미지 존재 시 배열 형식 (T-71)
    struct Message: Encodable {
        let role: String
        let content: Content

        init(role: String, text: String, attachments: [MessageAttachment]? = nil) {
            self.role = role
            if let attachments, !attachments.isEmpty {
                var parts: [ContentPart] = [.init(type: "text", text: text)]
                for attachment in attachments {
                    let uri = "data:\(attachment.mimeType);base64,\(attachment.imageData.base64EncodedString())"
                    parts.append(.init(type: "image_url", imageURL: uri))
                }
                content = .parts(parts)
            } else {
                content = .text(text)
            }
        }
    }

    enum Content: Encodable {
        case text(String)
        case parts([ContentPart])

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let string): try container.encode(string)
            case .parts(let parts): try container.encode(parts)
            }
        }
    }

    struct ContentPart: Encodable {
        let type: String
        let text: String?
        let image_url: ImageURL?

        init(type: String, text: String? = nil, imageURL: String? = nil) {
            self.type = type
            self.text = text
            self.image_url = imageURL.map { .init(url: $0) }
        }

        struct ImageURL: Encodable {
            let url: String
        }
    }

    private struct StreamChunk: Codable {
        let choices: [Choice]?
        let usage: Usage?

        struct Choice: Codable {
            let delta: Delta
            let finish_reason: String?
        }

        struct Delta: Codable {
            let content: String?
            /// 도구 호출 프래그먼트 — 인덱스별 누적 필요 (v2.4 T-120)
            let tool_calls: [ToolCallDelta]?
        }

        /// tool_calls 스트리밍 델타 — arguments가 여러 청크에 걸쳐 조각으로 온다
        struct ToolCallDelta: Codable {
            let index: Int?
            let id: String?
            let function: FunctionFragment?

            struct FunctionFragment: Codable {
                let name: String?
                let arguments: String?
            }
        }

        struct Usage: Codable {
            let prompt_tokens: Int?
            let completion_tokens: Int?

            /// 방어적 디코딩 (v2.1 T-106) — 일부 호환 서버가 토큰 수를 문자열로 전송.
            /// strict 디코더면 usage 필드 하나가 청크 전체를 오염시켜 텍스트 델타까지 유실되므로
            /// usage만 관대하게 파싱한다.
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                prompt_tokens = Self.flexibleInt(c, .prompt_tokens)
                completion_tokens = Self.flexibleInt(c, .completion_tokens)
            }

            private static func flexibleInt(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
                if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return v }
                if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Int(s) }
                return nil
            }

            enum CodingKeys: String, CodingKey {
                case prompt_tokens, completion_tokens
            }
        }
    }

    /// SSE payload 파싱 — 텍스트/usage 추출 (테스트 가능하도록 분리, v1.9 T-76)
    static func parseSSEPayload(_ payload: String) -> (text: String?, promptTokens: Int?, completionTokens: Int?) {
        guard let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data) else { return (nil, nil, nil) }
        return (
            chunk.choices?.first?.delta.content,
            chunk.usage?.prompt_tokens,
            chunk.usage?.completion_tokens
        )
    }

    /// ChatMessage → API 메시지 변환 (시스템 프롬프트 선두 추가) — 테스트 가능하도록 분리 (v2.2 T-111)
    static func makeAPIMessages(systemPrompt: String?, messages: [ChatMessage]) -> [Message] {
        var apiMessages: [Message] = []
        if let sys = systemPrompt, !sys.isEmpty {
            apiMessages.append(Message(role: "system", text: sys))
        }
        for msg in messages where msg.role == .user || msg.role == .assistant {
            apiMessages.append(Message(role: msg.role.rawValue, text: msg.content, attachments: msg.attachments))
        }
        return apiMessages
    }

    /// 요청 바디 JSON 생성 — temperature 포함 여부 검증 가능하도록 내부 공개 (v2.2 T-111, v0.2.0 T-202 topP/maxTokens)
    static func encodeRequestBody(model: String, apiMessages: [Message],
                                  streamOptions: StreamOptions?, temperature: Double?,
                                  topP: Double? = nil, maxTokens: Int? = nil,
                                  tools: [APITool]? = nil) throws -> Data {
        let body = RequestBody(model: model, messages: apiMessages, stream: true,
                               stream_options: streamOptions, temperature: temperature,
                               topP: topP, maxTokens: maxTokens, tools: tools)
        return try JSONEncoder().encode(body)
    }

    // MARK: - 도구 호출 (v2.4 T-120)

    var supportsTools: Bool { true }

    func streamWithTools(
        messages: [ChatMessage], systemPrompt: String?, temperature: Double?,
        tools: [LLMToolDefinition], onUsage: ((Int?, Int?) -> Void)?
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        rawStreamWithTools(messages: messages, systemPrompt: systemPrompt, temperature: temperature, tools: tools, onUsage: onUsage)
    }

    func stream(messages: [ChatMessage], systemPrompt: String?, onUsage: ((Int?, Int?) -> Void)?) -> AsyncThrowingStream<String, Error> {
        stream(messages: messages, systemPrompt: systemPrompt, temperature: nil, onUsage: onUsage)
    }

    /// topP/maxTokens 지원 스트리밍 (v0.2.0 T-202) — 인프라 핵심, 실제 요청 바디에 top_p/max_tokens 반영
    func stream(messages: [ChatMessage], systemPrompt: String?, temperature: Double?,
                topP: Double?, maxTokens: Int?,
                onUsage: ((Int?, Int?) -> Void)?) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !apiKey.isEmpty || provider == .custom else {
                        // 커스텀 엔드포인트(LM Studio 등)는 키 없이도 호출 가능
                        throw AppError.missingKey(provider)
                    }

                    let apiMessages = Self.makeAPIMessages(systemPrompt: systemPrompt, messages: messages)

                    // stream_options는 검증된 공급자에만 전송 — 임의 로컬 서버의 미지원 파라미터 400 방어 (v1.9 T-76)
                    let streamOptions: StreamOptions? = provider == .custom ? nil : .init(include_usage: true)
                    let data = try Self.encodeRequestBody(
                        model: model, apiMessages: apiMessages,
                        streamOptions: streamOptions, temperature: temperature,
                        topP: topP, maxTokens: maxTokens)

                    let urlStr = baseURL + "/chat/completions"
                    DebugLogger.shared.info("API-OPENAI", "요청 URL: \(urlStr)")
                    DebugLogger.shared.debug("API-OPENAI", "메시지 수: \(apiMessages.count), 모델: \(model)")

                    var urlRequest = URLRequest(url: URL(string: urlStr)!)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    urlRequest.httpBody = data
                    urlRequest.timeoutInterval = 120

                    DebugLogger.shared.debug("API-OPENAI", "요청 전송 중...")
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else {
                        throw AppError.network("응답 없음")
                    }
                    DebugLogger.shared.info("API-OPENAI", "응답 상태: HTTP \(http.statusCode)")

                    if !(200..<300).contains(http.statusCode) {
                        var errBody = Data()
                        for try await b in bytes { errBody.append(b) }
                        let text = String(data: errBody, encoding: .utf8) ?? ""
                        DebugLogger.shared.error("API-OPENAI", "서버 에러 HTTP \(http.statusCode): \(text.prefix(500))")
                        throw AppError.serverError(http.statusCode, text)
                    }

                    DebugLogger.shared.debug("API-OPENAI", "스트리밍 수신 시작...")
                    var lineCount = 0
                    var lastPromptTokens: Int?
                    var lastCompletionTokens: Int?
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" {
                            DebugLogger.shared.debug("API-OPENAI", "[DONE] 수신. 스트리밍 종료.")
                            break
                        }
                        let parsed = Self.parseSSEPayload(payload)
                        if let text = parsed.text {
                            continuation.yield(text)
                            lineCount += 1
                        }
                        if parsed.promptTokens != nil || parsed.completionTokens != nil {
                            lastPromptTokens = parsed.promptTokens
                            lastCompletionTokens = parsed.completionTokens
                        }
                    }
                    DebugLogger.shared.info("API-OPENAI", "스트리밍 완료: \(lineCount)개 데이터 라인 처리")

                    if lastPromptTokens != nil || lastCompletionTokens != nil {
                        onUsage?(lastPromptTokens, lastCompletionTokens)
                        DebugLogger.shared.info("API-OPENAI", "[FEATURE] usage 수신됨: ↑\(lastPromptTokens.map(String.init) ?? "-") ↓\(lastCompletionTokens.map(String.init) ?? "-")")
                    }
                    continuation.finish()
                } catch is CancellationError {
                    DebugLogger.shared.warn("API-OPENAI", "요청 취소됨")
                    continuation.finish()
                } catch let error as AppError {
                    DebugLogger.shared.error("API-OPENAI", "[\(error.errorCode)] \(error.localizedDescription ?? "")")
                    continuation.finish(throwing: error)
                } catch {
                    DebugLogger.shared.error("API-OPENAI", "예상 못한 에러: \(error.localizedDescription)")
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

    /// temperature 지원 스트리밍 (v2.2 T-111) — nil이면 요청에서 생략(공급자 기본값)
    func stream(messages: [ChatMessage], systemPrompt: String?, temperature: Double?,
                onUsage: ((Int?, Int?) -> Void)?) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !apiKey.isEmpty || provider == .custom else {
                        // 커스텀 엔드포인트(LM Studio 등)는 키 없이도 호출 가능
                        throw AppError.missingKey(provider)
                    }

                    let apiMessages = Self.makeAPIMessages(systemPrompt: systemPrompt, messages: messages)

                    // stream_options는 검증된 공급자에만 전송 — 임의 로컬 서버의 미지원 파라미터 400 방어 (v1.9 T-76)
                    let streamOptions: StreamOptions? = provider == .custom ? nil : .init(include_usage: true)
                    let data = try Self.encodeRequestBody(
                        model: model, apiMessages: apiMessages,
                        streamOptions: streamOptions, temperature: temperature)

                    let urlStr = baseURL + "/chat/completions"
                    DebugLogger.shared.info("API-OPENAI", "요청 URL: \(urlStr)")
                    DebugLogger.shared.debug("API-OPENAI", "메시지 수: \(apiMessages.count), 모델: \(model)")

                    var urlRequest = URLRequest(url: URL(string: urlStr)!)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    urlRequest.httpBody = data
                    urlRequest.timeoutInterval = 120

                    DebugLogger.shared.debug("API-OPENAI", "요청 전송 중...")
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else {
                        throw AppError.network("응답 없음")
                    }
                    DebugLogger.shared.info("API-OPENAI", "응답 상태: HTTP \(http.statusCode)")

                    if !(200..<300).contains(http.statusCode) {
                        var errBody = Data()
                        for try await b in bytes { errBody.append(b) }
                        let text = String(data: errBody, encoding: .utf8) ?? ""
                        DebugLogger.shared.error("API-OPENAI", "서버 에러 HTTP \(http.statusCode): \(text.prefix(500))")
                        throw AppError.serverError(http.statusCode, text)
                    }

                    DebugLogger.shared.debug("API-OPENAI", "스트리밍 수신 시작...")
                    var lineCount = 0
                    var lastPromptTokens: Int?
                    var lastCompletionTokens: Int?
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" {
                            DebugLogger.shared.debug("API-OPENAI", "[DONE] 수신. 스트리밍 종료.")
                            break
                        }
                        let parsed = Self.parseSSEPayload(payload)
                        if let text = parsed.text {
                            continuation.yield(text)
                            lineCount += 1
                        }
                        // usage는 마지막 청크에 누적값으로 도착 (v1.9 T-76, PLAN D5)
                        if parsed.promptTokens != nil || parsed.completionTokens != nil {
                            lastPromptTokens = parsed.promptTokens
                            lastCompletionTokens = parsed.completionTokens
                        }
                    }
                    DebugLogger.shared.info("API-OPENAI", "스트리밍 완료: \(lineCount)개 데이터 라인 처리")

                    if lastPromptTokens != nil || lastCompletionTokens != nil {
                        onUsage?(lastPromptTokens, lastCompletionTokens)
                        DebugLogger.shared.info("API-OPENAI", "[FEATURE] usage 수신됨: ↑\(lastPromptTokens.map(String.init) ?? "-") ↓\(lastCompletionTokens.map(String.init) ?? "-")")
                    }
                    continuation.finish()
                } catch is CancellationError {
                    DebugLogger.shared.warn("API-OPENAI", "요청 취소됨")
                    continuation.finish()
                } catch let error as AppError {
                    DebugLogger.shared.error("API-OPENAI", "[\(error.errorCode)] \(error.localizedDescription ?? "")")
                    continuation.finish(throwing: error)
                } catch {
                    DebugLogger.shared.error("API-OPENAI", "예상 못한 에러: \(error.localizedDescription)")
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

    /// 도구 포함 스트리밍 (v2.4 T-120)
    /// 텍스트 델타는 즉시 발행, tool_calls 프래그먼트는 인덱스별로 누적해 스트림 종료 전 일괄 발행.
    func rawStreamWithTools(
        messages: [ChatMessage], systemPrompt: String?, temperature: Double?,
        tools: [LLMToolDefinition], onUsage: ((Int?, Int?) -> Void)?
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !apiKey.isEmpty || provider == .custom else {
                        throw AppError.missingKey(provider)
                    }
                    let apiMessages = Self.makeAPIMessages(systemPrompt: systemPrompt, messages: messages)
                    let apiTools = tools.map { APITool(from: $0) }
                    let streamOptions: StreamOptions? = provider == .custom ? nil : .init(include_usage: true)
                    let data = try Self.encodeRequestBody(
                        model: model, apiMessages: apiMessages,
                        streamOptions: streamOptions, temperature: temperature, tools: apiTools)

                    let urlStr = baseURL + "/chat/completions"
                    DebugLogger.shared.info("API-OPENAI", "[TOOLS] 요청 URL: \(urlStr), 도구 \(tools.count)개")

                    var urlRequest = URLRequest(url: URL(string: urlStr)!)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    urlRequest.httpBody = data
                    urlRequest.timeoutInterval = 120

                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else {
                        throw AppError.network("응답 없음")
                    }
                    if !(200..<300).contains(http.statusCode) {
                        var errBody = Data()
                        for try await b in bytes { errBody.append(b) }
                        let text = String(data: errBody, encoding: .utf8) ?? ""
                        DebugLogger.shared.error("API-OPENAI", "서버 에러 HTTP \(http.statusCode): \(text.prefix(500))")
                        throw AppError.serverError(http.statusCode, text)
                    }

                    // 인덱스별 조각 누적 — arguments는 여러 청크에 걸쳐 도착
                    var accumulated: [Int: (id: String, name: String, args: String)] = [:]
                    var lastPromptTokens: Int?
                    var lastCompletionTokens: Int?
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data2 = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data2) else { continue }

                        if let choice = chunk.choices?.first {
                            if let content = choice.delta.content, !content.isEmpty {
                                continuation.yield(.text(content))
                            }
                            for fragment in choice.delta.tool_calls ?? [] {
                                let idx = fragment.index ?? accumulated.count
                                var entry = accumulated[idx] ?? ("", "", "")
                                if let id = fragment.id, !id.isEmpty { entry.id = id }
                                if let name = fragment.function?.name, !name.isEmpty { entry.name = name }
                                if let args = fragment.function?.arguments { entry.args += args }
                                accumulated[idx] = entry
                            }
                        }
                        if let usage = chunk.usage {
                            if usage.prompt_tokens != nil { lastPromptTokens = usage.prompt_tokens }
                            if usage.completion_tokens != nil { lastCompletionTokens = usage.completion_tokens }
                        }
                    }

                    // 누적된 도구 호출 발행 — 이름 있는 것만 유효
                    let calls = accumulated
                        .sorted { $0.key < $1.key }
                        .compactMap { _, entry -> LLMToolCall? in
                            guard !entry.name.isEmpty else { return nil }
                            return LLMToolCall(
                                id: entry.id.isEmpty ? UUID().uuidString : entry.id,
                                name: entry.name,
                                argumentsJSON: entry.args)
                        }
                    if !calls.isEmpty {
                        DebugLogger.shared.info("API-OPENAI", "[FEATURE] 도구 호출 요청 수신: \(calls.map { $0.name }.joined(separator: ", "))")
                        continuation.yield(.toolCalls(calls))
                    }

                    if lastPromptTokens != nil || lastCompletionTokens != nil {
                        onUsage?(lastPromptTokens, lastCompletionTokens)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    DebugLogger.shared.warn("API-OPENAI", "[TOOLS] 요청 취소됨")
                    continuation.finish()
                } catch let error as AppError {
                    DebugLogger.shared.error("API-OPENAI", "[TOOLS][\(error.errorCode)] \(error.localizedDescription ?? "")")
                    continuation.finish(throwing: error)
                } catch {
                    DebugLogger.shared.error("API-OPENAI", "[TOOLS] 예상 못한 에러: \(error.localizedDescription)")
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
}