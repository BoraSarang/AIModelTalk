import Foundation

/// 도구별 권한 정책 (v2.4 T-120) — 기본 매번 확인
enum ToolPermissionPolicy: String, Codable, CaseIterable {
    case ask            // 매번 물어보기
    case alwaysAllow    // 항상 허용
    case deny           // 항상 거부
}

/// 도구 권한 저장소 — UserDefaults 영속화 (v2.4 T-120)
@MainActor
final class MCPPermissionStore: ObservableObject {
    static let shared = MCPPermissionStore()

    /// key = 도구 이름 (도구 이름은 서버 간 충돌 드묾 — 충돌 시 마지막 등록이 이김)
    @Published private(set) var policies: [String: ToolPermissionPolicy]
    private let defaults: UserDefaults
    private static let storageKey = "mcpToolPolicies"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: ToolPermissionPolicy].self, from: data) {
            policies = decoded
        } else {
            policies = [:]
        }
    }

    func policy(forTool name: String) -> ToolPermissionPolicy {
        policies[name] ?? .ask
    }

    func setPolicy(_ policy: ToolPermissionPolicy, forTool name: String) {
        policies[name] = policy
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(policies) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
