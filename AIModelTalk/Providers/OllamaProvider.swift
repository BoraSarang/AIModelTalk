import Foundation

/// Ollama 공급자 로직 — ChatClient 준수 클라이언트 + 모델 관리 서비스 (v1.8 T-70d)
/// (구 LLMProvider 래퍼는 v2.1 R1에서 제거 — 실사용 경로는 AIClientFactory) — 스트리밍 채팅 전용 (v1.8 T-70d)
struct OllamaClient: ChatClient {
    let baseURL: String
    let model: String

    private struct RequestBody: Codable {
        let model: String
        let messages: [Message]
        let stream: Bool
        /// 샘플링 옵션 — nil이면 생략 (v0.2.0 T-202)
        let options: Options?

        init(model: String, messages: [Message], stream: Bool, options: Options? = nil) {
            self.model = model
            self.messages = messages
            self.stream = stream
            self.options = options
        }

        struct Options: Codable {
            let temperature: Double?
            let top_p: Double?
            let num_predict: Int?
        }
    }

    private struct Message: Codable {
        let role: String
        let content: String
        /// 이미지 base64 배열 — llava 등 비전 모델용 (T-71). 없으면 인코딩 생략
        var images: [String]?

        init(role: String, text: String, attachments: [MessageAttachment]? = nil) {
            self.role = role
            self.content = text
            if let attachments, !attachments.isEmpty {
                self.images = attachments.map { $0.imageData.base64EncodedString() }
            } else {
                self.images = nil
            }
        }
    }

    private struct StreamChunk: Codable {
        let message: Message?
        let done: Bool
    }

    func stream(messages: [ChatMessage], systemPrompt: String?, onUsage: ((Int?, Int?) -> Void)?) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var apiMessages: [Message] = []
                    if let sys = systemPrompt, !sys.isEmpty {
                        apiMessages.append(Message(role: "system", text: sys))
                    }
                    for msg in messages where msg.role == .user || msg.role == .assistant {
                        apiMessages.append(Message(role: msg.role.rawValue, text: msg.content, attachments: msg.attachments))
                    }

                    let body = RequestBody(model: model, messages: apiMessages, stream: true)
                    let data = try JSONEncoder().encode(body)

                    let urlStr = "\(baseURL)/api/chat"
                    DebugLogger.shared.info("API-OLLAMA", "요청 URL: \(urlStr), 모델: \(model)")

                    var urlRequest = URLRequest(url: URL(string: urlStr)!)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.httpBody = data
                    urlRequest.timeoutInterval = 120

                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else {
                        throw AppError.network("응답 없음")
                    }
                    DebugLogger.shared.info("API-OLLAMA", "응답 상태: HTTP \(http.statusCode)")

                    if !(200..<300).contains(http.statusCode) {
                        var errBody = Data()
                        for try await b in bytes { errBody.append(b) }
                        let text = String(data: errBody, encoding: .utf8) ?? ""
                        DebugLogger.shared.error("API-OLLAMA", "서버 에러 HTTP \(http.statusCode): \(text.prefix(500))")
                        throw AppError.serverError(http.statusCode, text)
                    }

                    DebugLogger.shared.debug("API-OLLAMA", "스트리밍 수신 시작...")
                    var lastChunk: StreamChunk?
                    for try await line in bytes.lines {
                        guard let jsonData = line.data(using: .utf8) else { continue }
                        if let chunk = try? JSONDecoder().decode(StreamChunk.self, from: jsonData),
                           let text = chunk.message?.content {
                            continuation.yield(text)
                        }
                        lastChunk = try? JSONDecoder().decode(StreamChunk.self, from: jsonData)
                        if lastChunk?.done == true {
                            DebugLogger.shared.debug("API-OLLAMA", "[DONE] 수신. 스트리밍 종료.")
                            break
                        }
                    }
                    DebugLogger.shared.info("API-OLLAMA", "스트리밍 완료")
                    continuation.finish()
                } catch is CancellationError {
                    DebugLogger.shared.warn("API-OLLAMA", "요청 취소됨")
                    continuation.finish()
                } catch let error as AppError {
                    DebugLogger.shared.error("API-OLLAMA", "[\(error.errorCode)] \(error.localizedDescription ?? "")")
                    continuation.finish(throwing: error)
                } catch {
                    DebugLogger.shared.error("API-OLLAMA", "예상 못한 에러: \(error.localizedDescription)")
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

    /// temperature/topP/maxTokens 지원 스트리밍 (v0.2.0 T-202) — options에 반영
    func stream(messages: [ChatMessage], systemPrompt: String?, temperature: Double?,
                topP: Double? = nil, maxTokens: Int? = nil,
                onUsage: ((Int?, Int?) -> Void)?) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var apiMessages: [Message] = []
                    if let sys = systemPrompt, !sys.isEmpty {
                        apiMessages.append(Message(role: "system", text: sys))
                    }
                    for msg in messages where msg.role == .user || msg.role == .assistant {
                        apiMessages.append(Message(role: msg.role.rawValue, text: msg.content, attachments: msg.attachments))
                    }

                    // 온도/topP/maxTokens 중 하나라도 설정되면 options 포함, 아니면 생략
                    let hasOptions = temperature != nil || topP != nil || maxTokens != nil
                    let options: RequestBody.Options? = hasOptions
                        ? .init(temperature: temperature, top_p: topP, num_predict: maxTokens)
                        : nil
                    let body = RequestBody(model: model, messages: apiMessages, stream: true, options: options)
                    let data = try JSONEncoder().encode(body)

                    let urlStr = "\(baseURL)/api/chat"
                    DebugLogger.shared.info("API-OLLAMA", "요청 URL: \(urlStr), 모델: \(model)")

                    var urlRequest = URLRequest(url: URL(string: urlStr)!)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.httpBody = data
                    urlRequest.timeoutInterval = 120

                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else {
                        throw AppError.network("응답 없음")
                    }
                    DebugLogger.shared.info("API-OLLAMA", "응답 상태: HTTP \(http.statusCode)")

                    if !(200..<300).contains(http.statusCode) {
                        var errBody = Data()
                        for try await b in bytes { errBody.append(b) }
                        let text = String(data: errBody, encoding: .utf8) ?? ""
                        DebugLogger.shared.error("API-OLLAMA", "서버 에러 HTTP \(http.statusCode): \(text.prefix(500))")
                        throw AppError.serverError(http.statusCode, text)
                    }

                    DebugLogger.shared.debug("API-OLLAMA", "스트리밍 수신 시작...")
                    var lastChunk: StreamChunk?
                    for try await line in bytes.lines {
                        guard let jsonData = line.data(using: .utf8) else { continue }
                        if let chunk = try? JSONDecoder().decode(StreamChunk.self, from: jsonData),
                           let text = chunk.message?.content {
                            continuation.yield(text)
                        }
                        lastChunk = try? JSONDecoder().decode(StreamChunk.self, from: jsonData)
                        if lastChunk?.done == true {
                            DebugLogger.shared.debug("API-OLLAMA", "[DONE] 수신. 스트리밍 종료.")
                            break
                        }
                    }
                    DebugLogger.shared.info("API-OLLAMA", "스트리밍 완료")
                    continuation.finish()
                } catch is CancellationError {
                    DebugLogger.shared.warn("API-OLLAMA", "요청 취소됨")
                    continuation.finish()
                } catch let error as AppError {
                    DebugLogger.shared.error("API-OLLAMA", "[\(error.errorCode)] \(error.localizedDescription ?? "")")
                    continuation.finish(throwing: error)
                } catch {
                    DebugLogger.shared.error("API-OLLAMA", "예상 못한 에러: \(error.localizedDescription)")
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

/// Ollama 모델 설치/삭제 서비스 (v1.8 T-70d)
/// ModelManagerView에서 사용
@MainActor
final class OllamaService: ObservableObject {
    static let shared = OllamaService()

    @Published var pullProgress: [String: Double] = [:] // modelName -> 0.0~1.0
    @Published var isPulling = false
    @Published var pullError: String?

    private let baseURL: String

    init(baseURL: String = "http://localhost:11434") {
        self.baseURL = baseURL
    }

    /// 모델 설치 — 진행률 콜백으로 UI 업데이트
    func pullModel(_ modelName: String) async throws {
        isPulling = true
        pullError = nil
        pullProgress[modelName] = 0.0
        defer { isPulling = false }

        guard let url = URL(string: "\(baseURL)/api/pull") else { throw AppError.network("잘못된 BaseURL") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct PullRequest: Codable {
            let name: String
            let stream: Bool
        }
        req.httpBody = try JSONEncoder().encode(PullRequest(name: modelName, stream: true))

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppError.network("모델 설치 요청 실패")
        }

        struct PullProgress: Codable {
            let status: String
            let completed: Int64?
            let total: Int64?
        }

        for try await line in bytes.lines {
            guard let jsonData = line.data(using: .utf8),
                  let progress = try? JSONDecoder().decode(PullProgress.self, from: jsonData) else { continue }

            if let completed = progress.completed, let total = progress.total, total > 0 {
                pullProgress[modelName] = Double(completed) / Double(total)
            } else if progress.status.contains("success") || progress.status == "done" {
                pullProgress[modelName] = 1.0
            }
        }
        pullProgress[modelName] = 1.0
        DebugLogger.shared.info("OLLAMA", "모델 설치 완료: \(modelName)")
    }

    /// 모델 삭제
    func deleteModel(_ modelName: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/delete") else { throw AppError.network("잘못된 BaseURL") }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct DeleteRequest: Codable {
            let name: String
        }
        req.httpBody = try JSONEncoder().encode(DeleteRequest(name: modelName))

        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppError.network("모델 삭제 실패")
        }
        DebugLogger.shared.info("OLLAMA", "모델 삭제 완료: \(modelName)")
    }

    /// 서버 상태 확인
    func checkServer() async -> Bool {
        do {
            guard let url = URL(string: "\(baseURL)/api/tags") else { return false }
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}