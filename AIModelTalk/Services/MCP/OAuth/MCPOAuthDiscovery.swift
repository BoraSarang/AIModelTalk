import Foundation

/// RFC 8414 ASM (Authorization Server Metadata) + RFC 9728 PRM (Protected Resource Metadata)
/// OAuth 2.1 DCR을 위한 메타데이터 디스커버리
final class MCPOAuthDiscovery {

    struct AuthorizationServerMetadata: Codable {
        let issuer: String
        let authorizationEndpoint: String
        let tokenEndpoint: String
        let jwksUri: String?
        let registrationEndpoint: String?
        let scopesSupported: [String]?
        let responseTypesSupported: [String]?
        let grantTypesSupported: [String]?
        let codeChallengeMethodsSupported: [String]?
        let tokenEndpointAuthMethodsSupported: [String]?

        enum CodingKeys: String, CodingKey {
            case issuer
            case authorizationEndpoint = "authorization_endpoint"
            case tokenEndpoint = "token_endpoint"
            case jwksUri = "jwks_uri"
            case registrationEndpoint = "registration_endpoint"
            case scopesSupported = "scopes_supported"
            case responseTypesSupported = "response_types_supported"
            case grantTypesSupported = "grant_types_supported"
            case codeChallengeMethodsSupported = "code_challenge_methods_supported"
            case tokenEndpointAuthMethodsSupported = "token_endpoint_auth_methods_supported"
        }
    }

    struct ProtectedResourceMetadata: Codable {
        let resource: String
        let authorizationServers: [String]?
        let scopesSupported: [String]?
        let bearerMethodsSupported: [String]?

        enum CodingKeys: String, CodingKey {
            case resource
            case authorizationServers = "authorization_servers"
            case scopesSupported = "scopes_supported"
            case bearerMethodsSupported = "bearer_methods_supported"
        }
    }

    /// 보호 리소스 메타데이터 조회 (RFC 9728) — .well-known/oauth-protected-resource
    static func discoverProtectedResource(for url: URL) async throws -> ProtectedResourceMetadata {
        let base = url.scheme! + "://" + url.host!
        let wellKnown = URL(string: "\(base)/.well-known/oauth-protected-resource")!
        DebugLogger.shared.info("MCP", "[DISCOVERY] PRM 요청: \(wellKnown.absoluteString)")
        let (data, response) = try await URLSession.shared.data(from: wellKnown)
        let http = response as? HTTPURLResponse
        let body = String(data: data, encoding: .utf8) ?? ""
        DebugLogger.shared.debug("MCP", "[DISCOVERY] PRM 응답: HTTP \(http?.statusCode ?? 0) \(body.prefix(300))")

        do {
            return try JSONDecoder().decode(ProtectedResourceMetadata.self, from: data)
        } catch {
            DebugLogger.shared.warn("MCP", "[DISCOVERY] PRM 파싱 실패: \(error.localizedDescription) HTTP \(http?.statusCode ?? 0)")
            throw OAuthDiscoveryError.invalidMetadata
        }
    }

    /// 인증 서버 메타데이터 조회 (RFC 8414) — .well-known/oauth-authorization-server
    /// OAuth ASM 실패 시 OIDC 폴백 (.well-known/openid-configuration)
    static func discoverAuthorizationServer(issuer: String) async throws -> AuthorizationServerMetadata {
        // 1차: OAuth ASM
        let oauthURL = URL(string: "\(issuer)/.well-known/oauth-authorization-server")!
        DebugLogger.shared.info("MCP", "[DISCOVERY] ASM 요청: \(oauthURL.absoluteString)")
        if let (data, response) = try? await URLSession.shared.data(from: oauthURL) {
            let http = response as? HTTPURLResponse
            let body = String(data: data, encoding: .utf8) ?? ""
            DebugLogger.shared.debug("MCP", "[DISCOVERY] ASM 응답: HTTP \(http?.statusCode ?? 0) \(body.prefix(300))")
            if let decoded = try? JSONDecoder().decode(AuthorizationServerMetadata.self, from: data) {
                DebugLogger.shared.info("MCP", "[DISCOVERY] ASM 발견: issuer=\(decoded.issuer) auth=\(decoded.authorizationEndpoint) token=\(decoded.tokenEndpoint) reg=\(decoded.registrationEndpoint ?? "없음")")
                return decoded
            } else {
                DebugLogger.shared.warn("MCP", "[DISCOVERY] ASM 파싱 실패 — OIDC 폴백 시도")
            }
        } else {
            DebugLogger.shared.warn("MCP", "[DISCOVERY] ASM HTTP 오류 — OIDC 폴백 시도")
        }

        // 2차: OIDC 폴백 (Google, GitHub, GitLab 등 OAuth-only 엔드포인트 미지원)
        return try await discoverOIDC(issuer: issuer)
    }

    /// 통합 디스커버리: 리소스 → 인증 서버 순서로 자동 탐색
    /// 공급자 템플릿에 issuer가 명시돼 있으면 바로 사용, 없으면 보호 리소스에서 발견
    static func discoverAll(for resourceURL: URL, knownIssuer: String?) async throws -> (ProtectedResourceMetadata?, AuthorizationServerMetadata) {
        // issuer가 명시되면 PRM 없이 바로 ASM 사용
        if let knownIssuer = knownIssuer {
            DebugLogger.shared.info("MCP", "[DISCOVERY] 템플릿 issuer 사용: \(knownIssuer)")
            let asm = try await discoverAuthorizationServer(issuer: knownIssuer)
            return (nil, asm)
        }

        DebugLogger.shared.info("MCP", "[DISCOVERY] issuer 미지정 — PRM에서 자동 발견 (resource: \(resourceURL.absoluteString))")
        if let prm = try? await discoverProtectedResource(for: resourceURL) {
            let issuer = prm.authorizationServers?.first
            if let issuer {
                let asm = try await discoverAuthorizationServer(issuer: issuer)
                return (prm, asm)
            }
            DebugLogger.shared.warn("MCP", "[DISCOVERY] PRM에 authorization_servers 없음")
        } else {
            DebugLogger.shared.warn("MCP", "[DISCOVERY] PRM 조회 실패/비지원 — issuer 필수")
        }
        throw OAuthDiscoveryError.noAuthorizationServer
    }

    /// OIDC 디스커버리 폴백 — 일부 공급자는 OAuth 대신 OIDC 엔드포인트만 제공
    static func discoverOIDC(issuer: String) async throws -> AuthorizationServerMetadata {
        let wellKnown = URL(string: "\(issuer)/.well-known/openid-configuration")!
        DebugLogger.shared.info("MCP", "[DISCOVERY] OIDC 요청: \(wellKnown.absoluteString)")
        let (data, response) = try await URLSession.shared.data(from: wellKnown)
        let http = response as? HTTPURLResponse
        let body = String(data: data, encoding: .utf8) ?? ""
        DebugLogger.shared.debug("MCP", "[DISCOVERY] OIDC 응답: HTTP \(http?.statusCode ?? 0) \(body.prefix(300))")

        do {
            let decoded = try JSONDecoder().decode(AuthorizationServerMetadata.self, from: data)
            DebugLogger.shared.info("MCP", "[DISCOVERY] OIDC 발견: issuer=\(decoded.issuer) auth=\(decoded.authorizationEndpoint) token=\(decoded.tokenEndpoint)")
            return decoded
        } catch {
            DebugLogger.shared.error("MCP", "[DISCOVERY] OIDC 파싱 실패: \(error.localizedDescription) HTTP \(http?.statusCode ?? 0)")
            throw OAuthDiscoveryError.invalidMetadata
        }
    }
}

enum OAuthDiscoveryError: Error, LocalizedError {
    case noAuthorizationServer
    case invalidMetadata
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .noAuthorizationServer: return "인증 서버를 찾을 수 없습니다"
        case .invalidMetadata: return "메타데이터 파싱 실패"
        case .networkError(let e): return "네트워크 오류: \(e.localizedDescription)"
        }
    }
}