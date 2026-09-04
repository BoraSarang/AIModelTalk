import Foundation

/// `WWW-Authenticate: Bearer` 챌린지 파서 (RFC 6750, RFC 9728)
/// 401 응답에서 인증 서버 정보 추출
struct MCPWWWAuthenticate {

    struct Challenge {
        let realm: String?
        let scope: String?
        let error: String?
        let errorDescription: String?
        let errorUri: String?
        /// RFC 9728: authorization_server 파라미터 — ASM 엔드포인트 힌트
        let authorizationServer: String?
        /// RFC 9728: resource_metadata — PRM 엔드포인트 힌트
        let resourceMetadata: String?

        var isAuthorizationServerPresent: Bool {
            authorizationServer != nil && !authorizationServer!.isEmpty
        }
    }

    /// 헤더 값 파싱 — "Bearer realm="...", scope="...", error="...", authorization_server="...""
    static func parse(_ header: String) -> Challenge {
        // "Bearer " 프리픽스 제거
        let bearerPrefix = "Bearer "
        guard header.hasPrefix(bearerPrefix) else {
            return Challenge(realm: nil, scope: nil, error: nil, errorDescription: nil, errorUri: nil, authorizationServer: nil, resourceMetadata: nil)
        }

        let paramsString = header.dropFirst(bearerPrefix.count)
        var realm: String?
        var scope: String?
        var error: String?
        var errorDescription: String?
        var errorUri: String?
        var authorizationServer: String?
        var resourceMetadata: String?

        // 파라미터 파싱: key="value" 형태, 콤마로 구분 (따옴표 내 콤마 무시)
        let scanner = Scanner(string: String(paramsString))
        scanner.charactersToBeSkipped = .whitespaces

        while !scanner.isAtEnd {
            var key: NSString?
            if scanner.scanUpToCharacters(from: CharacterSet(charactersIn: "="), into: &key),
               scanner.scanString("=", into: nil) {
                var value: NSString?
if scanner.scanString("\"", into: nil),
               scanner.scanUpTo("\"", into: &value),
               scanner.scanString("\"", into: nil) {
                    let k = key as String?
                    let v = value as String?
                    switch k?.lowercased() {
                    case "realm": realm = v
                    case "scope": scope = v
                    case "error": error = v
                    case "error_description": errorDescription = v
                    case "error_uri": errorUri = v
                    case "authorization_server": authorizationServer = v
                    case "resource_metadata": resourceMetadata = v
                    default: break
                    }
                }
            }
            scanner.scanString(",", into: nil)
        }

        return Challenge(
            realm: realm,
            scope: scope,
            error: error,
            errorDescription: errorDescription,
            errorUri: errorUri,
            authorizationServer: authorizationServer,
            resourceMetadata: resourceMetadata
        )
    }

    /// HTTP 응답 헤더에서 첫 번째 Bearer 챌린지 추출
    static func extract(from response: HTTPURLResponse) -> Challenge? {
        let headers = response.allHeaderFields as? [String: String] ?? [:]
        // WWW-Authenticate는 단일 값이지만 여러 챌린지가 콤마로 연결될 수 있음
        // 여기선 첫 번째 Bearer만 파싱
        for (key, value) in headers where key.caseInsensitiveCompare("WWW-Authenticate") == .orderedSame {
            if value.hasPrefix("Bearer") {
                return parse(value)
            }
        }
        return nil
    }
}