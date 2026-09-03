import Foundation

/// 뷰 계층의 공급자 목록 항목 — 내장 공급자 + 커스텀 엔드포인트별 항목 (v1.9 T-85)
/// Provider enum은 세션 영속 호환을 위해 건드리지 않고, 표시·선택·필터링만 추상화한다.
struct ProviderEntry: Identifiable, Hashable {
    let id: String              // provider.rawValue 또는 "custom:{endpointUUID}"
    let title: String           // 공급자명 또는 endpoint.name
    let provider: Provider      // 기반 공급자 (엔드포인트는 .custom)
    let endpoint: CustomEndpoint?   // nil이면 내장 공급자
    /// 행 점 색상 hex — 내장은 공급자 색, 엔드포인트는 회색 통일 (사용자 확정)
    let colorHex: String

    init(provider: Provider) {
        self.id = provider.rawValue
        self.title = provider.rawValue
        self.provider = provider
        self.endpoint = nil
        self.colorHex = provider.accentColor
    }

    init(endpoint: CustomEndpoint) {
        self.id = "custom:\(endpoint.id.uuidString)"
        self.title = endpoint.name
        self.provider = .custom
        self.endpoint = endpoint
        self.colorHex = "#8E8E93"
    }

    /// 사이드바·피커용 전체 목록 — 내장 6종(.custom 제외) + 등록된 엔드포인트 N개
    static func currentList(endpoints: [CustomEndpoint]) -> [ProviderEntry] {
        var list = Provider.allCases.filter { $0 != .custom }.map { ProviderEntry(provider: $0) }
        list += endpoints.map { ProviderEntry(endpoint: $0) }
        return list
    }

    static func currentList() -> [ProviderEntry] {
        currentList(endpoints: CustomEndpointStore(defaults: CustomEndpointStore.suiteDefaults).endpoints)
    }
}

extension AIModel {
    /// 커스텀 모델의 소속 엔드포인트 ID — 복합 ID "{uuid}:{raw}" 파싱, 비커스텀은 nil
    var customEndpointID: UUID? {
        guard provider == .custom else { return nil }
        return CustomEndpoint.parse(id)?.endpointID
    }

    /// 엔트리 소속 여부.
    /// 프리픽스 없는 구형 커스텀 모델은 첫 엔드포인트에 폴백 배정된다 (세션 호환 유지).
    /// 폴백 대상이 없으면(nil) 구형 모델은 어디에도 속하지 않는다.
    func belongs(to entry: ProviderEntry, fallbackFirstEndpointID: UUID?) -> Bool {
        guard provider == .custom else {
            return entry.endpoint == nil && entry.provider == provider
        }
        if let eid = customEndpointID {
            return entry.endpoint?.id == eid
        }
        guard let fallback = fallbackFirstEndpointID else { return false }
        return entry.endpoint?.id == fallback
    }
}
