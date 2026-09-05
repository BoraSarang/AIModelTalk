import Foundation
import AppKit

/// OAuth 2.1 DCR + PKCE 엔드투엔드 플로우 오케스트레이션
/// 1. 루프백 서버 시작 → 2. 인증 요청 URL 구성 → 3. 브라우저 열기 → 4. 콜백 수신 → 5. 토큰 교환 → 6. 토큰 저장
@MainActor
final class MCPOAuthService {

    struct OAuthResult {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: TimeInterval?
        let scope: String?
        let tokenType: String
        let clientId: String?
        let clientSecret: String?
    }

    struct TokenResponse: Codable {
        let accessToken: String
        let tokenType: String
        let expiresIn: Int?
        let refreshToken: String?
        let scope: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case tokenType = "token_type"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
            case scope
        }
    }

    /// 수동 OAuth 엔드포인트 결정 (T-333) — 순수 함수, 테스트 가능
    /// 우선순위: 사용자 커스텀 입력 > 템플릿 내장값. 둘 다 비면 nil.
    nonisolated static func resolveEndpoints(
        template: MCPProviderTemplate,
        customAuthorizationEndpoint: String?,
        customTokenEndpoint: String?
    ) -> (authorizationEndpoint: String?, tokenEndpoint: String?) {
        let customAuth = customAuthorizationEndpoint?.trimmingCharacters(in: .whitespacesAndNewlines)
        let customToken = customTokenEndpoint?.trimmingCharacters(in: .whitespacesAndNewlines)
        let auth = (customAuth?.isEmpty == false) ? customAuth : template.authorizationEndpoint
        let token = (customToken?.isEmpty == false) ? customToken : template.tokenEndpoint
        return (auth, token)
    }

    /// 전체 OAuth 플로우 실행
    /// - Parameters:
    ///   - config: 공급자 설정 (MCPProviderConfiguration에서 변환)
    ///   - scopes: 요청할 스코프
    ///   - knownIssuer: 알려진 인증 서버 issuer (템플릿에 있으면 전달, 없으면 nil로 자동 발견)
    ///   - authorizationEndpoint: 수동 OAuth 전용 authorize URL (DCR 미지원 공급자)
    ///   - tokenEndpoint: 수동 OAuth 전용 token URL (DCR 미지원 공급자)
    static func authenticate(
        config: MCPProviderConfiguration,
        scopes: [String],
        knownIssuer: String? = nil,
        authorizationEndpoint: String? = nil,
        tokenEndpoint: String? = nil
    ) async throws -> OAuthResult {
        let isManual = authorizationEndpoint != nil && tokenEndpoint != nil
        DebugLogger.shared.info("MCP", "[OAUTH] [\(config.displayName)] 인증 시작 (scopes: \(scopes.joined(separator: " ")), issuer: \(knownIssuer ?? "auto"), mode: \(isManual ? "수동" : "DCR"))")

        // 1. 루프백 서버 시작 (수동은 콘솔 등록 가능한 고정 포트 사용)
        let loopback: OAuthLoopbackServer
        if isManual {
            loopback = try OAuthLoopbackServer(fixedPort: OAuthLoopbackServer.manualLoopbackPort)
        } else {
            loopback = try OAuthLoopbackServer()
        }
        let callbackURL = loopback.callbackURL
        let verifier = PKCE.generateVerifier()
        DebugLogger.shared.debug("MCP", "[OAUTH] 루프백 서버 시작: \(callbackURL.absoluteString)")

        // 2. 인증 서버 메타데이터 — 수동은 템플릿 엔드포인트 직접 사용 (디스커버리 생략)
        let asm: MCPOAuthDiscovery.AuthorizationServerMetadata
        if isManual {
            asm = MCPOAuthDiscovery.AuthorizationServerMetadata(
                issuer: config.issuer ?? knownIssuer ?? "",
                authorizationEndpoint: authorizationEndpoint!,
                tokenEndpoint: tokenEndpoint!,
                jwksUri: nil,
                registrationEndpoint: nil,
                scopesSupported: scopes,
                responseTypesSupported: ["code"],
                grantTypesSupported: ["authorization_code", "refresh_token"],
                codeChallengeMethodsSupported: ["S256"],
                tokenEndpointAuthMethodsSupported: ["client_secret_post"]
            )
            DebugLogger.shared.debug("MCP", "[OAUTH] 수동 메타데이터 사용: auth=\(authorizationEndpoint!) token=\(tokenEndpoint!)")
        } else {
            let resourceURL = URL(string: config.url)!
            let (_, discovered) = try await MCPOAuthDiscovery.discoverAll(
                for: resourceURL,
                knownIssuer: knownIssuer ?? config.issuer
            )
            asm = discovered
            DebugLogger.shared.debug("MCP", "[OAUTH] 메타데이터 발견: auth=\(asm.authorizationEndpoint) token=\(asm.tokenEndpoint)")
        }

        // 3. 클라이언트 확정 — 수동은 사용자 등록 자격증명 직접 사용, DCR는 등록/기존 재사용
        let registrationResult: MCPOAuthRegistration.RegistrationResponse
        if isManual {
            guard let clientId = config.clientId?.trimmingCharacters(in: .whitespacesAndNewlines), !clientId.isEmpty else {
                DebugLogger.shared.error("MCP", "[OAUTH] 수동 OAuth: Client ID 누락")
                throw OAuthError.missingClientCredentials
            }
            registrationResult = MCPOAuthRegistration.RegistrationResponse(
                clientId: clientId,
                clientSecret: config.clientSecret,
                clientIdIssuedAt: nil,
                clientSecretExpiresAt: nil,
                redirectUris: [callbackURL.absoluteString],
                tokenEndpointAuthMethod: "client_secret_post",
                grantTypes: ["authorization_code", "refresh_token"],
                responseTypes: ["code"],
                scope: scopes.joined(separator: " "),
                clientName: "Osaurus"
            )
            DebugLogger.shared.info("MCP", "[OAUTH] 수동 클라이언트 사용: client_id=\(clientId.prefix(6))…")
        } else if let existingClientId = config.clientId, !existingClientId.isEmpty {
            // 기존 클라이언트 사용 — redirect_uri 업데이트 필요할 수 있음
            DebugLogger.shared.info("MCP", "[OAUTH] 기존 client_id 사용: \(existingClientId)")
            registrationResult = MCPOAuthRegistration.RegistrationResponse(
                clientId: existingClientId,
                clientSecret: config.clientSecret,
                clientIdIssuedAt: nil,
                clientSecretExpiresAt: nil,
                redirectUris: [callbackURL.absoluteString],
                tokenEndpointAuthMethod: "none",
                grantTypes: ["authorization_code", "refresh_token"],
                responseTypes: ["code"],
                scope: scopes.joined(separator: " "),
                clientName: "Osaurus"
            )
        } else {
            let request = MCPOAuthRegistration.RegistrationRequest.defaultRequest(
                redirectURI: callbackURL.absoluteString,
                scope: scopes.joined(separator: " ")
            )
            registrationResult = try await MCPOAuthRegistration.register(
                at: URL(string: asm.registrationEndpoint ?? asm.tokenEndpoint)!,
                request: request
            )
            DebugLogger.shared.debug("MCP", "[OAUTH] DCR 등록 완료: client_id=\(registrationResult.clientId) (secret: \(registrationResult.clientSecret != nil ? "발급" : "없음"))")
        }

        // 4. 인증 요청 URL 구성
        let state = UUID().uuidString
        let authURL = buildAuthorizationURL(
            authorizationEndpoint: asm.authorizationEndpoint,
            clientId: registrationResult.clientId,
            redirectURI: callbackURL.absoluteString,
            scope: scopes.joined(separator: " "),
            verifier: verifier,
            state: state
        )
        DebugLogger.shared.debug("MCP", "[OAUTH] 인증 URL: \(authURL.absoluteString)")

        // 5. 브라우저에서 인증 요청 열기
        let opened = await NSWorkspace.shared.open(authURL)
        DebugLogger.shared.info("MCP", "[OAUTH] 브라우저 열기: \(opened ? "성공" : "실패")")

        // 6. 콜백 대기 (코드 + state 수신)
        let callback = try await loopback.waitForCallback()
        DebugLogger.shared.info("MCP", "[OAUTH] 콜백 수신: \(callback.absoluteString)")
        guard let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            DebugLogger.shared.error("MCP", "[OAUTH] 콜백 파싱 실패: \(callback.absoluteString)")
            throw OAuthError.invalidCallback
        }

        let code = queryItems.first { $0.name == "code" }?.value
        let stateReceived = queryItems.first { $0.name == "state" }?.value
        let error = queryItems.first { $0.name == "error" }?.value

        if let error {
            let errorDescription = queryItems.first { $0.name == "error_description" }?.value
            DebugLogger.shared.error("MCP", "[OAUTH] 인증 서버 에러: \(error) \(errorDescription ?? "")")
            throw OAuthError.serverError("인증 실패: \(error) \(errorDescription ?? "")")
        }
        guard let code else {
            DebugLogger.shared.error("MCP", "[OAUTH] 인증 코드 누락: \(callback.absoluteString)")
            throw OAuthError.missingCode
        }
        // state 검증 (CSRF 방지)
        guard stateReceived == state else {
            DebugLogger.shared.error("MCP", "[OAUTH] state 불일치: 기대=\(state) 수신=\(stateReceived ?? "없음")")
            throw OAuthError.stateMismatch
        }
        DebugLogger.shared.debug("MCP", "[OAUTH] state 검증 통과, code 수신 완료")

        // 7. 토큰 교환
        let tokenResponse = try await exchangeToken(
            tokenEndpoint: asm.tokenEndpoint,
            clientId: registrationResult.clientId,
            clientSecret: registrationResult.clientSecret,
            code: code,
            redirectURI: callbackURL.absoluteString,
            verifier: verifier
        )
        DebugLogger.shared.info("MCP", "[OAUTH] 토큰 교환 완료: access_token=\(tokenResponse.accessToken.prefix(8))… token_type=\(tokenResponse.tokenType) expires_in=\(tokenResponse.expiresIn.map(String.init) ?? "nil") refresh=\(tokenResponse.refreshToken != nil ? "발급" : "없음")")

        return OAuthResult(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresIn: tokenResponse.expiresIn.map(TimeInterval.init),
            scope: tokenResponse.scope,
            tokenType: tokenResponse.tokenType,
            clientId: registrationResult.clientId,
            clientSecret: registrationResult.clientSecret
        )
    }

    /// 토큰 갱신 (refresh_token 사용)
    static func refreshToken(
        tokenEndpoint: String,
        clientId: String,
        refreshToken: String,
        scopes: [String]? = nil
    ) async throws -> TokenResponse {
        DebugLogger.shared.info("MCP", "[OAUTH] 토큰 갱신 요청 (client_id=\(clientId))")
        var params: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientId
        ]
        if let scopes {
            params["scope"] = scopes.joined(separator: " ")
        }

        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = OAuthFormEncoding.body(params)

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        DebugLogger.shared.debug("MCP", "[OAUTH] 토큰 갱신 성공")
        return decoded
    }

    /// 토큰 해지 (선택적) — 연결 해제 시 정리
    static func revokeToken(
        revocationEndpoint: String?,
        clientId: String,
        token: String,
        tokenTypeHint: String = "access_token"
    ) async throws {
        guard let endpoint = revocationEndpoint else { return }
        DebugLogger.shared.info("MCP", "[OAUTH] 토큰 해지 요청: \(endpoint)")
        var params: [String: String] = [
            "client_id": clientId,
            "token": token,
            "token_type_hint": tokenTypeHint
        ]

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = OAuthFormEncoding.body(params)

        let (_, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: Data())
        DebugLogger.shared.debug("MCP", "[OAUTH] 토큰 해지 완료")
    }

    // MARK: - Private Helpers

    private static func buildAuthorizationURL(
        authorizationEndpoint: String,
        clientId: String,
        redirectURI: String,
        scope: String,
        verifier: String,
        state: String
    ) -> URL {
        var components = URLComponents(string: authorizationEndpoint)!
        let pkceParams = PKCE.authorizationParameters(verifier: verifier)
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkceParams["code_challenge"]),
            URLQueryItem(name: "code_challenge_method", value: pkceParams["code_challenge_method"])
        ]
        return components.url!
    }

    private static func exchangeToken(
        tokenEndpoint: String,
        clientId: String,
        clientSecret: String?,
        code: String,
        redirectURI: String,
        verifier: String
    ) async throws -> TokenResponse {
        var params: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientId
        ]
        // 기밀 클라이언트면 client_secret 포함 (GitHub, Linear 등 수동 자격증명)
        if let clientSecret, !clientSecret.isEmpty {
            params["client_secret"] = clientSecret
        }
        // PKCE verifier 추가
        let pkceTokenParams = PKCE.tokenParameters(verifier: verifier)
        params.merge(pkceTokenParams) { _, new in new }

        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = OAuthFormEncoding.body(params)
        DebugLogger.shared.debug("MCP", "[OAUTH] 토큰 교환 요청: \(tokenEndpoint)")

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)

        let http = response as? HTTPURLResponse
        let body = String(data: data, encoding: .utf8) ?? ""
        DebugLogger.shared.debug("MCP", "[OAUTH] 토큰 교환 응답: HTTP \(http?.statusCode ?? 0) \(body.prefix(300))")

        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            DebugLogger.shared.error("MCP", "[OAUTH] 토큰 응답 파싱 실패: \(error.localizedDescription) 바디: \(body.prefix(300))")
            throw OAuthError.tokenExchangeFailed(String(body.prefix(300)))
        }
    }

    private static func checkResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode >= 400 {
            let msg = String(data: data.prefix(500), encoding: .utf8) ?? ""
            DebugLogger.shared.error("MCP", "[OAUTH] HTTP \(http.statusCode): \(msg.prefix(300))")
            throw OAuthError.serverError("HTTP \(http.statusCode): \(msg)")
        }
    }
}