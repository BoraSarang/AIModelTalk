import Foundation

/// RFC 7591 Dynamic Client Registration (DCR)
/// 클라이언트 ID/시크릿 동적 발급 — 사용자 설정 불필요
final class MCPOAuthRegistration {

    struct RegistrationRequest: Codable {
        let redirectUris: [String]
        let tokenEndpointAuthMethod: String
        let grantTypes: [String]
        let responseTypes: [String]
        let scope: String
        let clientName: String
        let clientUri: String?
        let logoUri: String?
        let contacts: [String]?
        let softwareId: String?
        let softwareVersion: String?

        enum CodingKeys: String, CodingKey {
            case redirectUris = "redirect_uris"
            case tokenEndpointAuthMethod = "token_endpoint_auth_method"
            case grantTypes = "grant_types"
            case responseTypes = "response_types"
            case scope
            case clientName = "client_name"
            case clientUri = "client_uri"
            case logoUri = "logo_uri"
            case contacts
            case softwareId = "software_id"
            case softwareVersion = "software_version"
        }

        static func defaultRequest(
            redirectURI: String,
            clientName: String = "Osaurus",
            scope: String,
            clientUri: String? = "https://osaurus.ai",
            logoUri: String? = nil
        ) -> RegistrationRequest {
            RegistrationRequest(
                redirectUris: [redirectURI],
                tokenEndpointAuthMethod: "none", // PKCE 사용 시 public client
                grantTypes: ["authorization_code", "refresh_token"],
                responseTypes: ["code"],
                scope: scope,
                clientName: clientName,
                clientUri: clientUri,
                logoUri: logoUri,
                contacts: nil,
                softwareId: "com.osaurus.Osaurus",
                softwareVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            )
        }
    }

    struct RegistrationResponse: Codable {
        let clientId: String
        let clientSecret: String?
        let clientIdIssuedAt: Int?
        let clientSecretExpiresAt: Int?
        let redirectUris: [String]
        let tokenEndpointAuthMethod: String?
        let grantTypes: [String]?
        let responseTypes: [String]?
        let scope: String?
        let clientName: String?

        enum CodingKeys: String, CodingKey {
            case clientId = "client_id"
            case clientSecret = "client_secret"
            case clientIdIssuedAt = "client_id_issued_at"
            case clientSecretExpiresAt = "client_secret_expires_at"
            case redirectUris = "redirect_uris"
            case tokenEndpointAuthMethod = "token_endpoint_auth_method"
            case grantTypes = "grant_types"
            case responseTypes = "response_types"
            case scope
            case clientName = "client_name"
        }
    }

    /// 클라이언트 등록 요청
    /// - Parameters:
    ///   - registrationEndpoint: ASM에서 얻은 registration_endpoint
    ///   - request: 등록 요청 파라미터
    ///   - initialAccessToken: 일부 공급자는 초기 액세스 토큰 요구 (Bearer 헤더)
    static func register(
        at endpoint: URL,
        request: RegistrationRequest,
        initialAccessToken: String? = nil
    ) async throws -> RegistrationResponse {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = initialAccessToken {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = try JSONEncoder().encode(request)

        DebugLogger.shared.info("MCP", "[REGISTRATION] DCR 요청: \(endpoint.absoluteString)")
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try checkResponse(response, data: data)

        let http = response as? HTTPURLResponse
        let body = String(data: data, encoding: .utf8) ?? ""
        DebugLogger.shared.debug("MCP", "[REGISTRATION] DCR 응답: HTTP \(http?.statusCode ?? 0) \(body.prefix(300))")

        do {
            let decoded = try JSONDecoder().decode(RegistrationResponse.self, from: data)
            DebugLogger.shared.info("MCP", "[REGISTRATION] DCR 성공: client_id=\(decoded.clientId) secret=\(decoded.clientSecret != nil ? "발급" : "없음")")
            return decoded
        } catch {
            DebugLogger.shared.error("MCP", "[REGISTRATION] DCR 응답 파싱 실패: \(error.localizedDescription) 바디: \(body.prefix(300))")
            throw OAuthRegistrationError.invalidResponse
        }
    }

    /// 클라이언트 정보 업데이트 (PUT) — redirect_uri 변경 등
    static func update(
        at endpoint: URL,
        clientId: String,
        request: RegistrationRequest,
        accessToken: String
    ) async throws -> RegistrationResponse {
        let url = endpoint.appendingPathComponent(clientId)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "PUT"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        DebugLogger.shared.info("MCP", "[REGISTRATION] DCR 업데이트: \(url.absoluteString)")
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try checkResponse(response, data: data)
        return try JSONDecoder().decode(RegistrationResponse.self, from: data)
    }

    /// 클라이언트 삭제 (DELETE) — 연결 해제 시 정리용
    static func delete(at endpoint: URL, clientId: String, accessToken: String) async throws {
        let url = endpoint.appendingPathComponent(clientId)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "DELETE"
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        DebugLogger.shared.info("MCP", "[REGISTRATION] DCR 삭제: \(url.absoluteString)")
        let (_, response) = try await URLSession.shared.data(for: urlRequest)
        try checkResponse(response, data: Data())
    }

    private static func checkResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode >= 400 {
            let msg = String(data: data.prefix(500), encoding: .utf8) ?? ""
            DebugLogger.shared.error("MCP", "[REGISTRATION] HTTP \(http.statusCode): \(msg.prefix(300))")
            throw OAuthRegistrationError.serverError("HTTP \(http.statusCode): \(msg)")
        }
    }
}

enum OAuthRegistrationError: Error, LocalizedError {
    case serverError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .serverError(let msg): return msg
        case .invalidResponse: return "등록 응답 파싱 실패"
        }
    }
}