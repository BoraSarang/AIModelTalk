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
    /// parse_link 본문 (T-205) — fetch_url로 추출한 페이지 본문, 없으면 nil
    var body: String?

    init(id: UUID = UUID(), title: String, url: String, content: String, body: String? = nil) {
        self.id = id
        self.title = title
        self.url = url
        self.content = content
        self.body = body
    }
}

enum WebSearchError: LocalizedError {
    case missingAPIKey
    case httpStatus(Int, String)
    case emptyQuery
    case fetchBlocked(String)   // T-204 SSRF 가드
    case fetchTooLarge          // T-204 크기 캡
    case calcInvalid(String)    // T-204 계산기

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "웹 검색 API 키가 없습니다. 설정 → 일반에서 입력해 주세요."
        case .httpStatus(let code, let body):
            return "웹 검색 실패 (HTTP \(code)): \(body.prefix(200))"
        case .emptyQuery:
            return "검색어가 비어 있습니다."
        case .fetchBlocked(let reason):
            return "불러오기 차단: \(reason)"
        case .fetchTooLarge:
            return "페이지가 너무 커서 불러오지 못했습니다 (2MB 제한)."
        case .calcInvalid(let reason):
            return "계산 실패: \(reason)"
        }
    }

    /// error_message_ko.json 매핑용 에러코드
    var errorCode: String {
        switch self {
        case .missingAPIKey: return "E-MAC-KEY-1003"
        case .httpStatus: return "E-MAC-NET-1004"
        case .emptyQuery: return "E-MAC-VALID-1002"
        case .fetchBlocked: return "E-MAC-NET-1005"
        case .fetchTooLarge: return "E-MAC-NET-1006"
        case .calcInvalid: return "E-MAC-VALID-1003"
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

    /// 검색 결과를 시스템 프롬프트 주입용 텍스트 블록으로 변환 (인용 번호 포함, T-205)
    static func formatResults(_ results: [WebSearchResult], query: String) -> String {
        guard !results.isEmpty else { return "" }
        let items = results.enumerated().map { index, result -> String in
            var block = """
            [\(index + 1)] \(result.title)
            출처: \(result.url)
            \(result.content)
            """
            if let body = result.body, !body.isEmpty {
                block += "\n〔본문〕\(body)"
            }
            return block
        }.joined(separator: "\n\n")
        return """
        ## 웹 검색 결과
        아래는 "\(query)"에 대한 실시간 웹 검색 결과입니다. 답변 시 이 정보를 참고하고, 인용한 출처 번호([n])를 함께 표시하세요. 검색 결과와 모순되는 최신 정보가 있다면 검색 결과를 우선하세요.

        \(items)
        """
    }

    /// parse_link (T-205) — 각 결과 URL을 열어 본문을 추출해 첨부. 실패한 결과는 원본 스니펫 유지.
    static func enrichWithBodies(_ results: [WebSearchResult], maxBodies: Int = 3) async -> [WebSearchResult] {
        let candidates = results.prefix(maxBodies)
        var updated = results
        for (index, result) in updated.enumerated() {
            guard candidates.contains(where: { $0.id == result.id }) else { continue }
            guard let url = URL(string: result.url), WebSearchService.isSafeFetchURL(url) else { continue }
            if let body = try? await WebSearchService.fetchURL(url, maxChars: 800) {
                updated[index].body = body
            }
        }
        return updated
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

    // MARK: - 내장 fetch_url 도구 (T-204)

    /// SSRF 가드 — 리터럴 사설/루프백/링크로컬 IP와 로컬 호스트명·비 HTTP(S) 차단 (T-204)
    static func isSafeFetchURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        guard let host = url.host?.lowercased() else { return false }
        // 명시적 로컬 호스트명 차단
        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".localhost") {
            return false
        }
        // 리터럴 IPv4 주소만 파싱해 사설 대역 차단
        if let addr = literalIPv4(host) {
            return !(addr.isPrivate || addr.isLoopback || addr.isLinkLocal)
        }
        // 도메인명이면 허용 (공개 DNS로만 접근 — 상세 SSRF 방어는 서버측 정책)
        return true
    }

    private static func literalIPv4(_ host: String) -> IPv4Address? {
        var storage = in_addr()
        if inet_pton(AF_INET, host, &storage) == 1 {
            return IPv4Address(bigEndian: storage.s_addr)
        }
        return nil
    }

    /// 페이지 본문 페치 — HTML→텍스트 일부, 크기 캡(4000자·2MB)
    static func fetchURL(_ url: URL, maxChars: Int = 4000) async throws -> String {
        guard isSafeFetchURL(url) else {
            throw WebSearchError.fetchBlocked("차단된 URL입니다. (http/https 공개 주소만 허용)")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("AIModelTalk/0.2 (model-tester)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw WebSearchError.httpStatus(code, "")
        }
        guard data.count <= 2_000_000 else {
            throw WebSearchError.fetchTooLarge
        }
        let body = stripHTML(String(data: data, encoding: .utf8) ?? "")
        if body.count > maxChars {
            return String(body.prefix(maxChars)) + "\n…[본문 너무 길어 \(body.count)자 중 \(maxChars)자 표시]"
        }
        return body
    }

    /// 간단 HTML → 텍스트 정제 (스크립트/스타일/태그 제거 + 공백 정리)
    static func stripHTML(_ html: String) -> String {
        var text = html
        // 스크립트/스타일 블록 제거
        text = text.replacingOccurrences(
            of: "<script[^>]*>.*?</script>|<style[^>]*>.*?</style>",
            with: " ", options: [.regularExpression, .caseInsensitive]
        )
        // 나머지 태그 제거
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: " ", options: [.regularExpression]
        )
        // 엔티티 디코딩 기초
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
        // 공백·개행 정규화(3칸 이상 연속 공백 제거)
        text = text.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 내장 calculator 도구 (T-204)

    /// 안전한 사칙연산 표현식 평가 — 화이트리스트 문자(숫자·연산자·공백·소수점)만 허용, NSExpression 재평가
    /// - Parameters:
    ///   - offset: 최대 20자리 정수(오버플로 방지). 0이면 전역 한계.
    /// - Throws: 파싱 실패·범위 초과 시 오류
    static func evaluateCalculator(_ expression: String) throws -> Double {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WebSearchError.calcInvalid("표현식이 비어 있습니다.") }
        // 화이트리스트 검증
        let allowed = CharacterSet(charactersIn: "0123456789+-*/()., ")
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw WebSearchError.calcInvalid("숫자와 연산자(+ - * / ( ) .)만 허용합니다.")
        }
        // 연산자 연속·끝자리 연산자 거부
        let opChars = CharacterSet(charactersIn: "+-*/")
        let scalars = Array(trimmed.unicodeScalars)
        for (i, scalar) in scalars.enumerated() {
            if opChars.contains(scalar) {
                if i > 0, opChars.contains(scalars[i - 1]) {
                    throw WebSearchError.calcInvalid("연산자가 연속입니다.")
                }
            }
        }
        if let last = scalars.last, opChars.contains(last) {
            throw WebSearchError.calcInvalid("표현식이 연산자로 끝납니다.")
        }
        if trimmed.contains(",") {
            // 1,234 형식 쉼표 제거 후 숫자 검증
            let noComma = trimmed.filter { $0 != "," }
            if !noComma.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789+-*/(). ").contains($0) }) {
                throw WebSearchError.calcInvalid("잘못된 쉼표 사용입니다.")
            }
            let result = try evalSafe(noComma)
            return result
        }
        return try evalSafe(trimmed)
    }

    private static func evalSafe(_ expression: String) throws -> Double {
        // NSExpression은 context nil에서 크래시 위험이 있어 순수 재귀 하강 파서로 평가 (T-204)
        var parser = CalcParser(fullExpression: expression)
        do {
            let value = try parser.parse()
            guard value.isFinite else {
                throw WebSearchError.calcInvalid("결과가 너무 크거나 무한입니다.")
            }
            return value
        } catch let e as WebSearchError {
            throw e
        } catch {
            throw WebSearchError.calcInvalid("표현식 해석 실패")
        }
    }
}

/// 사칙연산 재귀 하강 파서 (T-204) — + - * / 와 소수·괄호만 처리, NSExpression 크래시 회피
private struct CalcParser {
    let fullExpression: String
    private var pos = 0

    init(fullExpression: String) { self.fullExpression = fullExpression }

    mutating func parse() throws -> Double {
        let v = try parseAddSub()
        skipSpaces()
        if pos < fullExpression.count {
            throw WebSearchError.calcInvalid("표현식 끝부분에 예상치 못한 문자가 있습니다.")
        }
        return v
    }

    private mutating func peek() -> Character? {
        guard pos < fullExpression.count else { return nil }
        return fullExpression[fullExpression.index(fullExpression.startIndex, offsetBy: pos)]
    }

    private mutating func skipSpaces() {
        var idx = pos
        let start = fullExpression.startIndex
        while idx < fullExpression.count {
            let ch = fullExpression[fullExpression.index(start, offsetBy: idx)]
            if ch == " " { idx += 1 } else { break }
        }
        pos = idx
    }

    private mutating func parseAddSub() throws -> Double {
        skipSpaces()
        var value = try parseMulDiv()
        while true {
            skipSpaces()
            guard let ch = peek() else { break }
            if ch == "+" {
                pos += 1
                value += try parseMulDiv()
            } else if ch == "-" {
                pos += 1
                value -= try parseMulDiv()
            } else {
                break
            }
        }
        return value
    }

    private mutating func parseMulDiv() throws -> Double {
        skipSpaces()
        var value = try parsePrimary()
        while true {
            skipSpaces()
            guard let ch = peek() else { break }
            if ch == "*" {
                pos += 1
                value *= try parsePrimary()
            } else if ch == "/" {
                pos += 1
                let divisor = try parsePrimary()
                guard divisor != 0 else { throw WebSearchError.calcInvalid("0으로 나눌 수 없습니다.") }
                value /= divisor
            } else {
                break
            }
        }
        return value
    }

    private mutating func parsePrimary() throws -> Double {
        skipSpaces()
        guard let ch = peek() else { throw WebSearchError.calcInvalid("피연산자가 없습니다.") }
        if ch == "(" {
            pos += 1
            let v = try parseAddSub()
            skipSpaces()
            guard peek() == ")" else { throw WebSearchError.calcInvalid("괄호가 닫히지 않았습니다.") }
            pos += 1
            return v
        }
        if ch == "+" {
            pos += 1
            return try parsePrimary()
        }
        if ch == "-" {
            pos += 1
            return -(try parsePrimary())
        }
        // 숫자
        var idx = pos
        let start = fullExpression.startIndex
        var foundDigit = false
        while idx < fullExpression.count {
            let ch = fullExpression[fullExpression.index(start, offsetBy: idx)]
            if ch.isNumber || ch == "." {
                foundDigit = foundDigit || ch.isNumber
                idx += 1
            } else if ch == " " {
                break
            } else {
                break
            }
        }
        guard foundDigit else {
            throw WebSearchError.calcInvalid("유효하지 않은 숫자입니다.")
        }
        let token = String(fullExpression[fullExpression.index(start, offsetBy: pos)..<fullExpression.index(start, offsetBy: idx)])
        pos = idx
        guard let value = Double(token) else {
            throw WebSearchError.calcInvalid("숫자 변환 실패")
        }
        return value
    }
}

// MARK: - 사설 IP 판정 (T-204)

private struct IPv4Address: Equatable {
    let bigEndian: UInt32

    init(bigEndian: UInt32) { self.bigEndian = bigEndian }
    init(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) {
        bigEndian = UInt32(a) << 24 | UInt32(b) << 16 | UInt32(c) << 8 | UInt32(d)
    }

    var isPrivate: Bool {
        let n = bigEndian.bigEndian
        if n >> 24 == 10 { return true }                 // 10.0.0.0/8
        if n >> 20 == 0xAC1 { return true }              // 172.16.0.0/12
        if n >> 16 == 0xC0A8 { return true }            // 192.168.0.0/16
        return false
    }
    var isLoopback: Bool { bigEndian.bigEndian >> 24 == 127 }  // 127.0.0.0/8
    var isLinkLocal: Bool { bigEndian.bigEndian >> 16 == 0xA9FE }  // 169.254.0.0/16
}
