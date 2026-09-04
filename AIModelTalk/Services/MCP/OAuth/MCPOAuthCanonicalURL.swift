import Foundation

/// RFC 8707 OAuth 2.0 Authorization Server 정식 리소스 식별자
/// 리소스 표시자(resource indicator) 정규화 — 인증 서버가 올바른 리소스로 토큰 발급하도록 보장
struct MCPOAuthCanonicalURL {

    /// 리소스 URL → 정식 식별자 변환
    /// - scheme/host/port 정규화, 경로 제거, trailing slash 제거
    static func canonicalize(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = ""
        components?.query = nil
        components?.fragment = nil
        // 기본 포트 제거 (http:80, https:443)
        if let scheme = components?.scheme,
           let port = components?.port {
            if (scheme == "http" && port == 80) || (scheme == "https" && port == 443) {
                components?.port = nil
            }
        }
        return components?.url?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? url.absoluteString
    }

    /// 여러 리소스 URL → 정식 식별자 배열 (중복 제거, 정렬)
    static func canonicalize(_ urls: [URL]) -> [String] {
        Set(urls.map(canonicalize)).sorted()
    }

    /// 토큰 요청 시 `resource` 파라미터용 값 생성 (RFC 8707)
    /// 단일 리소스인 경우 문자열, 다중인 경우 배열 (공급자 따라 다름)
    static func resourceParameter(for url: URL) -> String {
        canonicalize(url)
    }

    /// 토큰 요청 시 `resource` 파라미터용 값 생성 (다중 리소스)
    static func resourceParameter(for urls: [URL]) -> [String] {
        canonicalize(urls)
    }

    /// 공급자 템플릿의 기본 URL에서 정식 식별자 추출
    static func fromProviderTemplate(_ template: MCPProviderTemplate) -> String {
        guard let url = URL(string: template.defaultURL) else {
            return template.defaultURL
        }
        return canonicalize(url)
    }
}