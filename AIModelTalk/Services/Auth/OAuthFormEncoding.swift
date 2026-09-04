import Foundation

/// `application/x-www-form-urlencoded` 인코딩 헬퍼
enum OAuthFormEncoding {

    /// 딕셔너리 → percent-encoded 쿼리 문자열
    static func encode(_ parameters: [String: String]) -> String {
        parameters
            .sorted(by: { $0.key < $1.key })
            .map { "\(encode($0.key))=\(encode($0.value))" }
            .joined(separator: "&")
    }

    /// 단일 값 percent-encoding (RFC 3986)
    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .oauthAllowed) ?? ""
    }

    /// 바디 데이터 생성
    static func body(_ parameters: [String: String]) -> Data {
        Data(encode(parameters).utf8)
    }
}

/// OAuth용 허용 문자 집합 (RFC 3986 unreserved + 일부)
extension CharacterSet {
    static let oauthAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}