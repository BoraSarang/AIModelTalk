import Foundation
import Security

/// 범용 시크릿 저장소 프로토콜 — 테스트 주입 가능
protocol SecretStore {
    func setSecret(_ value: String, forKey key: String)
    func secret(forKey key: String) -> String?
    func deleteSecret(forKey key: String)
}

/// macOS Keychain 래퍼 — MCP 서버 env 시크릿 저장용 (v2.4 T-119)
final class KeychainService: SecretStore {
    static let shared = KeychainService()
    private let service = "com.borasarang.AIModelTalk"

    func setSecret(_ value: String, forKey key: String) {
        deleteSecret(forKey: key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8)
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            DebugLogger.shared.error("MCP", "E-MAC-STOR-1002 Keychain 저장 실패: \(status)")
        }
    }

    func secret(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteSecret(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
