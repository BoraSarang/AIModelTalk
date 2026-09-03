import Foundation

/// 웹 검색 프로바이더 추상화 (v1.8 T-72)
/// Tavily 우선 지원 — Serper/Brave는 향후 확장
enum WebSearchBackend: String, CaseIterable {
    case tavily = "Tavily"

    var signupURL: String? {
        switch self {
        case .tavily: return "https://app.tavily.com/"
        }
    }
}

struct WebSearchResult: Identifiable, Equatable {
    let id: UUID
    let title: String
    let url: String
    let content: String

    init(id: UUID = UUID(), title: String, url: String, content: String) {
        self.id = id
        self.title = title
        self.url = url
        self.content = content
    }
}

enum WebSearchError: LocalizedError {
    case missingAPIKey
    case httpStatus(Int, String)
    case emptyQuery

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "웹 검색 API 키가 없습니다. 설정 → 일반에서 입력해 주세요."
        case .httpStatus(let code, let body):
            return "웹 검색 실패 (HTTP \(code)): \(body.prefix(200))"
        case .emptyQuery:
            return "검색어가 비어 있습니다."
        }
    }

    /// error_message_ko.json 매핑용 에러코드
    var errorCode: String {
        switch self {
        case .missingAPIKey: return "E-MAC-KEY-1003"
        case .httpStatus: return "E-MAC-NET-1004"
        case .emptyQuery: return "E-MAC-VALID-1002"
        }
    }
}

enum WebSearchService {

    /// Tavily /search 호출 — 무료 1000회/월
    static func search(
        query: String,
        apiKey: String,
        backend: WebSearchBackend = .tavily,
        maxResults: Int = 5
    ) async throws -> [WebSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WebSearchError.emptyQuery }
        guard !apiKey.isEmpty else { throw WebSearchError.missingAPIKey }

        switch backend {
        case .tavily:
            return try await searchTavily(query: trimmed, apiKey: apiKey, maxResults: maxResults)
        }
    }

    /// 검색 결과를 시스템 프롬프트 주입용 텍스트 블록으로 변환
    static func formatResults(_ results: [WebSearchResult], query: String) -> String {
        guard !results.isEmpty else { return "" }
        let items = results.enumerated().map { index, result -> String in
            """
            [\(index + 1)] \(result.title)
            출처: \(result.url)
            \(result.content)
            """
        }.joined(separator: "\n\n")
        return """
        ## 웹 검색 결과
        아래는 "\(query)"에 대한 실시간 웹 검색 결과입니다. 답변 시 이 정보를 참고하고, 인용한 출처 번호를 함께 표시하세요. 검색 결과와 모순되는 최신 정보가 있다면 검색 결과를 우선하세요.

        \(items)
        """
    }

    // MARK: - Tavily

    private struct TavilyResponse: Decodable {
        let results: [Item]

        struct Item: Decodable {
            let title: String?
            let url: String?
            let content: String?
        }
    }

    private static func searchTavily(query: String, apiKey: String, maxResults: Int) async throws -> [WebSearchResult] {
        guard let url = URL(string: "https://api.tavily.com/search") else {
            throw AppError.network("잘못된 Tavily URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "query": query,
            "max_results": maxResults,
            "search_depth": "basic"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        DebugLogger.shared.info("WEBSEARCH", "Tavily 검색: \(query.prefix(60))")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AppError.network("응답 없음")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            DebugLogger.shared.error("WEBSEARCH", "[E-MAC-NET-1003] HTTP \(http.statusCode): \(bodyText.prefix(200))")
            throw WebSearchError.httpStatus(http.statusCode, bodyText)
        }

        let decoded = try JSONDecoder().decode(TavilyResponse.self, from: data)
        let results = decoded.results.compactMap { item -> WebSearchResult? in
            guard let url = item.url else { return nil }
            return WebSearchResult(
                title: item.title ?? "(제목 없음)",
                url: url,
                content: item.content ?? ""
            )
        }
        DebugLogger.shared.info("WEBSEARCH", "검색 완료: \(results.count)개 결과")
        return results
    }
}
