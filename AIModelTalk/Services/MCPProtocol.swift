import Foundation

/// MCP stdio JSON-RPC 2.0 프로토콜 — 순수 인코딩/파싱 (v2.4 T-119)
/// 라인 단위(newline-delimited JSON) 프레이밍
enum MCPProtocol {

    static let protocolVersion = "2025-06-18"

    enum ProtocolError: Error, Equatable {
        case invalidLine
        case serverError(String)
    }


    /// 파싱된 인바운드 메시지
    enum Inbound: Equatable {
        case response(id: Int, result: [String: Any])
        case error(id: Int?, message: String)
        case notification(method: String)

        static func == (lhs: Inbound, rhs: Inbound) -> Bool {
            switch (lhs, rhs) {
            case let (.response(a, _), .response(b, _)): return a == b
            case let (.error(a, m), .error(b, n)): return a == b && m == n
            case let (.notification(m), .notification(n)): return m == n
            default: return false
            }
        }
    }

    // MARK: - 요청/알림 인코딩

    static func encode(_ object: [String: Any]) -> Data {
        var data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        data.append(0x0A) // newline framing
        return data
    }

    static func initializeRequest(id: Int, clientName: String, clientVersion: String) -> Data {
        encode([
            "jsonrpc": "2.0",
            "id": id,
            "method": "initialize",
            "params": [
                "protocolVersion": protocolVersion,
                "capabilities": [:],
                "clientInfo": ["name": clientName, "version": clientVersion]
            ]
        ])
    }

    static func initializedNotification() -> Data {
        encode(["jsonrpc": "2.0", "method": "notifications/initialized"])
    }

    static func toolsListRequest(id: Int) -> Data {
        encode(["jsonrpc": "2.0", "id": id, "method": "tools/list"])
    }

    static func toolsCallRequest(id: Int, name: String, arguments: [String: Any]) throws -> Data {
        encode([
            "jsonrpc": "2.0",
            "id": id,
            "method": "tools/call",
            "params": ["name": name, "arguments": arguments]
        ])
    }

    // MARK: - 응답 파싱

    /// 한 줄 파싱 — 응답·에러·알림 분류, 해석 불가면 nil
    static func parse(line raw: String) -> Inbound? {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            return nil
        }
        if let method = obj["method"] as? String, obj["id"] == nil {
            return .notification(method: method)
        }
        let id = (obj["id"] as? NSNumber)?.intValue
        if let err = obj["error"] as? [String: Any] {
            let message = (err["message"] as? String) ?? "알 수 없는 서버 오류"
            return .error(id: id, message: message)
        }
        guard let result = obj["result"] as? [String: Any] else { return nil }
        return .response(id: id ?? -1, result: result)
    }

    // MARK: - HTTP 전송용 파싱 (v2.4 T-122)

    /// JSON 바디 → Inbound — application/json 단일 응답 처리
    static func parseJSONBody(_ data: Data) -> Inbound? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return parse(line: text)
    }

    /// SSE 바디 → Inbound 배열 — 빈 줄로 구분된 이벤트 블록의 data: 줄을 결합해 파싱
    /// (progress 등 알림과 응답이 섞여 스트리밍될 수 있어 전부 반환)
    static func parseSSEBody(_ data: Data) -> [Inbound] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var inbounds: [Inbound] = []
        for block in text.components(separatedBy: "\n\n") {
            let dataLines = block
                .split(separator: "\n", omittingEmptySubsequences: true)
                .filter { $0.hasPrefix("data:") }
                .map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces) }
            guard !dataLines.isEmpty else { continue }
            if let inbound = parse(line: dataLines.joined(separator: "\n")) {
                inbounds.append(inbound)
            }
        }
        return inbounds
    }

    /// Inbound 배열에서 특정 id 응답·에러 추출 (알림은 무시)
    static func firstReply(id: Int, in inbounds: [Inbound]) -> Inbound? {
        inbounds.first {
            switch $0 {
            case let .response(replyID, _): return replyID == id
            case let .error(replyID, _): return replyID == nil || replyID == id
            case .notification: return false
            }
        }
    }

    /// tools/list 결과 → 도구 배열
    static func parseTools(fromResult result: [String: Any]) -> [MCPTool] {
        guard let items = result["tools"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let name = item["name"] as? String else { return nil }
            let description = item["description"] as? String ?? ""
            var schemaJSON = "{}"
            if let schema = item["inputSchema"],
               let data = try? JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys]) {
                schemaJSON = String(data: data, encoding: .utf8) ?? "{}"
            }
            return MCPTool(name: name, description: description, inputSchemaJSON: schemaJSON)
        }
    }

    /// tools/call 결과 — 텍스트 병합 + 오류 플래그
    struct CallOutcome: Equatable {
        let isError: Bool
        let text: String
    }

    /// tools/call 결과 파싱 — content 배열에서 텍스트 병합, isError면 오류로 판정
    static func parseCallResult(fromResult result: [String: Any]) -> CallOutcome {
        let isError = (result["isError"] as? Bool) ?? false
        var text = ""
        if let contents = result["content"] as? [[String: Any]] {
            for content in contents where (content["type"] as? String) == "text" {
                if let t = content["text"] as? String {
                    if !text.isEmpty { text += "\n" }
                    text += t
                }
            }
        }
        return CallOutcome(
            isError: isError,
            text: (isError && text.isEmpty) ? "도구 실행 오류 (내용 없음)" : text)
    }
}

/// localizedDescription이 사유를 유지하도록 (v2.4 T-122 — "작업을 완료할 수 없습니다" 래퍼 방지)
extension MCPProtocol.ProtocolError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidLine:
            return "응답 줄 해석 실패"
        case let .serverError(message):
            return message
        }
    }
}
