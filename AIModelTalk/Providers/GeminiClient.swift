import Foundation

struct GeminiClient: ChatClient {
    let apiKey: String
    let model: String

    private struct RequestBody: Codable {
        let contents: [Content]
        let systemInstruction: Instruction?
        /// 캐릭터별 샘플링 온도 — nil이면 생략 (v2.2 T-111)
        var generationConfig: GenerationConfig?

        struct GenerationConfig: Codable {
            let temperature: Double?
            let topP: Double?
            let maxOutputTokens: Int?

            init(temperature: Double?, topP: Double? = nil, maxOutputTokens: Int? = nil) {
                self.temperature = temperature
                self.topP = topP
                self.maxOutputTokens = maxOutputTokens
            }
            // JSONEncoder는 nil 옵셔널 필드를 자동 생략 → 미설정 파라미터는 키가 안 나감
        }

        struct Content: Codable {
            let role: String
            let parts: [Part]
        }

        /// text 또는 inline_data(이미지 base64) 파트 — T-71
        struct Part: Codable {
            var text: String?
            var inlineData: InlineData?

            init(text: String) {
                self.text = text
                self.inlineData = nil
            }

            init(mimeType: String, base64: String) {
                self.text = nil
                self.inlineData = .init(mimeType: mimeType, data: base64)
            }

            struct InlineData: Codable {
                let mimeType: String
                let data: String
            }
        }

        struct Instruction: Codable {
            let parts: [Part]

            init(text: String) {
                self.parts = [.init(text: text)]
            }
        }
    }

    private struct StreamResponse: Codable {
        let candidates: [Candidate]?
        let usageMetadata: UsageMetadata?

        struct Candidate: Codable {
            let content: ResponseContent?
        }

        struct ResponseContent: Codable {
            let parts: [Part]
        }

        struct Part: Codable {
            let text: String?
        }

        struct UsageMetadata: Codable {
            let promptTokenCount: Int?
            let candidatesTokenCount: Int?
        }
    }

    /// Gemini SSE payload 파싱 — 텍스트/usage 추출 (테스트 가능하도록 분리, v2.1 T-95)
    static func parseGeminiPayload(_ payload: String) -> (text: String?, promptTokens: Int?, completionTokens: Int?) {
        guard let data = payload.data(using: .utf8),
              let resp = try? JSONDecoder().decode(StreamResponse.self, from: data) else { return (nil, nil, nil) }
        return (
            resp.candidates?.first?.content?.parts.first?.text,
            resp.usageMetadata?.promptTokenCount,
            resp.usageMetadata?.candidatesTokenCount
        )
    }

    func stream(messages: [ChatMessage], systemPrompt: String?, onUsage: ((Int?, Int?) -> Void)?) -> AsyncThrowingStream<String, Error> {
        stream(messages: messages, systemPrompt: systemPrompt, temperature: nil, onUsage: onUsage)
    }

    /// temperature/topP/maxTokens 지원 스트리밍 (v2.2 T-111, v0.2.0 T-202) — nil 파라미터는 generationConfig 생략
    func stream(messages: [ChatMessage], systemPrompt: String?, temperature: Double?,
                topP: Double? = nil, maxTokens: Int? = nil,
                onUsage: ((Int?, Int?) -> Void)?) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !apiKey.isEmpty else {
                        throw AppError.missingKey(.gemini)
                    }

                    var contents: [RequestBody.Content] = []
                    for msg in messages where msg.role == .user || msg.role == .assistant {
                        let role = msg.role == .assistant ? "model" : "user"
                        var parts: [RequestBody.Part] = [.init(text: msg.content)]
                        // 이미지 첨부 → inline_data 파트 변환 (T-71)
                        if let attachments = msg.attachments {
                            for attachment in attachments where attachment.mimeType.hasPrefix("image/") {
                                parts.append(.init(mimeType: attachment.mimeType, base64: attachment.imageData.base64EncodedString()))
                            }
                        }
                        contents.append(RequestBody.Content(role: role, parts: parts))
                    }

                    // Gemini는 마지막 콘텐츠가 model(assistant) 턴으로 끝나는 요청을 거부(400).
                    // 비교/도구 등 대화 컨텍스트 스냅샷이 assistant로 끝날 수 있으므로,
                    // 범용으로 마지막 턴이 model이면 보조 user 턴을 덧붙여 예방한다.
                    if contents.last?.role == "model" {
                        contents.append(RequestBody.Content(role: "user", parts: [.init(text: "계속하세요")]))
                    }

                    let instruction = systemPrompt.map { RequestBody.Instruction(text: $0) }
                    let hasParams = temperature != nil || topP != nil || maxTokens != nil
                    let generationConfig: RequestBody.GenerationConfig?
                    if hasParams {
                        generationConfig = RequestBody.GenerationConfig(temperature: temperature, topP: topP, maxOutputTokens: maxTokens)
                    } else {
                        generationConfig = nil
                    }
                    let body = RequestBody(contents: contents, systemInstruction: instruction, generationConfig: generationConfig)
                    let data = try JSONEncoder().encode(body)

                    let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent"
                    DebugLogger.shared.info("API-GEMINI", "요청 URL: \(urlStr)")
                    DebugLogger.shared.debug("API-GEMINI", "컨텐츠 수: \(contents.count), 모델: \(model)")

                    var components = URLComponents(string: urlStr)!
                    components.queryItems = [
                        URLQueryItem(name: "alt", value: "sse"),
                        URLQueryItem(name: "key", value: apiKey)
                    ]
                    var urlRequest = URLRequest(url: components.url!)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.httpBody = data
                    urlRequest.timeoutInterval = 120

                    DebugLogger.shared.debug("API-GEMINI", "요청 전송 중...")
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else {
                        throw AppError.network("응답 없음")
                    }
                    DebugLogger.shared.info("API-GEMINI", "응답 상태: HTTP \(http.statusCode)")

                    if !(200..<300).contains(http.statusCode) {
                        var errBody = Data()
                        for try await b in bytes { errBody.append(b) }
                        let text = String(data: errBody, encoding: .utf8) ?? ""
                        DebugLogger.shared.error("API-GEMINI", "서버 에러 HTTP \(http.statusCode): \(text.prefix(500))")
                        throw AppError.serverError(http.statusCode, text)
                    }

                    DebugLogger.shared.debug("API-GEMINI", "스트리밍 수신 시작...")
                    var lineCount = 0
                    var lastPromptTokens: Int?
                    var lastCompletionTokens: Int?
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if payload.isEmpty { continue }
                        // usageMetadata는 매 청차마다 누적값으로 도착 — 마지막 값 사용 (v2.1 T-95)
                        let parsed = Self.parseGeminiPayload(payload)
                        if let text = parsed.text {
                            continuation.yield(text)
                            lineCount += 1
                        }
                        if parsed.promptTokens != nil || parsed.completionTokens != nil {
                            lastPromptTokens = parsed.promptTokens
                            lastCompletionTokens = parsed.completionTokens
                        }
                    }

                    if lastPromptTokens != nil || lastCompletionTokens != nil {
                        onUsage?(lastPromptTokens, lastCompletionTokens)
                        DebugLogger.shared.info("API-GEMINI", "[FEATURE] usage 수신됨: ↑\(lastPromptTokens.map(String.init) ?? "-") ↓\(lastCompletionTokens.map(String.init) ?? "-")")
                    }
                    DebugLogger.shared.info("API-GEMINI", "스트리밍 완료: \(lineCount)개 데이터 라인 처리")
                    continuation.finish()
                } catch is CancellationError {
                    DebugLogger.shared.warn("API-GEMINI", "요청 취소됨")
                    continuation.finish()
                } catch let error as AppError {
                    DebugLogger.shared.error("API-GEMINI", "[\(error.errorCode)] \(error.localizedDescription ?? "")")
                    continuation.finish(throwing: error)
                } catch {
                    DebugLogger.shared.error("API-GEMINI", "예상 못한 에러: \(error.localizedDescription)")
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