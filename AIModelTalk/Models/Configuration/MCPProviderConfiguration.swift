import Foundation

/// 원격 MCP 공급자 설정 (연결된 공급자 인스턴스)
/// MCPServerConfig와 별도 — 공급자 메타데이터 + OAuth 토큰 + 연결 상태 관리
struct MCPProviderConfiguration: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var templateID: String                  // MCPProviderTemplate.id (연결된 템플릿)
    var name: String                        // 사용자 지정 이름 (템플릿 이름 기본)
    var url: String                         // 엔드포인트 URL
    var authMode: MCPAuthMode
    var isEnabled: Bool = true

    // OAuth 2.1 DCR 결과
    var clientId: String?
    var clientSecret: String?               // Keychain에 별도 저장 권장, 여기선 참조용
    var issuer: String?                     // 인증 서버 issuer

    // 토큰 (Keychain 저장 키 참조)
    var accessTokenKey: String?             // "mcp.provider.<id>.access_token"
    var refreshTokenKey: String?            // "mcp.provider.<id>.refresh_token"
    var tokenExpiresAt: Date?               // 만료 시간 (자동 갱신용)

    // API Key 모드용
    var apiKeyKey: String?                  // "mcp.provider.<id>.api_key"

    // 연결 상태 캐시
    var lastConnectedAt: Date?
    var lastError: String?
    var toolCount: Int = 0

    // MARK: - 편의 프로퍼티

    var template: MCPProviderTemplate? {
        MCPProviderTemplate.catalog.first { $0.id == templateID }
    }

    var displayName: String {
        name.isEmpty ? (template?.name ?? templateID) : name
    }

    var requiresBrowserAuth: Bool {
        authMode == .oauth21DCR || authMode == .oauth21Manual
    }

    var isConnected: Bool {
        lastConnectedAt != nil && lastError == nil
    }

    // MARK: - Keychain 키 생성

    func keychainPrefix() -> String {
        "mcp.provider.\(id.uuidString)"
    }

    func accessTokenKeyName() -> String {
        "\(keychainPrefix()).access_token"
    }

    func refreshTokenKeyName() -> String {
        "\(keychainPrefix()).refresh_token"
    }

    func clientSecretKeyName() -> String {
        "\(keychainPrefix()).client_secret"
    }

    func apiKeyKeyName() -> String {
        "\(keychainPrefix()).api_key"
    }

    // MARK: - 초기화

    init(
        id: UUID = UUID(),
        templateID: String,
        name: String = "",
        url: String,
        authMode: MCPAuthMode,
        isEnabled: Bool = true,
        clientId: String? = nil,
        clientSecret: String? = nil,
        issuer: String? = nil,
        accessTokenKey: String? = nil,
        refreshTokenKey: String? = nil,
        tokenExpiresAt: Date? = nil,
        apiKeyKey: String? = nil,
        lastConnectedAt: Date? = nil,
        lastError: String? = nil,
        toolCount: Int = 0
    ) {
        self.id = id
        self.templateID = templateID
        self.name = name
        self.url = url
        self.authMode = authMode
        self.isEnabled = isEnabled
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.issuer = issuer
        self.accessTokenKey = accessTokenKey
        self.refreshTokenKey = refreshTokenKey
        self.tokenExpiresAt = tokenExpiresAt
        self.apiKeyKey = apiKeyKey
        self.lastConnectedAt = lastConnectedAt
        self.lastError = lastError
        self.toolCount = toolCount
    }

    /// 템플릿으로부터 기본 설정 생성
    static func fromTemplate(_ template: MCPProviderTemplate, customURL: String? = nil) -> MCPProviderConfiguration {
        MCPProviderConfiguration(
            templateID: template.id,
            name: template.name,
            url: customURL ?? template.defaultURL,
            authMode: template.authMode,
            issuer: template.issuer
        )
    }

    // MARK: - Codable 호환 (기존 저장 데이터 마이그레이션)

    private enum CodingKeys: String, CodingKey {
        case id, templateID, name, url, authMode, isEnabled
        case clientId, clientSecret, issuer
        case accessTokenKey, refreshTokenKey, tokenExpiresAt, apiKeyKey
        case lastConnectedAt, lastError, toolCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        templateID = try c.decode(String.self, forKey: .templateID)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        url = try c.decode(String.self, forKey: .url)
        authMode = try c.decodeIfPresent(MCPAuthMode.self, forKey: .authMode) ?? .selfHosted
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        clientId = try c.decodeIfPresent(String.self, forKey: .clientId)
        clientSecret = try c.decodeIfPresent(String.self, forKey: .clientSecret)
        issuer = try c.decodeIfPresent(String.self, forKey: .issuer)
        accessTokenKey = try c.decodeIfPresent(String.self, forKey: .accessTokenKey)
        refreshTokenKey = try c.decodeIfPresent(String.self, forKey: .refreshTokenKey)
        tokenExpiresAt = try c.decodeIfPresent(Date.self, forKey: .tokenExpiresAt)
        apiKeyKey = try c.decodeIfPresent(String.self, forKey: .apiKeyKey)
        lastConnectedAt = try c.decodeIfPresent(Date.self, forKey: .lastConnectedAt)
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
        toolCount = try c.decodeIfPresent(Int.self, forKey: .toolCount) ?? 0
    }
}

/// 공급자 저장소 — UserDefaults 영속화 + Keychain 시크릿 연동
@MainActor
final class MCPProviderStore: ObservableObject {
    static let shared = MCPProviderStore()

    @Published private(set) var providers: [MCPProviderConfiguration] = []

    private let defaults: UserDefaults
    private static let storageKey = "mcpProviders"
    private let keychain = KeychainService.shared

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    private func load() {
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([MCPProviderConfiguration].self, from: data) {
            providers = decoded
        } else {
            providers = []
        }
        DebugLogger.shared.info("MCP", "[FEATURE] 원격 공급자 저장소 초기화: \(providers.count)개")
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(providers) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    func upsert(_ config: MCPProviderConfiguration) {
        if let idx = providers.firstIndex(where: { $0.id == config.id }) {
            providers[idx] = config
        } else {
            providers.append(config)
        }
        persist()
    }

    func remove(_ id: UUID) {
        if let provider = providers.first(where: { $0.id == id }) {
            // 연관 시크릿 정리
            keychain.deleteSecret(forKey: provider.accessTokenKeyName())
            keychain.deleteSecret(forKey: provider.refreshTokenKeyName())
            keychain.deleteSecret(forKey: provider.clientSecretKeyName())
            keychain.deleteSecret(forKey: provider.apiKeyKeyName())
        }
        providers.removeAll { $0.id == id }
        persist()
    }

    /// OAuth 실패 시, 해당 시간에 새로 추가된 (연결 이력 없는) 공급자 제거
    /// 이미 연결된 기존 공급자면 유지
    func removePendingIfNotConnected(_ config: MCPProviderConfiguration) {
        guard let existing = providers.first(where: { $0.id == config.id }) else { return }
        // lastConnectedAt이 nil = 아직 한 번도 연결 안 된 신규 등록 → 실패 시 제거
        if existing.lastConnectedAt == nil {
            DebugLogger.shared.debug("MCP", "OAuth 실패 — 신규 공급자 '\(existing.displayName)' 목록에서 제거")
            remove(existing.id)
        } else {
            DebugLogger.shared.debug("MCP", "OAuth 실패 — 기존 연결 공급자 '\(existing.displayName)' 유지")
        }
    }

    // MARK: - 시크릿 접근

    func setAccessToken(_ token: String, for providerID: UUID) {
        guard let provider = providers.first(where: { $0.id == providerID }) else { return }
        keychain.setSecret(token, forKey: provider.accessTokenKeyName())
    }

    func accessToken(for providerID: UUID) -> String? {
        guard let provider = providers.first(where: { $0.id == providerID }) else { return nil }
        return keychain.secret(forKey: provider.accessTokenKeyName())
    }

    func setRefreshToken(_ token: String, for providerID: UUID) {
        guard let provider = providers.first(where: { $0.id == providerID }) else { return }
        keychain.setSecret(token, forKey: provider.refreshTokenKeyName())
    }

    func refreshToken(for providerID: UUID) -> String? {
        guard let provider = providers.first(where: { $0.id == providerID }) else { return nil }
        return keychain.secret(forKey: provider.refreshTokenKeyName())
    }

    func setClientSecret(_ secret: String, for providerID: UUID) {
        guard let provider = providers.first(where: { $0.id == providerID }) else { return }
        keychain.setSecret(secret, forKey: provider.clientSecretKeyName())
    }

    func clientSecret(for providerID: UUID) -> String? {
        guard let provider = providers.first(where: { $0.id == providerID }) else { return nil }
        return keychain.secret(forKey: provider.clientSecretKeyName())
    }

    func setAPIKey(_ key: String, for providerID: UUID) {
        guard let provider = providers.first(where: { $0.id == providerID }) else { return }
        keychain.setSecret(key, forKey: provider.apiKeyKeyName())
    }

    func apiKey(for providerID: UUID) -> String? {
        guard let provider = providers.first(where: { $0.id == providerID }) else { return nil }
        return keychain.secret(forKey: provider.apiKeyKeyName())
    }

    // MARK: - 토큰 만료 확인

    func isTokenExpired(_ provider: MCPProviderConfiguration) -> Bool {
        guard let expiresAt = provider.tokenExpiresAt else { return true }
        return Date() >= expiresAt.addingTimeInterval(-60) // 1분 여유
    }

    func updateTokenExpiry(_ providerID: UUID, expiresIn: TimeInterval) {
        guard let idx = providers.firstIndex(where: { $0.id == providerID }) else { return }
        providers[idx].tokenExpiresAt = Date().addingTimeInterval(expiresIn)
        persist()
    }
}