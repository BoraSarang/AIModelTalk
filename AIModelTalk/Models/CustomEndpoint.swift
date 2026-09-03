import Foundation
import SwiftUI

/// 커스텀 OpenAI 호환 엔드포인트 — v1.9 T-84 다중 지원
/// LM Studio, vLLM, OpenAI 공식 등 이름 붙은 엔드포인트를 N개 등록할 수 있다.
struct CustomEndpoint: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    /// 사용자 지정 표시 이름 (예: "LM Studio", "OpenAI")
    var name: String
    /// 예: http://localhost:1234/v1 — 클라이언트가 /chat/completions를 붙인다
    var baseURL: String = ""
    var apiKey: String = ""

    /// 엔드포인트에 속한 모델의 복합 ID — "{endpointUUID}:{rawModelID}"
    /// AIModel.id가 그대로 API 전송용이 아니라 파싱 대상이므로 팩토리에서 분해한다.
    static func compositeID(endpointID: UUID, modelID: String) -> String {
        "\(endpointID.uuidString):\(modelID)"
    }

    /// 복합 ID 분해 — 프리픽스가 유효 UUID면 (uuid, raw), 아니면 nil
    static func parse(_ composite: String) -> (endpointID: UUID, rawModelID: String)? {
        guard let idx = composite.firstIndex(of: ":") else { return nil }
        guard let uuid = UUID(uuidString: String(composite[composite.startIndex..<idx])) else { return nil }
        let raw = String(composite[composite.index(after: idx)...])
        return (uuid, raw)
    }
}

/// 커스텀 엔드포인트 저장소 — UserDefaults 주입형 (PersonaStore와 동일 패턴)
struct CustomEndpointStore {
    let defaults: UserDefaults
    private let key = "customEndpoints"

    /// 고정 스위트 도메인 인스턴스 (v3.8.1 T-1008)
    static let suiteDefaults: UserDefaults = {
        guard let suite = UserDefaults(suiteName: AppSettings.apiKeySuiteName) else {
            DebugLogger.shared.error("APP", "[E-MAC-STOR-1003] 커스텀 엔드포인트 스위트 생성 실패")
            return UserDefaults.standard
        }
        return suite
    }()

    var endpoints: [CustomEndpoint] {
        get {
            guard let data = defaults.data(forKey: key) else { return [] }
            return (try? JSONDecoder().decode([CustomEndpoint].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: key)
            }
        }
    }

    mutating func upsert(_ endpoint: CustomEndpoint) {
        var list = endpoints
        if let index = list.firstIndex(where: { $0.id == endpoint.id }) {
            list[index] = endpoint
        } else {
            list.append(endpoint)
        }
        endpoints = list
    }

    mutating func remove(id: UUID) {
        endpoints.removeAll { $0.id == id }
    }

    // MARK: - 레거시 단일 설정 마이그레이션 (v1.8 이전 customBaseURL/customAPIKey)

    static let migratedFlagKey = "customEndpointsMigrated"

    /// 기존 단일 커스텀 설정을 첫 엔드포인트로 1회 이전.
    /// 구버전 모델(프리픽스 없는 ID)은 팩토리 폴백으로 첫 엔드포인트를 사용하므로 별도 재작성 불필요.
    @discardableResult
    mutating func migrateLegacyIfNeeded() -> Bool {
        guard !defaults.bool(forKey: Self.migratedFlagKey) else { return false }
        defaults.set(true, forKey: Self.migratedFlagKey)

        var legacyURL = defaults.string(forKey: "customBaseURL") ?? ""
        let legacyKey = defaults.string(forKey: "customAPIKey") ?? ""
        while legacyURL.hasSuffix("/") { legacyURL = String(legacyURL.dropLast()) }

        guard !legacyURL.isEmpty || !legacyKey.isEmpty else { return false }
        guard endpoints.isEmpty else { return false } // 이미 사용자 데이터가 있으면 건드리지 않음

        upsert(CustomEndpoint(name: "커스텀", baseURL: legacyURL, apiKey: legacyKey))
        DebugLogger.shared.info("APP", "[FEATURE] 레거시 커스텀 설정 마이그레이션 실행됨: URL \(legacyURL.isEmpty ? "없음" : "있음")")
        return true
    }

    // MARK: - .standard → 고정 스위트 이전 (v3.8.1 T-1008)

    /// .standard에 저장된 커스텀 엔드포인트 배열을 고정 스위트로 1회 이전.
    /// 스위트에 데이터가 없거나 빈 배열이고, .standard에 데이터가 있으면 복사.
    @discardableResult
    static func migrateToSuiteIfNeeded() -> Bool {
        let standard = UserDefaults.standard
        let suite = suiteDefaults
        let flagKey = "customEndpointsMigratedToSuite"

        guard !suite.bool(forKey: flagKey) else { return false }

        guard let data = standard.data(forKey: "customEndpoints"),
              let endpoints = try? JSONDecoder().decode([CustomEndpoint].self, from: data),
              !endpoints.isEmpty else { return false }

        suite.set(data, forKey: "customEndpoints")
        suite.set(true, forKey: flagKey)
        suite.synchronize()
        DebugLogger.shared.info("APP", "[FEATURE] 커스텀 엔드포인트 \(endpoints.count)개 고정 스위트로 이전")
        return true
    }
}

extension CustomEndpoint {
    /// /models 조회로 연결 검증 — 결과 문자열 반환 ("✓ ..." / "✗ ...")
    /// 설정 행·에디터 양쪽에서 공용 사용. 키 값은 절대 로그에 남기지 않는다.
    static func testConnection(_ endpoint: CustomEndpoint) async -> String {
        var base = endpoint.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            DebugLogger.shared.warn("API-CUSTOM", "'\(endpoint.name)' Base URL 미입력 상태로 테스트 시도")
            return "✗ Base URL 미입력"
        }
        if !base.hasPrefix("http://") && !base.hasPrefix("https://") {
            let isLocal = base.hasPrefix("localhost") || base.hasPrefix("127.0.0.1")
            base = (isLocal ? "http://" : "https://") + base
        }
        while base.hasSuffix("/") { base = String(base.dropLast()) }

        guard let url = URL(string: base + "/models") else {
            DebugLogger.shared.error("API-CUSTOM", "[E-MAC-VALID-1003] '\(endpoint.name)' URL 형식 오류: \(base)")
            return "✗ URL 형식 오류"
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        if !endpoint.apiKey.isEmpty {
            req.setValue("Bearer \(endpoint.apiKey)", forHTTPHeaderField: "Authorization")
        }

        DebugLogger.shared.info(
            "API-CUSTOM",
            "'\(endpoint.name)' 연결 테스트 시작: GET \(base)/models (키 \(endpoint.apiKey.isEmpty ? "없음" : "있음, 길이 \(endpoint.apiKey.count)"))"
        )
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                DebugLogger.shared.error("API-CUSTOM", "[E-MAC-NET-1001] '\(endpoint.name)' 응답 없음 (HTTP 아님)")
                return "✗ 응답 없음"
            }
            if (200..<300).contains(http.statusCode) {
                let count = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                    .flatMap { $0["data"] as? [[String: Any]] }?.count ?? 0
                DebugLogger.shared.info("API-CUSTOM", "'\(endpoint.name)' 연결 성공: HTTP \(http.statusCode), 모델 \(count)개")
                return "✓ 연결 성공 (모델 \(count)개)"
            }
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            let hint = http.statusCode == 401 ? " — API 키 확인 필요"
                : (http.statusCode == 404 ? " — /v1 경로 포함 여부 확인" : "")
            DebugLogger.shared.error("API-CUSTOM", "[E-MAC-API-1001] '\(endpoint.name)' HTTP \(http.statusCode): \(bodyText.prefix(300))")
            return "✗ HTTP \(http.statusCode)\(hint)"
        } catch {
            DebugLogger.shared.error("API-CUSTOM", "[E-MAC-NET-1001] '\(endpoint.name)' 연결 실패: \(error.localizedDescription)")
            return "✗ 연결 실패"
        }
    }
}
