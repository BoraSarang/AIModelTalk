import Foundation
import Network

/// RFC 8252 루프백 콜백 서버 — 로컬 포트에서 OAuth 리다이렉트 수신
/// 단일 요청 처리 후 자동 종료 (한 번만 사용)
final class OAuthLoopbackServer {

    private let listener: NWListener
    private let port: UInt16
    private var continuation: CheckedContinuation<URL, Error>?
    private let queue = DispatchQueue(label: "com.osaurus.oauth.loopback", qos: .userInitiated)

    /// 사용 가능한 임의 포트 바인딩
    init() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        self.listener = try NWListener(using: params, on: .any)
        self.port = listener.port?.rawValue ?? 0
    }

    /// 서버 시작 및 단일 콜백 대기
    /// - Returns: 전체 리다이렉트 URL (query/fragment 포함)
    func waitForCallback(timeout: TimeInterval = 300) async throws -> URL {
        DebugLogger.shared.info("OAUTH", "[Loopback] 서버 시작 대기 (timeout: \(Int(timeout))s)")
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    DebugLogger.shared.info("OAUTH", "[Loopback] 리슨 준비: 포트 \(self?.port ?? 0)")
                case .failed(let error):
                    DebugLogger.shared.error("OAUTH", "[Loopback] 리슨 실패: \(error.localizedDescription)")
                    self?.fail(error)
                case .cancelled:
                    DebugLogger.shared.warn("OAUTH", "[Loopback] 취소됨")
                    self?.fail(CancellationError())
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                DebugLogger.shared.debug("OAUTH", "[Loopback] 새 연결 수신")
                self?.handleConnection(connection)
            }

            listener.start(queue: queue)

            // 타임아웃 워커
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                DebugLogger.shared.error("OAUTH", "[Loopback] 타임아웃 (\(Int(timeout))s)")
                self?.fail(OAuthError.timeout)
            }
        }
    }

    /// 콜백 URL 구성 — 앱 스킴으로 리다이렉트
    var callbackURL: URL {
        URL(string: "http://127.0.0.1:\(port)/callback")!
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                DebugLogger.shared.error("OAUTH", "[Loopback] 연결 에러: \(error.localizedDescription)")
                self.fail(error)
                connection.cancel()
                return
            }

            guard let data, !data.isEmpty else {
                if isComplete {
                    DebugLogger.shared.debug("OAUTH", "[Loopback] 연결 종료 (데이터 없음)")
                    connection.cancel()
                }
                return
            }

            let requestText = String(data: data, encoding: .utf8) ?? ""
            DebugLogger.shared.debug("OAUTH", "[Loopback] HTTP 요청: \(requestText.prefix(300))")

            // GET /callback?code=...&state=... 파싱
            if let url = self.parseCallbackURL(from: requestText) {
                DebugLogger.shared.info("OAUTH", "[Loopback] 콜백 파싱 성공: \(url.absoluteString)")
                self.succeed(url)
            } else {
                DebugLogger.shared.error("OAUTH", "[Loopback] 콜백 파싱 실패 — 요청: \(requestText.prefix(300))")
                self.fail(OAuthError.invalidCallback)
            }

            // 간단한 HTML 응답 전송
            let response = """
                HTTP/1.1 200 OK\r
                Content-Type: text/html; charset=utf-8\r
                Connection: close\r
                \r
                <!DOCTYPE html><html><head><meta charset="utf-8"><title>Osaurus</title></head>
                <body style="font-family:-apple-system;text-align:center;padding:3rem">
                <h2>✅ 인증 완료</h2>
                <p>이 창을 닫고 Osaurus로 돌아가세요.</p>
                <script>window.close()</script>
                </body></html>
                """
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func parseCallbackURL(from request: String) -> URL? {
        // "GET /callback?code=xxx&state=yyy HTTP/1.1" 형태 파싱
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first,
              firstLine.hasPrefix("GET ") else { return nil }

        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let path = String(parts[1])

        // 경로에 쿼리 포함됨 — 절대 URL로 구성
        return URL(string: "http://127.0.0.1:\(port)\(path)")
    }

    private func succeed(_ url: URL) {
        continuation?.resume(returning: url)
        continuation = nil
        shutdown()
    }

    private func fail(_ error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
        shutdown()
    }

    private func shutdown() {
        listener.stateUpdateHandler = nil
        listener.newConnectionHandler = nil
        listener.cancel()
    }

    private func log(_ message: String) {
        DebugLogger.shared.debug("OAUTH", "[Loopback] \(message)")
    }
}