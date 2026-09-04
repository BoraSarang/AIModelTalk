import Foundation
import CryptoKit
import Security

/// PKCE (RFC 7636) S256 챌린지/베리파이어 생성
enum PKCE {

    /// code_verifier 생성 — 43~128자, URL-safe base64
    static func generateVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    /// code_challenge 생성 — SHA256(code_verifier) → URL-safe base64 (no padding)
    static func challenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncodedString()
    }

    /// 인증 요청용 파라미터 딕셔너리
    static func authorizationParameters(verifier: String) -> [String: String] {
        [
            "code_challenge": challenge(from: verifier),
            "code_challenge_method": "S256"
        ]
    }

    /// 토큰 요청용 파라미터 딕셔너리
    static func tokenParameters(verifier: String) -> [String: String] {
        ["code_verifier": verifier]
    }
}

/// URL-safe base64 인코딩 (패딩 제거, +→-, /→_)
extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// URL-safe base64 디코딩
extension String {
    func base64URLDecodedData() -> Data? {
        var base64 = self
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = 4 - (base64.count % 4)
        if padding < 4 { base64 += String(repeating: "=", count: padding) }
        return Data(base64Encoded: base64)
    }
}