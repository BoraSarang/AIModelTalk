import Foundation

// MARK: - 갱신 리포트 (v1.7.1 T-58)

struct ProviderRefreshResult {
    enum Status { case ok, failed, skipped }

    let provider: Provider
    let status: Status
    var addedCount = 0
    var removedCount = 0
    /// 실패 사유 (status == .failed일 때 사용자 노출용) — 공급자 갱신 리포트 상세화
    var errorMessage: String? = nil
}

struct CatalogRefreshReport {
    let results: [ProviderRefreshResult]

    var addedTotal: Int { results.reduce(0) { $0 + $1.addedCount } }
    var removedTotal: Int { results.reduce(0) { $0 + $1.removedCount } }
    var failedProviderNames: [String] {
        results.filter { $0.status == .failed }.map { $0.provider.rawValue }
    }

    /// 모델 목록 조회 HTTP 상태코드 → 사람이 읽을 실패 사유.
    /// 목록 조회 실패는 호출 방식/URL/인증 문제로, 개별 모델 자동 비활성화와 무관하다.
    static func refreshFailureReason(_ code: Int) -> String {
        switch code {
        case 401, 403: return "인증 실패 (API 키 확인)"
        case 404: return "목록 엔드포인트 404 — URL/방식 오류 확인"
        case 429: return "요청 한도/속도 초과"
        case 500...599: return "공급자 서버 오류 (HTTP \(code))"
        default: return "공급자 오류 (HTTP \(code))"
        }
    }

    /// 사용자 노출용 요약 문구 — 설정 하단 버튼 바에 표시
    static func summaryText(_ results: [ProviderRefreshResult]) -> String {
        guard !results.isEmpty, !results.allSatisfy({ $0.status == .skipped }) else {
            return "API 키가 설정된 공급자가 없습니다"
        }
        let added = results.reduce(0) { $0 + $1.addedCount }
        let removed = results.reduce(0) { $0 + $1.removedCount }
        let okProviders = results.filter { $0.status == .ok }.map(\.provider.rawValue)
        let failed = results.filter { $0.status == .failed }

        if added == 0 && removed == 0 && failed.isEmpty && !okProviders.isEmpty {
            return "변경 없음 (\(okProviders.joined(separator: ", ")))"
        }

        var parts: [String] = []
        if added > 0 || removed > 0 {
            var countPart = ""
            if added > 0 { countPart += "추가 \(added)개" }
            if removed > 0 { countPart += (countPart.isEmpty ? "" : ", ") + "제거 \(removed)개" }
            parts.append(countPart + (okProviders.isEmpty ? "" : " (\(okProviders.joined(separator: ", ")))"))
        } else if !okProviders.isEmpty {
            parts.append("성공: \(okProviders.joined(separator: ", "))")
        }
        if !failed.isEmpty {
            let detail = failed.map { r -> String in
                let reason = r.errorMessage.flatMap { " (\($0))" } ?? ""
                return "\(r.provider.rawValue)\(reason)"
            }
            parts.append("실패: \(detail.joined(separator: " · "))")
        }
        return parts.joined(separator: " / ")
    }
}

@MainActor
final class ModelCatalog: ObservableObject {
    static let shared = ModelCatalog()

    @Published var models: [AIModel] = [] {
        didSet {
            // refresh() 배치 중엔 연쇄 재구축을 피하고 마지막에 1회 확정 (v0.2.2)
            guard !isBatchUpdating else { return }
            rebuildIndexes()
        }
    }

    /// 모델 사용 플래그 ("공급자:id" → 사용 여부). 미등록 키는 기본 해제 — Apple Intelligence만 예외 (v0.2.2)
    @Published var enabledOverrides: [String: Bool] = [:]
    /// refresh() 중 models 변이를 배치로 모으기 위한 플래그 — true 동안 rebuildIndexes/saveCustomModels를 지연
    private var isBatchUpdating = false

    private let userDefaultsKey = "customModels"
    private let overridesKey = "modelEnabledOverrides"
    /// 410/404 자동 정리로 비활성화된 모델 키(공급자:id) — 수동 해제와 구분해 별도 영구 저장 (v0.2.0)
    private let autoDisabledKey = "autoDisabledModelKeys"
    /// 갱신으로 받아온 모델 ID 스냅샷(공급자별) — 원격에서 사라진 모델 제거 감지용 (v1.7.1 D2)
    private let refreshedIDsKey = "refreshedModelIDs"
    private var refreshedIDs: [String: [String]] = [:]
    private let defaults: UserDefaults

    /// 자동 정리(410/404)로 비활성화된 모델 키 집합 — 수동 해제와 구분되어 갱신 로그/UI에 노출
    @Published private(set) var autoDisabledKeys: Set<String> = []

    // MARK: - 정적 기본 목록 (무료 전용)
    static let defaultModels: [AIModel] = [
        // NVIDIA
        AIModel(id: "openai/gpt-oss-20b", provider: .nvidia, displayName: "GPT-OSS-20B", contextLimit: 131_072),
        AIModel(id: "nvidia/llama-3.3-nemotron-super-49b-v1.5", provider: .nvidia, displayName: "Nemotron Super 49B", contextLimit: 131_072),
        AIModel(id: "nvidia/llama-3.1-8b-instruct", provider: .nvidia, displayName: "Llama 3.1 8B", contextLimit: 131_072),
        // OpenRouter (":free" suffix)
        AIModel(id: "google/gemini-2.5-flash-preview:free", provider: .openRouter, displayName: "Gemini 2.5 Flash", contextLimit: 1_048_576),
        AIModel(id: "deepseek/deepseek-chat-v3-0324:free", provider: .openRouter, displayName: "DeepSeek V3", contextLimit: 128_000),
        AIModel(id: "meta-llama/llama-4-maverick:free", provider: .openRouter, displayName: "Llama 4 Maverick", contextLimit: 1_048_576),
        AIModel(id: "qwen/qwen3-235b-a22b:free", provider: .openRouter, displayName: "Qwen3 235B", contextLimit: 128_000),
        // Groq
        AIModel(id: "llama-3.3-70b-versatile", provider: .groq, displayName: "Llama 3.3 70B", contextLimit: 131_072),
        AIModel(id: "gemma2-9b-it", provider: .groq, displayName: "Gemma 2 9B", contextLimit: 8_192),
        AIModel(id: "mixtral-8x7b-32768", provider: .groq, displayName: "Mixtral 8x7B", contextLimit: 32_768),
        // Gemini (2026-08 기준 GA 안정판 — 구모델은 신규 계정에서 404)
        AIModel(id: "gemini-3.6-flash", provider: .gemini, displayName: "Gemini 3.6 Flash", contextLimit: 1_048_576),
        AIModel(id: "gemini-3.5-flash-lite", provider: .gemini, displayName: "Gemini 3.5 Flash-Lite", contextLimit: 1_048_576),
        // OpenAI / Anthropic (유료 — API 키 보유자용 대표 모델, v2.1 T-93 무료전용 정책 폐기)
        AIModel(id: "gpt-4o-mini", provider: .openAI, displayName: "GPT-4o mini", isFree: false, contextLimit: 128_000),
        AIModel(id: "gpt-4o", provider: .openAI, displayName: "GPT-4o", isFree: false, contextLimit: 128_000),
        AIModel(id: "claude-haiku-4-5", provider: .anthropic, displayName: "Claude Haiku 4.5", isFree: false, contextLimit: 200_000),
        AIModel(id: "claude-sonnet-4-5", provider: .anthropic, displayName: "Claude Sonnet 4.5", isFree: false, contextLimit: 200_000),
        // OpenCode Zen (게이트웨이, OpenAI 호환 chat/completions — 무료 먼저, 유료는 isFree: false)
        AIModel(id: "opencode/big-pickle", provider: .opencode, displayName: "Big Pickle (무료)", contextLimit: 128_000),
        AIModel(id: "opencode/nemotron-3-ultra-free", provider: .opencode, displayName: "Nemotron 3 Ultra (무료)", contextLimit: 128_000),
        AIModel(id: "opencode/mimo-v2.5-free", provider: .opencode, displayName: "MiMo V2.5 (무료)", contextLimit: 128_000),
        AIModel(id: "opencode/deepseek-v4-flash", provider: .opencode, displayName: "DeepSeek V4 Flash", isFree: false, contextLimit: 128_000),
        AIModel(id: "opencode/deepseek-v4-pro", provider: .opencode, displayName: "DeepSeek V4 Pro", isFree: false, contextLimit: 128_000),
        // DeepSeek (공식 API — 유료)
        AIModel(id: "deepseek-chat", provider: .deepseek, displayName: "DeepSeek Chat", isFree: false, contextLimit: 128_000),
        AIModel(id: "deepseek-reasoner", provider: .deepseek, displayName: "DeepSeek Reasoner", isFree: false, contextLimit: 64_000),
        // Ollama (로컬 무료 모델 — 대표 모델만 정적 등록, 실제 목록은 /api/tags에서 동기화)
        AIModel(id: "llama3.2:latest", provider: .ollama, displayName: "Llama 3.2", contextLimit: 128_000),
        AIModel(id: "gemma2:2b", provider: .ollama, displayName: "Gemma 2 2B", contextLimit: 8_192),
        AIModel(id: "qwen2.5:7b", provider: .ollama, displayName: "Qwen 2.5 7B", contextLimit: 128_000),
        AIModel(id: "phi3.5:latest", provider: .ollama, displayName: "Phi 3.5", contextLimit: 128_000),
        // Apple Intelligence (온디바이스 무료 — macOS 26+ FoundationModels. 미지원 환경은 UI에서 섹션 자동 숨김, v2.1 T-102)
        // 컨텍스트 상한 비공개 — 보수값 사용. 실제 응답은 AppleIntelligenceClient가 세션으로 처리
        AIModel(id: "apple-intelligence", provider: .appleIntelligence, displayName: "Apple Intelligence", contextLimit: 8_192),
    ]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 로딩 전체를 배치로 묶는다 — 커스텀 모델 수백 개를 개별 append할 때마다
        // rebuildIndexes()(UserDefaults JSON + 전체 모델 순회)가 O(N²)로 폭주하는 것을 방지. (v0.2.3)
        isBatchUpdating = true
        models = Self.defaultModels
        loadCustomModels()
        loadEnabledOverrides()
        autoDisabledKeys = Set((defaults.array(forKey: autoDisabledKey) as? [String]) ?? [])
        isBatchUpdating = false
        rebuildIndexes() // 배치 종료 후 로드된 전체 models 기준 소속 인덱스 1회 확정 (enabled는 조회 시점에 반영)
    }

    // MARK: - 모델 추가/삭제
    func addModel(_ model: AIModel) {
        guard !models.contains(where: { $0.id == model.id && $0.provider == model.provider }) else { return }
        models.append(model)
        saveCustomModels()
        DebugLogger.shared.info("MODEL", "모델 추가: \(model.id) (\(model.provider.rawValue))")
    }

    func removeModel(_ model: AIModel) {
        models.removeAll { $0.id == model.id && $0.provider == model.provider }
        saveCustomModels()
        DebugLogger.shared.info("MODEL", "모델 삭제: \(model.id) (\(model.provider.rawValue))")
    }

    func removeModels(for provider: Provider) {
        models.removeAll { $0.provider == provider }
        saveCustomModels()
        DebugLogger.shared.info("MODEL", "공급자 모델 전체 삭제: \(provider.rawValue)")
    }

    // MARK: - 엔트리 단위 조회 (v1.9 T-85 — 내장 공급자 + 커스텀 엔드포인트)

    // ── 성능 인덱스 캐시 (v0.2.1) ──
    // 모델이 수백~천여 개일 때 엔트리 필터를 매 body 평가마다 O(n)으로 반복 재계산하면
    // 피커·설정 목록이 멈추는 원인이 된다. 아래 사전으로 미리 인덱싱해 O(1) 조회로 전환한다.
    // rebuildIndexes()는 models가 바뀌는 지점에서 호출한다 (enabled는 조회 시점에 isEnabled로 반영).

    /// 엔트리 id → (belongs) 소속 모델 (fallback 결합 제외, 고정 소속만)
    private var modelsByEntryID: [String: [AIModel]] = [:]
    /// 엔트리 id → 활성화(enabled) 모델만 — 화면이 활성 목록만 읽도록 미리 인덱싱 (v0.2.3)
    /// 조회 시점에 models 전체를 filter(isEnabled)로 순회하지 않고 상수 시간에 활성만 반환한다.
    private var enabledByEntryID: [String: [AIModel]] = [:]
    /// 엔드포인트 미지정 구형 커스텀 모델 — 첫 엔드포인트(fallback)에 소속되는 그룹 (T-85 구형 호환)
    private var legacyCustomModels: [AIModel] = []
    /// 구형 커스텀 중 활성화 모델만 — enabledByEntryID와 동일하게 미리 필터 (v0.2.3)
    private var enabledLegacyCustomModels: [AIModel] = []
    /// rebuild 시점에 저장소에 존재하는 엔드포인트 ID 집합 — indexed() O(1) 판별용
    private var indexedEndpointIDs: Set<UUID> = []

    /// 내부 인덱스 재구축 — models 변경 시에만 호출 (enabled는 소속 분류와 무관, 조회 시점에 반영)
    private func rebuildIndexes() {
        var byEntry: [String: [AIModel]] = [:]
        var enabledByEntry: [String: [AIModel]] = [:]
        var legacy: [AIModel] = []
        var enabledLegacy: [AIModel] = []

        // 내장 공급자(비커스텀) + 커스텀 엔드포인트에 정확 소속되는 모델을 키별로 분류
        var endpointIDs: Set<UUID> = []
        let snapshot = allEntriesSnapshot()
        for entry in snapshot {
            if let eid = entry.endpoint?.id { endpointIDs.insert(eid) }
            var list: [AIModel] = []
            for model in models where model.belongs(to: entry, fallbackFirstEndpointID: nil) {
                list.append(model)
            }
            byEntry[entry.id] = list
            enabledByEntry[entry.id] = list.filter { isEnabled($0) }
        }
        // 엔드포인트 미지정 구형 커스텀 모델 — 소속이 어디에도 없던 .custom
        for model in models where model.provider == .custom && model.customEndpointID == nil {
            legacy.append(model)
            if isEnabled(model) { enabledLegacy.append(model) }
        }

        modelsByEntryID = byEntry
        enabledByEntryID = enabledByEntry
        legacyCustomModels = legacy
        enabledLegacyCustomModels = enabledLegacy
        indexedEndpointIDs = endpointIDs
    }

    /// 활성(enabled) 토글 변경 시 활성 인덱스만 재구성 — 모델 소속(modelsByEntryID)은 변하지 않으므로
    /// 전체 rebuildIndexes를 돌리지 않아도 된다 (v0.2.3). 조회 시점의 models 전체 순회를 제거한다.
    private func rebuildEnabledIndexes() {
        var enabledByEntry: [String: [AIModel]] = [:]
        for (key, list) in modelsByEntryID {
            enabledByEntry[key] = list.filter { isEnabled($0) }
        }
        enabledByEntryID = enabledByEntry
        enabledLegacyCustomModels = legacyCustomModels.filter { isEnabled($0) }
    }

    /// 단일 모델 토글 시 활성 인덱스 증분 갱신 — 전체를 순회하지 않고 그 모델이 속한 엔트리만
    /// 재구성한다 (v0.2.3). modelsByEntryID의 키(=엔트리 id) 기준으로 모델 소속을 찾는다.
    private func rebuildEnabledIndexes(for model: AIModel) {
        var touched = false
        for (key, list) in modelsByEntryID {
            guard let _ = list.first(where: { $0.id == model.id && $0.provider == model.provider }) else { continue }
            enabledByEntryID[key] = list.filter { isEnabled($0) }
            touched = true
        }
        // 구형 커스텀(엔드포인트 미지정) 모델이라면 legacy 인덱스도 갱신
        if model.provider == .custom && legacyCustomModels.contains(where: { $0.id == model.id }) {
            enabledLegacyCustomModels = legacyCustomModels.filter { isEnabled($0) }
            touched = true
        }
        // 보수적 폴백 — 소속을 못 찾았거나 배치 상태면 전체 재구성
        if !touched { rebuildEnabledIndexes() }
    }

    // 현재 엔트리 목록 — 이 카탈로그의 defaults(테스트 격리 suite 포함)에서 엔드포인트를 읽는다
    private func allEntriesSnapshot() -> [ProviderEntry] {
        Provider.allCases.filter { $0 != .custom }.map { ProviderEntry(provider: $0) }
            + CustomEndpointStore(defaults: defaults).endpoints
                .map { ProviderEntry(endpoint: $0) }
    }

    /// 엔트리(내장 공급자 또는 커스텀 엔드포인트)에 속한 모델 목록
    func models(in entry: ProviderEntry, fallbackFirstEndpointID: UUID? = nil) -> [AIModel] {
        // 저장된 엔드포인트라면 인덱스 O(1) 조회, 저장되지 않은(테스트 주입 등) 엔드포인트는 기존 필터 폴백
        guard indexed(entry) else {
            return models.filter { $0.belongs(to: entry, fallbackFirstEndpointID: fallbackFirstEndpointID) }
        }
        var result = modelsByEntryID[entry.id] ?? []
        if isFallbackCapture(entry, fallbackFirstEndpointID: fallbackFirstEndpointID) {
            result += legacyCustomModels
        }
        return result
    }

    func visibleModels(in entry: ProviderEntry, fallbackFirstEndpointID: UUID? = nil) -> [AIModel] {
        guard indexed(entry) else {
            return models.filter { $0.belongs(to: entry, fallbackFirstEndpointID: fallbackFirstEndpointID) && isEnabled($0) }
        }
        // 활성 모델 인덱스 O(1) — 전체를 순회하지 않고 이미 활성화된 모델만 반환 (v0.2.3)
        var result = enabledByEntryID[entry.id] ?? []
        if isFallbackCapture(entry, fallbackFirstEndpointID: fallbackFirstEndpointID) {
            result += enabledLegacyCustomModels
        }
        return result
    }

    /// 엔트리의 전체 모델 수 — 배열을 만들지 않고 인덱스 크기로 O(1) 반환 (v0.2.3)
    /// Picker 라벨 등 카운트만 필요한 곳에서 models(in:)로 전체를 조립하지 않도록 한다.
    func totalModelCount(in entry: ProviderEntry, fallbackFirstEndpointID: UUID? = nil) -> Int {
        guard indexed(entry) else {
            return models.reduce(0) { $0 + ($1.belongs(to: entry, fallbackFirstEndpointID: fallbackFirstEndpointID) ? 1 : 0) }
        }
        var count = modelsByEntryID[entry.id]?.count ?? 0
        if isFallbackCapture(entry, fallbackFirstEndpointID: fallbackFirstEndpointID) {
            count += legacyCustomModels.count
        }
        return count
    }

    /// 엔트리의 엔드포인트가 현재 저장소에 있어 인덱스가 해당 키를 보유하는지 여부
    private func indexed(_ entry: ProviderEntry) -> Bool {
        if let eid = entry.endpoint?.id { return indexedEndpointIDs.contains(eid) }
        return true // 내장 공급자
    }

    /// 구형 커스텀(엔드포인트 미지정) 모델이 이 조회에 흡수되는지 — 첫 엔드포인트로 폴백 배정될 때만
    private func isFallbackCapture(_ entry: ProviderEntry, fallbackFirstEndpointID: UUID?) -> Bool {
        guard entry.endpoint != nil, let fallback = fallbackFirstEndpointID,
              !legacyCustomModels.isEmpty else { return false }
        return entry.endpoint?.id == fallback
    }

    /// 엔트리 단위 일괄 토글 — "모두 사용/해제" 버튼용
    func setAllEnabled(_ enabled: Bool, in entry: ProviderEntry, fallbackFirstEndpointID: UUID? = nil) {
        let targets = models.filter { $0.belongs(to: entry, fallbackFirstEndpointID: fallbackFirstEndpointID) }
        var updated = enabledOverrides
        for model in targets {
            updated[overrideKey(model)] = enabled
        }
        enabledOverrides = updated
        defaults.set(enabledOverrides, forKey: overridesKey)
        rebuildEnabledIndexes() // 활성 인덱스 갱신 (v0.2.3)
        DebugLogger.shared.info("MODEL", "\(entry.title) 모델 전체 \(enabled ? "사용" : "해제"): \(targets.count)개")
    }

    // MARK: - 모델 사용 플래그 (v1.7 T-53)

    func isEnabled(_ model: AIModel) -> Bool {
        // Apple Intelligence는 시스템 모델이 실제 가용할 때만 사용 가능 (T-209)
        if !Self.appleAvailable(model: model, modelAvailable: AppleIntelligenceSupport.modelAvailable) {
            return false
        }
        // 기본값 해제 (v0.2.2): 명시되지 않은 모델은 사용 안 함. Apple Intelligence(온디바이스)만 기본 사용.
        if let override = enabledOverrides[overrideKey(model)] { return override }
        return model.provider == Provider.appleIntelligence
    }

    /// Apple Intelligence 가용 여부 — 테스트 가능하도록 주입 파라미터 (T-209)
    nonisolated static func appleAvailable(model: AIModel, modelAvailable: Bool) -> Bool {
        if model.provider == .appleIntelligence { return modelAvailable }
        return true
    }

    func setEnabled(_ model: AIModel, _ enabled: Bool) {
        let key = overrideKey(model)
        enabledOverrides[key] = enabled
        defaults.set(enabledOverrides, forKey: overridesKey)
        // 재활성화 시 자동 제외(410/404) 기록 해제 — 사용자가 다시 켠 모델은 정리 상태에서 빼줌
        if enabled, autoDisabledKeys.contains(key) {
            autoDisabledKeys.remove(key)
            defaults.set(Array(autoDisabledKeys), forKey: autoDisabledKey)
        }
        rebuildEnabledIndexes(for: model) // 토글 모델이 속한 엔트리만 활성 인덱스 갱신 (v0.2.3)
        DebugLogger.shared.info("MODEL", "모델 사용 \(enabled ? "ON" : "OFF"): \(model.id)")
    }

    /// 모델 EOL(410)/모델 없음(404) 응답 시 해당 모델을 자동 비활성화.
    /// - 410(Gone)은 항상 모델 문제 → 무조건 비활성화
    /// - 404(NotFound)는 호출부(채팅/비교/판정)에서만 모델 문제로 간주해 비활성화.
    ///   모델 목록 조회(방식/URL 오류)에서의 404는 처리하지 않는다 — 호출부가 아닌 곳에선 호출하지 않도록.
    /// UserDefaults(enabledOverrides) 영구 저장 → 원격 목록이 재추가돼도 visibleModels에서 숨김 유지.
    @discardableResult
    func disableUnavailableModel(error: Error, model: AIModel) -> Bool {
        guard let appError = error as? AppError else { return false }
        guard appError.isGone || appError.isModelNotFound else { return false }
        guard isEnabled(model) else { return false }
        setEnabled(model, false)
        recordAutoDisabled(model)
        let reason = appError.isGone ? "EOL(410)" : "모델 없음(404)"
        DebugLogger.shared.info("MODEL", "[FEATURE] \(reason) 응답 — 모델 자동 비활성화: \(model.provider.rawValue)/\(model.id)")
        return true
    }

    /// 자동 정리(410/404)로 제외된 모델 키를 별도 기록 — 수동 해제와 구분해 갱신 로그/UI에 노출.
    private func recordAutoDisabled(_ model: AIModel) {
        let key = overrideKey(model)
        guard !autoDisabledKeys.contains(key) else { return }
        autoDisabledKeys.insert(key)
        defaults.set(Array(autoDisabledKeys), forKey: autoDisabledKey)
    }

    /// 자동 정리된 모델 수 — 갱신 로그·설정 하단 리포트에 표시 (v0.2.0)
    var autoDisabledCount: Int { autoDisabledKeys.count }

    /// 피커 노출용 — 비활성 모델은 목록에서 완전 숨김 (v1.7 D4)
    func visibleModels(for provider: Provider) -> [AIModel] {
        // 활성 모델 인덱스 O(1) — 전체 순회 없이 활성만 반환 (v0.2.3)
        enabledByEntryID[provider.rawValue] ?? []
    }

    /// 공급자 전체 모델 일괄 토글 (v1.7.1 T-61)
    func setAllEnabled(_ enabled: Bool, for provider: Provider) {
        let targets = models.filter { $0.provider == provider }
        var updated = enabledOverrides
        for model in targets {
            updated[overrideKey(model)] = enabled
        }
        enabledOverrides = updated
        defaults.set(enabledOverrides, forKey: overridesKey)
        rebuildEnabledIndexes() // 활성 인덱스 갱신 (v0.2.3)
        DebugLogger.shared.info("MODEL", "\(provider.rawValue) 모델 전체 \(enabled ? "사용" : "해제"): \(targets.count)개")
    }

    private func overrideKey(_ model: AIModel) -> String {
        "\(model.provider.rawValue):\(model.id)"
    }

    private func loadEnabledOverrides() {
        guard let dict = defaults.dictionary(forKey: overridesKey) as? [String: Bool] else { return }
        enabledOverrides = dict
    }

    // MARK: - 사용자 지정 모델 저장/로드
    private func saveCustomModels() {
        // refresh() 배치 중에는 호출부의 반복 저장을 무시하고 마지막에 1회 (v0.2.2)
        guard !isBatchUpdating else { return }
        let customModels = models.filter { model in
            !Self.defaultModels.contains { $0.id == model.id && $0.provider == model.provider }
        }
        if let data = try? JSONEncoder().encode(customModels) {
            defaults.set(data, forKey: userDefaultsKey)
        }
    }

    private func loadCustomModels() {
        guard let data = defaults.data(forKey: userDefaultsKey),
              let customModels = try? JSONDecoder().decode([AIModel].self, from: data) else { return }
        for model in customModels {
            if !models.contains(where: { $0.id == model.id && $0.provider == model.provider }) {
                models.append(model)
            }
        }
    }

    // MARK: - 서버 새로고침 (키 설정 공급자만 · v1.7.1 T-58 리포트+로그)

    @discardableResult
    func refresh() async -> CatalogRefreshReport {
        DebugLogger.shared.info("MODEL", "모델 목록 갱신 시작")
        // 배치 모드 — mergeRemoteModels/syncCustomEndpoint의 개별 변이마다 rebuildIndexes/saveCustomModels를
        // 실행하지 않고, 전부 수집한 뒤 이 함수 마지막에 1회만 확정 (v0.2.2 성능)
        isBatchUpdating = true
        defer {
            isBatchUpdating = false
            rebuildIndexes()
            saveCustomModels()
        }
        async let openRouter = refreshOpenAICompatible(.openRouter) { item, id in
            (item["name"] as? String) ?? id
        } filter: { $0.hasSuffix(":free") }
        async let groq = refreshOpenAICompatible(.groq) { item, id in
            (item["owned_by"] as? String).map { "\(id) (\($0))" } ?? id
        }
        async let nvidia = refreshOpenAICompatible(.nvidia) { item, id in
            (item["owned_by"] as? String).map { "\(id) (\($0))" } ?? id
        }
        async let gemini = refreshGemini()
        async let ollama = refreshOllama()
        async let custom = refreshCustomEndpoints()
        // v2.1 T-93 — 신규 OpenAI 호환 공급자 3종 (키 없으면 자동 skipped)
        async let openAIOfficial = refreshOpenAICompatible(.openAI) { _, id in id }
        async let vercel = refreshOpenAICompatible(.vercelGateway) { item, id in
            (item["owned_by"] as? String).map { "\(id) (\($0))" } ?? id
        }
        async let tokenRouter = refreshOpenAICompatible(.tokenRouter) { _, id in id }

        let results = await [openRouter, groq, nvidia, gemini, ollama, custom,
                             openAIOfficial, vercel, tokenRouter]
        let report = CatalogRefreshReport(results: results)
        let failed = results.filter { $0.status == .failed }
        let failedLog = failed.map { r -> String in
            let reason = r.errorMessage ?? ""
            return reason.isEmpty ? "\(r.provider.rawValue)" : "\(r.provider.rawValue)(\(reason))"
        }
        var logLine = "모델 목록 갱신 완료 — 추가 \(report.addedTotal)개 / 제거 \(report.removedTotal)개"
            + (failedLog.isEmpty ? "" : " / 실패: \(failedLog.joined(separator: ", "))")
        if !autoDisabledKeys.isEmpty {
            logLine += " / 자동 제외(410/404) 모델 \(autoDisabledKeys.count)개 유지"
        }
        DebugLogger.shared.info("MODEL", logLine)
        return report
    }

    /// Ollama 로컬 서버 모델 목록 갱신 (v1.8 T-70d)
    private func refreshOllama() async -> ProviderRefreshResult {
        let baseURL = AppSettings.shared.ollamaBaseURL.isEmpty ? Provider.ollama.baseURL : AppSettings.shared.ollamaBaseURL
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            DebugLogger.shared.debug("MODEL", "Ollama: BaseURL 미설정 — 건너뜀")
            return ProviderRefreshResult(provider: .ollama, status: .skipped)
        }

        DebugLogger.shared.info("MODEL", "Ollama: 모델 목록 조회 중… (\(baseURL))")
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let reason = CatalogRefreshReport.refreshFailureReason(http.statusCode)
                DebugLogger.shared.warn("MODEL", "E-MAC-OLLAMA-1001 Ollama 목록 조회 실패 (HTTP \(http.statusCode)) — \(reason)")
                return ProviderRefreshResult(provider: .ollama, status: .failed, errorMessage: "Ollama \(reason)")
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["models"] as? [[String: Any]] else {
                let reason = "응답 형식 오류"
                DebugLogger.shared.warn("MODEL", "E-MAC-OLLAMA-1001 Ollama 응답 파싱 실패 — \(reason)")
                return ProviderRefreshResult(provider: .ollama, status: .failed, errorMessage: "Ollama \(reason)")
            }

            var remoteModels: [AIModel] = []
            for item in list {
                guard let name = item["name"] as? String else { continue }
                let displayName = name.replacingOccurrences(of: ":latest", with: "")
                remoteModels.append(AIModel(id: name, provider: .ollama, displayName: displayName, isFree: true, contextLimit: 128_000))
            }
            return mergeRemoteModels(remoteModels, provider: .ollama)
        } catch {
            let reason = "서버 접속 실패 (로컬 Ollama 실행 확인)"
            DebugLogger.shared.warn("MODEL", "E-MAC-OLLAMA-1001 \(reason): \(error.localizedDescription)")
            return ProviderRefreshResult(provider: .ollama, status: .failed, errorMessage: "Ollama \(reason)")
        }
    }

    /// 커스텀 엔드포인트 /models 동기화 — 등록된 모든 엔드포인트 순회, 복합 ID 모델로 편입 (v1.9 T-92)
    /// 추가 전용(원격 제거 없음): 수동 추가 모델 보호. 엔드포인트 삭제 시 소속 모델은 함께 정리됨(T-84)
    private func refreshCustomEndpoints() async -> ProviderRefreshResult {
        let endpoints = CustomEndpointStore(defaults: CustomEndpointStore.suiteDefaults).endpoints
            .filter { !$0.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !endpoints.isEmpty else {
            DebugLogger.shared.debug("MODEL", "커스텀: 등록된 엔드포인트 없음 — 건너뜀")
            return ProviderRefreshResult(provider: .custom, status: .skipped)
        }

        var addedTotal = 0
        var removedTotal = 0
        var failedNames: [String] = []

        for endpoint in endpoints {
            // URL 정규화 — 연결 테스트와 동일 규칙 (스킴 보정 + trailing slash 제거)
            var base = endpoint.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !base.hasPrefix("http://") && !base.hasPrefix("https://") {
                let isLocal = base.hasPrefix("localhost") || base.hasPrefix("127.0.0.1")
                base = (isLocal ? "http://" : "https://") + base
            }
            while base.hasSuffix("/") { base = String(base.dropLast()) }

            guard let url = URL(string: "\(base)/models") else {
                DebugLogger.shared.warn("MODEL", "[E-MAC-VALID-1003] 커스텀 '\(endpoint.name)' URL 형식 오류: \(base)")
                failedNames.append(endpoint.name)
                continue
            }

            var req = URLRequest(url: url)
            req.timeoutInterval = 15
            if !endpoint.apiKey.isEmpty {
                req.setValue("Bearer \(endpoint.apiKey)", forHTTPHeaderField: "Authorization")
            }

            DebugLogger.shared.info("MODEL", "커스텀 '\(endpoint.name)': 모델 목록 조회 중… (\(base))")
            guard let (data, _) = try? await URLSession.shared.data(for: req),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["data"] as? [[String: Any]] else {
                DebugLogger.shared.warn("MODEL", "[E-MAC-NET-1004] 커스텀 '\(endpoint.name)' 모델 목록 조회 실패")
                failedNames.append(endpoint.name)
                continue
            }

            let ids = list.compactMap { $0["id"] as? String }
            let result = syncCustomEndpoint(ids, endpoint: endpoint)
            addedTotal += result.added
            removedTotal += result.removed
            DebugLogger.shared.info("MODEL", "커스텀 '\(endpoint.name)': 원격 \(ids.count)개 기준 신규 \(result.added)개 / 제거 \(result.removed)개")
        }

        let status: ProviderRefreshResult.Status = failedNames.count == endpoints.count ? .failed : .ok
        var errorMessage: String? = nil
        if !failedNames.isEmpty {
            errorMessage = "엔드포인트 조회 실패: \(failedNames.joined(separator: ", "))"
        }
        return ProviderRefreshResult(provider: .custom, status: status, addedCount: addedTotal, removedCount: removedTotal, errorMessage: errorMessage)
    }

    /// 단일 엔드포인트 동기화 — 스테일 제거(스냅샷 기준) + 신규 추가 + 스냅샷 갱신 (v2.1 T-98)
    /// 스냅샷은 동기화 완료 시점의 해당 엔드포인트 전체 모델 ID — 이후 사용자가 수동 추가한 모델도 다음 회차부터 자동 보호된다.
    @discardableResult
    func syncCustomEndpoint(_ remoteIDs: [String], endpoint: CustomEndpoint) -> (added: Int, removed: Int) {
        let snapshotKey = "custom:\(endpoint.id.uuidString)"
        let idPrefix = "\(endpoint.id.uuidString):"

        // 1) 스테일 제거 — 이전 갱신 스냅샷에 있었고 이번 원격 목록에 없는 모델만
        let previousIDs = Set(refreshedIDs[snapshotKey] ?? [])
        let currentRemoteIDs = Set(remoteIDs.compactMap { raw -> String? in
            guard !raw.isEmpty else { return nil }
            return CustomEndpoint.compositeID(endpointID: endpoint.id, modelID: raw)
        })
        var removed = 0
        for staleID in previousIDs.subtracting(currentRemoteIDs).sorted() {
            if models.contains(where: { $0.provider == .custom && $0.id == staleID }) {
                models.removeAll { $0.provider == .custom && $0.id == staleID }
                removed += 1
                DebugLogger.shared.info("MODEL", "커스텀 '\(endpoint.name)': 원격에서 사라져 제거 — \(staleID)")
            }
        }

        // 2) 신규 추가 — 중복 복합 ID 건너뜀
        var added = 0
        for rawID in remoteIDs where !rawID.isEmpty {
            let composite = CustomEndpoint.compositeID(endpointID: endpoint.id, modelID: rawID)
            if models.contains(where: { $0.provider == .custom && $0.id == composite }) { continue }
            models.append(AIModel(
                id: composite,
                provider: .custom,
                displayName: "\(rawID) (\(endpoint.name))",
                contextLimit: 128_000
            ))
            added += 1
        }

        // 3) 스냅샷 갱신 — 원격 ID만 저장. 사용자의 수동 추가 모델은 스냅샷 밖이라 영구 보호된다.
        refreshedIDs[snapshotKey] = Array(currentRemoteIDs).sorted()
        defaults.set(refreshedIDs, forKey: refreshedIDsKey)

        if added > 0 || removed > 0 {
            saveCustomModels()
            DebugLogger.shared.info("MODEL", "[FEATURE] 커스텀 동기화 실행됨: '\(endpoint.name)' +\(added)/-\(removed)")
        }
        return (added, removed)
    }

    /// 엔드포인트 삭제 시 동기화 스냅샷 정리 (deleteCustomEndpoint 경유)
    func clearCustomSyncSnapshot(endpointID: UUID) {
        let key = "custom:\(endpointID.uuidString)"
        refreshedIDs.removeValue(forKey: key)
        defaults.set(refreshedIDs, forKey: refreshedIDsKey)
    }

    /// OpenAI 호환(/models, Bearer 인증) 공급자 공용 갱신 — OpenRouter/Groq/NVIDIA
    private func refreshOpenAICompatible(
        _ provider: Provider,
        displayName: @escaping ([String: Any], String) -> String,
        filter: ((String) -> Bool)? = nil
    ) async -> ProviderRefreshResult {
        let key = AppSettings.shared.apiKey(for: provider)
        guard !key.isEmpty else {
            DebugLogger.shared.debug("MODEL", "\(provider.rawValue): API 키 미설정 — 건너뜀")
            return ProviderRefreshResult(provider: provider, status: .skipped)
        }

        guard let url = URL(string: "\(provider.baseURL)/models") else {
            return ProviderRefreshResult(provider: provider, status: .failed, errorMessage: "BaseURL 형식 오류")
        }
        DebugLogger.shared.info("MODEL", "\(provider.rawValue): 모델 목록 조회 중…")
        var req = URLRequest(url: url)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse else {
            let reason = "서버 접속 실패 (네트워크 오류)"
            DebugLogger.shared.warn("MODEL", "E-MAC-NET-1004 \(provider.rawValue) 모델 목록 조회 실패 — \(reason)")
            return ProviderRefreshResult(provider: provider, status: .failed, errorMessage: reason)
        }

        let status = http.statusCode
        guard (200..<300).contains(status) else {
            // 모델 목록 조회의 4xx — 호출 방식/URL/인증 오류 (모델 문제 아님, 자동 비활성화 대상 아님)
            let reason = CatalogRefreshReport.refreshFailureReason(status)
            DebugLogger.shared.warn("MODEL", "E-MAC-NET-1004 \(provider.rawValue) 모델 목록 조회 실패 (HTTP \(status)) — \(reason)")
            return ProviderRefreshResult(provider: provider, status: .failed, errorMessage: reason)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else {
            let reason = "응답 형식 오류"
            DebugLogger.shared.warn("MODEL", "E-MAC-NET-1004 \(provider.rawValue) 모델 목록 조회 실패 — \(reason)")
            return ProviderRefreshResult(provider: provider, status: .failed, errorMessage: reason)
        }

        var remoteModels: [AIModel] = []
        for item in list {
            guard let id = item["id"] as? String else { continue }
            if let filter, !filter(id) { continue }
            remoteModels.append(AIModel(id: id, provider: provider, displayName: displayName(item, id)))
        }
        return mergeRemoteModels(remoteModels, provider: provider)
    }

    /// 원격 목록 병합 — 신규 추가 + 갱신 유래 모델 중 원격에서 사라진 것만 제거(정적/수동 추가는 보호)
    private func mergeRemoteModels(_ remote: [AIModel], provider: Provider) -> ProviderRefreshResult {
        let existingIDs = Set(models.filter { $0.provider == provider }.map(\.id))
        let newOnes = remote.filter { !existingIDs.contains($0.id) }
        models.append(contentsOf: newOnes)

        let previousIDs = Set(refreshedIDs[provider.rawValue] ?? [])
        let remoteIDs = Set(remote.map(\.id))
        var removedCount = 0
        for staleID in previousIDs.subtracting(remoteIDs).sorted()
        where !Self.defaultModels.contains(where: { $0.id == staleID && $0.provider == provider }) {
            models.removeAll { $0.provider == provider && $0.id == staleID }
            removedCount += 1
            DebugLogger.shared.info("MODEL", "\(provider.rawValue): 원격에서 사라져 제거 — \(staleID)")
        }

        refreshedIDs[provider.rawValue] = Array(remoteIDs).sorted()
        defaults.set(refreshedIDs, forKey: refreshedIDsKey)
        saveCustomModels()

        if newOnes.isEmpty && removedCount == 0 {
            DebugLogger.shared.info("MODEL", "\(provider.rawValue): 갱신 완료 — 변경 없음 (원격 \(remote.count)개)")
        } else {
            DebugLogger.shared.info("MODEL", "\(provider.rawValue): 갱신 완료 — 신규 \(newOnes.count)개 / 제거 \(removedCount)개 (원격 \(remote.count)개)")
            if !newOnes.isEmpty {
                let names = newOnes.prefix(10).map(\.id).joined(separator: ", ")
                DebugLogger.shared.info("MODEL", "\(provider.rawValue) 신규: \(names)\(newOnes.count > 10 ? " 외 \(newOnes.count - 10)개" : "")")
            }
        }
        return ProviderRefreshResult(provider: provider, status: .ok, addedCount: newOnes.count, removedCount: removedCount)
    }

    /// Gemini 공식 ListModels — generateContent 지원 모델만 수집 (v1.7 T-52, v1.7.1부터 refresh()에 정식 편입)
    private func refreshGemini() async -> ProviderRefreshResult {
        let key = AppSettings.shared.apiKey(for: .gemini)
        guard !key.isEmpty else {
            DebugLogger.shared.debug("MODEL", "Gemini: API 키 미설정 — 건너뜀")
            return ProviderRefreshResult(provider: .gemini, status: .skipped)
        }
        guard var comps = URLComponents(string: "\(Provider.gemini.baseURL)/v1beta/models") else {
            return ProviderRefreshResult(provider: .gemini, status: .failed, errorMessage: "Gemini URL 형식 오류")
        }
        comps.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "pageSize", value: "1000"),
        ]
        guard let url = comps.url else {
            return ProviderRefreshResult(provider: .gemini, status: .failed, errorMessage: "Gemini URL 형식 오류")
        }
        let (data, response) = await ((try? URLSession.shared.data(from: url)) ?? (Data(), nil))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let reason = CatalogRefreshReport.refreshFailureReason(http.statusCode)
            DebugLogger.shared.warn("MODEL", "E-MAC-NET-1004 Gemini 모델 목록 조회 실패 (HTTP \(http.statusCode)) — \(reason)")
            return ProviderRefreshResult(provider: .gemini, status: .failed, errorMessage: "Gemini \(reason)")
        }
        guard !data.isEmpty else {
            DebugLogger.shared.warn("MODEL", "E-MAC-NET-1004 Gemini 모델 목록 조회 실패")
            return ProviderRefreshResult(provider: .gemini, status: .failed, errorMessage: "Gemini 서버 접속 실패")
        }

        var geminiModels: [AIModel] = []
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let list = json["models"] as? [[String: Any]] {
            // 채팅에 못 쓰는 계열 제외 + generateContent 미지원 모델 제외
            let excludedKeywords = ["embedding", "aqa", "imagen", "veo", "tts"]
            for item in list {
                guard let name = item["name"] as? String else { continue } // "models/gemini-xxx"
                let id = name.split(separator: "/").last.map(String.init) ?? name
                if excludedKeywords.contains(where: { id.lowercased().contains($0) }) { continue }
                if let methods = item["supportedGenerationMethods"] as? [String],
                   !methods.contains("generateContent") { continue }
                let displayName = (item["displayName"] as? String) ?? id
                geminiModels.append(AIModel(id: id, provider: .gemini, displayName: displayName))
            }
            DebugLogger.shared.info("MODEL", "Gemini: 모델 목록 조회 중… → \(list.count)개 수신")
        } else {
            let reason = "응답 형식 오류"
            DebugLogger.shared.warn("MODEL", "E-MAC-NET-1004 Gemini 응답 파싱 실패 — \(reason)")
            return ProviderRefreshResult(provider: .gemini, status: .failed, errorMessage: "Gemini \(reason)")
        }
        return mergeRemoteModels(geminiModels, provider: .gemini)
    }

    // MARK: - 헬퍼
    func models(for provider: Provider) -> [AIModel] {
        models.filter { $0.provider == provider }
    }

    /// 429(rate 한도) 자동 폴백용 무료 활성 모델 우선순위 (v3.4 T-162)
    /// Groq → NVIDIA → Gemini → OpenRouter 순. 기본 모델 폴백과 요청 중 폴백 모두에 사용한다.
    /// - `isFree`가 아니거나, 사용 해제(enabledOverrides=false)된 모델은 제외
    /// - `excluding`에 지정한 모델은 제외(현재 rate 실패 모델을 건너뛰기)
    static let fallbackPriority: [(id: String, provider: Provider)] = [
        ("llama-3.3-70b-versatile", .groq),
        ("openai/gpt-oss-20b", .nvidia),
        ("gemini-3.6-flash", .gemini),
        ("google/gemini-2.5-flash-preview:free", .openRouter),
        ("deepseek/deepseek-chat-v3-0324:free", .openRouter),
    ]

    /// 우선순위 리스트에서 활성화된 무료 모델을 순서대로 반환 (발견 시 즉시 .first 사용 가능)
    static func freeFallbackCandidates(excluding current: AIModel? = nil) -> [AIModel] {
        let catalog = ModelCatalog.shared
        return fallbackPriority.compactMap { entry in
            catalog.models.first { $0.id == entry.id && $0.provider == entry.provider }
        }
        .filter { $0.isFree }
        .filter { catalog.isEnabled($0) }
        .filter { candidate in
            guard let current else { return true }
            return !(candidate.provider == current.provider && candidate.id == current.id)
        }
    }

    /// 기본 폴백 모델 — 우선순위 첫 활성 무료 모델, 없으면 등록 목록 첫 모델
    static func primaryFallbackModel() -> AIModel {
        freeFallbackCandidates().first ?? defaultModels.first!
    }

    /// 공급자 섹션 내 무료 모델을 상단에 배치하는 안정 정렬 (v3.1)
    /// Swift의 sorted(by:)는 안정성이 보장되지 않으므로 원래 인덱스로 동률을 끊어 순서를 보존한다.
    static func freeFirst(_ input: [AIModel]) -> [AIModel] {
        input.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.isFree != rhs.element.isFree {
                    return lhs.element.isFree && !rhs.element.isFree
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    func model(id: String, provider: Provider) -> AIModel? {
        models.first { $0.id == id && $0.provider == provider }
    }

    // MARK: - 표시용 라벨 헬퍼
    static func label(for provider: Provider, modelID: String) -> String {
        if let model = ModelCatalog.shared.model(id: modelID, provider: provider) {
            return model.label
        }
        let rawID = modelID.split(separator: "/").last.map(String.init) ?? modelID
        return "\(provider.rawValue) \(rawID)"
    }
}

extension AIModel {
    var label: String {
        let rawID = id.split(separator: "/").last.map(String.init) ?? id
        return "\(provider.rawValue) \(displayName) (\(rawID))"
    }
}
