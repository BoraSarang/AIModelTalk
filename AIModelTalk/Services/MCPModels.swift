import Foundation

/// 전송 계층 종류 (v2.4 T-122) — stdio 로컬 프로세스 / Streamable HTTP 원격
enum MCPTransportKind: String, Codable, Hashable {
    case stdio
    case http
}

/// MCP 서버 등록 설정 (v2.4 T-119)
/// 시크릿 env 값은 Keychain에 저장 — 여기엔 키 이름만 보관
struct MCPServerConfig: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var command: String
    var args: [String] = []
    /// 시크릿 환경변수 키 목록 (값은 Keychain: "mcp.<serverID>.<key>")
    var secretEnvKeys: [String] = []
    /// 비시크릿 환경변수
    var plainEnv: [String: String] = [:]
    var isEnabled: Bool = true
    /// 전송 계층 (v2.4 T-122) — stdio 로컬 프로세스 / Streamable HTTP 원격
    var transport: MCPTransportKind = .stdio
    /// HTTP 엔드포인트 — 예: https://example.com/mcp (transport == .http일 때만 사용)
    var url: String = ""
    /// HTTP 인증 헤더명 — 기본 Authorization (Bearer 접두어 자동 부착)
    var authHeaderName: String = "Authorization"

    func keychainKey(for envKey: String) -> String {
        "mcp.\(id.uuidString).\(envKey)"
    }

    /// HTTP 인증 토큰 Keychain 키 — env 시크릿과 동일 메커니즘 재사용
    static let authTokenEnvKey = "AUTH_TOKEN"

    func authToken(secrets: SecretStore = KeychainService.shared) -> String? {
        secrets.secret(forKey: keychainKey(for: Self.authTokenEnvKey))
    }

    /// 실행 환경변수 조립 — plain + Keychain 시크릿 병합
    func resolvedEnv(secrets: SecretStore = KeychainService.shared) -> [String: String] {
        var env = plainEnv
        for key in secretEnvKeys {
            if let value = secrets.secret(forKey: keychainKey(for: key)) {
                env[key] = value
            } else {
                DebugLogger.shared.warn("MCP", "[\(name)] 시크릿 '\(key)' 미설정 — Keychain 확인 필요")
            }
        }
        return env
    }

    // MARK: - 구버전 호환 코딩 — 새 필드는 decodeIfPresent, 구저장 JSON도 안전 디코드 (v2.4 T-122)

    private enum CodingKeys: String, CodingKey {
        case id, name, command, args, secretEnvKeys, plainEnv, isEnabled
        case transport, url, authHeaderName
    }

    init(id: UUID = UUID(),
         name: String,
         command: String = "",
         args: [String] = [],
         secretEnvKeys: [String] = [],
         plainEnv: [String: String] = [:],
         isEnabled: Bool = true,
         transport: MCPTransportKind = .stdio,
         url: String = "",
         authHeaderName: String = "Authorization") {
        self.id = id
        self.name = name
        self.command = command
        self.args = args
        self.secretEnvKeys = secretEnvKeys
        self.plainEnv = plainEnv
        self.isEnabled = isEnabled
        self.transport = transport
        self.url = url
        self.authHeaderName = authHeaderName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        command = try c.decodeIfPresent(String.self, forKey: .command) ?? ""
        args = try c.decodeIfPresent([String].self, forKey: .args) ?? []
        secretEnvKeys = try c.decodeIfPresent([String].self, forKey: .secretEnvKeys) ?? []
        plainEnv = try c.decodeIfPresent([String: String].self, forKey: .plainEnv) ?? [:]
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        transport = try c.decodeIfPresent(MCPTransportKind.self, forKey: .transport) ?? .stdio
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        authHeaderName = try c.decodeIfPresent(String.self, forKey: .authHeaderName) ?? "Authorization"
    }
}

/// 전송 계층 공용 인터페이스 — stdio(MCPConnection)·http(MCPHTTPConnection)를 동일하게 취급 (v2.4 T-122)
@MainActor
protocol MCPTransportConnection: AnyObject {
    var state: MCPConnection.State { get }
    var tools: [MCPTool] { get }
    func connect() async
    func disconnect()
    func restart() async
    func callTool(name: String, arguments: [String: Any]) async throws -> String
}

extension MCPConnection: MCPTransportConnection {}
extension MCPHTTPConnection: MCPTransportConnection {}

/// 설정에 맞는 연결 객체 생성
@MainActor
enum MCPConnectionFactory {
    static func make(config: MCPServerConfig) -> any MCPTransportConnection {
        if config.transport == .http {
            return MCPHTTPConnection(config: config)
        }
        return MCPConnection(config: config)
    }
}

/// MCP 도구 — tools/list 결과 항목
struct MCPTool: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let description: String
    /// JSON Schema 원본 문자열 — LLM tool 정의 전달용
    let inputSchemaJSON: String
}

/// 서버 등록소 — UserDefaults에 JSON 배열로 영속화 (시크릿 제외) (v2.4 T-119)
@MainActor
final class MCPServerStore: ObservableObject {
    static let shared = MCPServerStore()

    @Published private(set) var servers: [MCPServerConfig]
    private let defaults: UserDefaults
    private static let storageKey = "mcpServers"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([MCPServerConfig].self, from: data) {
            servers = decoded
        } else {
            servers = []
        }
        DebugLogger.shared.info("MCP", "[FEATURE] 서버 등록소 초기화: \(servers.count)개")
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(servers) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    func upsert(_ config: MCPServerConfig) {
        if let idx = servers.firstIndex(where: { $0.id == config.id }) {
            servers[idx] = config
        } else {
            servers.append(config)
        }
        persist()
    }

    func remove(_ id: UUID) {
        // 연관 시크릿도 함께 삭제
        if let server = servers.first(where: { $0.id == id }) {
            let keychain = KeychainService.shared
            for key in server.secretEnvKeys {
                keychain.deleteSecret(forKey: server.keychainKey(for: key))
            }
        }
        servers.removeAll { $0.id == id }
        persist()
    }

    /// 시크릿 값 저장 — 편집 화면에서 사용
    func setSecret(serverID: UUID, envKey: String, value: String) {
        let key = "mcp.\(serverID.uuidString).\(envKey)"
        KeychainService.shared.setSecret(value, forKey: key)
    }

    func secret(serverID: UUID, envKey: String) -> String? {
        KeychainService.shared.secret(forKey: "mcp.\(serverID.uuidString).\(envKey)")
    }
}
