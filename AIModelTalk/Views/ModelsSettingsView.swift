import SwiftUI

struct ModelsSettingsView: View {
    @Environment(\.theme) private var theme
    /// @ObservedObject를 의도적으로 쓰지 않는다 — 토글(enabledOverrides) 변화로 이 화면 전체가
    /// 재평가되는 것을 막는다. 각 행(ModelRow)이 자기 모델만 관찰한다. (v0.2.3)
    /// 모델 목록/카운트는 쿼리 시점에 catalog에서 직접 읽는다.
    private let catalog = ModelCatalog.shared

    private let noneSelectedID = ""

    @State private var selectedEntryID: String = ""
    @State private var endpoints: [CustomEndpoint] = []
    @State private var searchText = ""
    @State private var isRefreshing = false
    @State private var refreshResult: String?
    @State private var hasRefreshError = false
    @State private var showAddModel = false
    @State private var showModelManager = false

    private var entries: [ProviderEntry] {
        ProviderEntry.currentList(endpoints: endpoints).filter { entry in
            !(entry.provider == .appleIntelligence && !AppleIntelligenceSupport.modelAvailable)
        }
    }

    private var effectiveEntry: ProviderEntry? {
        guard !selectedEntryID.isEmpty else { return nil }
        return entries.first { $0.id == selectedEntryID }
    }

    private var fallbackFirstEndpointID: UUID? {
        entries.compactMap(\.endpoint).first?.id
    }

    private var allModelCount: Int { catalog.models.count }

    var body: some View {

                VStack(spacing: theme.space4) {
                    // ── 상단 카드 (고정) ──
                    VStack(spacing: theme.space4) {
                        // 검색 필드
                        HStack {
                            SettingsSearchField(
                                placeholder: "모델 이름, ID, 공급자 검색",
                                text: $searchText
                            )
                        }
                        
                        // 공급자 Picker + 버튼
                        HStack(spacing: 12) {
                            Picker("공급자", selection: $selectedEntryID) {
                                Text("선택 안 함 (전체 \(allModelCount)개)")
                                    .tag(noneSelectedID)
                                ForEach(entries) { entry in
                                    let vis = catalog.visibleModels(in: entry, fallbackFirstEndpointID: fallbackFirstEndpointID).count
                                    let tot = catalog.totalModelCount(in: entry, fallbackFirstEndpointID: fallbackFirstEndpointID)
                                    Text("\(entry.title) (활성 \(vis)/\(tot))")
                                        .tag(entry.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 280, alignment: .leading)
                            .labelsHidden()
                            
                            Spacer()
                            
                            Button {
                                showAddModel = true
                            } label: {
                                Label("추가", systemImage: "plus")
                            }
                            .help("선택된 공급자에 모델을 추가합니다")
                            .disabled(effectiveEntry == nil)
                            
                            Button("모두 사용") { setAllEnabledForSelection(true) }
                                .disabled(displayedModels.isEmpty)
                            
                            Button("모두 해제") { setAllEnabledForSelection(false) }
                                .disabled(displayedModels.isEmpty)
                            
                            if effectiveEntry?.provider == .ollama {
                                Button { showModelManager = true } label: {
                                    Label("모델 관리", systemImage: "cube.box")
                                }
                            }
                            
                            if let result = refreshResult {
                                Text(result)
                                    .font(.caption)
                                    .foregroundStyle(hasRefreshError ? Color.orange : theme.secondaryText)
                                    .lineLimit(1)
                            }
                            Button {
                                Task { await refreshModels() }
                            } label: {
                                if isRefreshing {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("새로고침", systemImage: "arrow.clockwise")
                                }
                            }
                            .disabled(isRefreshing)
                        }
                        
                        // 공급자 모델 목록 카운트
                        if let entry = effectiveEntry {
                            let vis = catalog.visibleModels(in: entry, fallbackFirstEndpointID: fallbackFirstEndpointID).count
                            let tot = catalog.models(in: entry, fallbackFirstEndpointID: fallbackFirstEndpointID).count
                            HStack {
                                Text("공급자 \(entry.title) 모델 목록")
                                    .font(.headline)
                                Spacer()
                                Text("활성 \(vis) / 전체 \(tot)")
                                    .font(.caption)
                                    .foregroundStyle(theme.secondaryText)
                            }
                        }
                    }
                    .padding(theme.cardInset)
                    .background(theme.cardBackground).overlay(RoundedRectangle(cornerRadius: theme.cardCornerRadius).stroke(theme.cardBorder.opacity(theme.borderOpacity), lineWidth: theme.defaultBorderWidth)).clipShape(RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous))
                    
                    Spacer(minLength: theme.cardInset)
                    
                    // ── 하단 카드 (스크롤, 가상화) ──
                    // 모델이 700+개여도 필요한 행만 렌더되도록 List로 전환 (v0.2.1 성능)
                    List {
                        if selectedEntryID.isEmpty && searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "cpu")
                                    .font(.title2)
                                    .foregroundStyle(theme.tertiaryText)
                                Text("공급자를 선택하거나 검색하세요")
                                    .font(.callout)
                                    .foregroundStyle(theme.secondaryText)
                                Text("총 \(allModelCount)개 모델 등록됨")
                                    .font(.caption)
                                    .foregroundStyle(theme.tertiaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .listRowSeparator(.hidden)
                        } else if searchedModels.isEmpty {
                            Text("'\(searchText)'에 일치하는 모델이 없습니다")
                                .foregroundStyle(theme.secondaryText)
                                .frame(maxWidth: .infinity)
                                .listRowSeparator(.hidden)
                        } else {
                            ForEach(searchedModels) { model in
                                ModelRow(
                                    model: model,
                                    onDelete: { deleteModel(model) }
                                )
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 0, leading: theme.space16, bottom: 0, trailing: theme.space16))
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .frame(maxHeight: .infinity)
                    .background(theme.cardBackground).overlay(RoundedRectangle(cornerRadius: theme.cardCornerRadius).stroke(theme.cardBorder.opacity(theme.borderOpacity), lineWidth: theme.defaultBorderWidth)).clipShape(RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous))
                    
                    Spacer(minLength: theme.cardInset)
                }
                .sheet(isPresented: $showAddModel) {
                    AddModelSheet(
                        entries: entries,
                        preselectedEntry: effectiveEntry,
                        fallbackFirstEndpointID: fallbackFirstEndpointID
                    )
                }
                .sheet(isPresented: $showModelManager) {
                    ModelManagerView()
                }
                .onChange(of: selectedEntryID) { _, newValue in
                    searchText = ""
                    if newValue.isEmpty {
                        DebugLogger.shared.info("APP", "[FEATURE] 모델 공급자 선택 해제됨")
                    } else if let entry = entries.first(where: { $0.id == newValue }) {
                        DebugLogger.shared.info("APP", "[FEATURE] 모델 공급자 선택 변경됨: '\(entry.title)'")
                    }
                }
                .onAppear {
                    reloadEndpoints()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(theme.space16)

    }

    // MARK: - 데이터

    func reloadEndpoints() {
        endpoints = CustomEndpointStore(defaults: CustomEndpointStore.suiteDefaults).endpoints
        if !selectedEntryID.isEmpty,
           !entries.contains(where: { $0.id == selectedEntryID }) {
            selectedEntryID = ""
        }
    }

    private var displayedModels: [AIModel] {
        guard let entry = effectiveEntry else { return [] }
        return catalog.models(in: entry, fallbackFirstEndpointID: fallbackFirstEndpointID)
    }

    private var searchedModels: [AIModel] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let base = displayedModels
        guard !query.isEmpty else { return base }
        return base.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) ||
            $0.id.localizedCaseInsensitiveContains(query) ||
            $0.provider.rawValue.localizedCaseInsensitiveContains(query)
        }
    }

    private func setAllEnabledForSelection(_ enabled: Bool) {
        guard let entry = effectiveEntry else { return }
        catalog.setAllEnabled(enabled, in: entry, fallbackFirstEndpointID: fallbackFirstEndpointID)
    }

    private func deleteModel(_ model: AIModel) {
        let alert = NSAlert()
        alert.messageText = "모델 삭제"
        alert.informativeText = "'\(model.displayName)' 모델을 삭제하시겠습니까?"
        alert.addButton(withTitle: "삭제")
        alert.addButton(withTitle: "취소")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            catalog.removeModel(model)
        }
    }

    private func refreshModels() async {
        isRefreshing = true
        refreshResult = nil
        hasRefreshError = false
        defer { isRefreshing = false }
        let report = await catalog.refresh()
        hasRefreshError = !report.failedProviderNames.isEmpty
        var text = CatalogRefreshReport.summaryText(report.results)
        if catalog.autoDisabledCount > 0 {
            text += text.isEmpty ? "" : " / "
            text += "자동 제외(410/404) 모델 \(catalog.autoDisabledCount)개 유지"
        }
        refreshResult = text
    }
}

// MARK: - 모델 행

private struct ModelRow: View {
    @Environment(\.theme) private var theme
    /// 행마다 카탈로그를 직접 관찰해 토글이 이 행 하나만 재평가되게 분리 (v0.2.3)
    @ObservedObject private var catalog = ModelCatalog.shared
    let model: AIModel
    let onDelete: () -> Void

    /// 백만 토큰당 입/출력 USD 축약 표시 (v0.2.7)
    private var priceText: String? {
        let i = model.inputPricePerM ?? 0
        let o = model.outputPricePerM ?? 0
        func fmt(_ v: Double) -> String {
            v >= 1 ? String(format: "$%.2f", v) : String(format: "$%.3f", v)
        }
        return "\(fmt(i))/\(fmt(o))"
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.provider.accentSwiftUIColor)
                    .frame(width: theme.dotStandard, height: theme.dotStandard)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(model.provider.rawValue)
                            .font(.caption2)
                            .foregroundStyle(theme.tertiaryText)
                    }
                    Text(model.id)
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            HStack(spacing: 14) {
                if model.isPaid, let cost = priceText {
                    Text(cost)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(theme.accentColor)
                        .help("백만 토큰당 입/출력 USD 가격 (설정 → 비용/토큰)")
                } else if model.contextLimit > 0 {
                    Text("\(model.contextLimit / 1000)K")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                }

                Toggle("", isOn: Binding(
                    get: { catalog.isEnabled(model) },
                    set: { catalog.setEnabled(model, $0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help("모델 피커 표시 여부")

                Button { onDelete() } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(theme.secondaryText)
                }
                .buttonStyle(.plain)
                .help("모델 삭제")
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 모델 추가 시트

private struct AddModelSheet: View {
    let entries: [ProviderEntry]
    let preselectedEntry: ProviderEntry?
    let fallbackFirstEndpointID: UUID?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var catalog = ModelCatalog.shared
    @Environment(\.theme) private var theme

    @State private var selectedEntry: ProviderEntry?
    @State private var modelID = ""
    @State private var displayName = ""
    @State private var contextLimit = "128000"
    @State private var inputPrice = ""
    @State private var outputPrice = ""
    @State private var customEndpoints: [CustomEndpoint] = []
    @State private var selectedEndpointID: UUID?

    var body: some View {
        VStack(spacing: 16) {
            Text("모델 추가")
                .font(.headline)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("공급자")
                        .foregroundStyle(theme.secondaryText)
                        .gridColumnAlignment(.trailing)
                    Picker("", selection: $selectedEntry) {
                        Text("공급자 선택…").tag(ProviderEntry?.none)
                        ForEach(entries.filter { $0.provider != .appleIntelligence || AppleIntelligenceSupport.modelAvailable }) { entry in
                            Text(entry.title).tag(ProviderEntry?.some(entry))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260)
                }

                if selectedEntry?.provider == .custom {
                    GridRow {
                        Text("엔드포인트")
                            .foregroundStyle(theme.secondaryText)
                            .gridColumnAlignment(.trailing)
                        Picker("", selection: $selectedEndpointID) {
                            Text("엔드포인트 선택…").tag(UUID?.none)
                            ForEach(customEndpoints) { endpoint in
                                Text(endpoint.name).tag(UUID?.some(endpoint.id))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 260)
                    }
                }

                GridRow {
                    Text("모델 ID")
                        .foregroundStyle(theme.secondaryText)
                        .gridColumnAlignment(.trailing)
                    TextField("예: gpt-4o", text: $modelID)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("표시 이름")
                        .foregroundStyle(theme.secondaryText)
                        .gridColumnAlignment(.trailing)
                    TextField("예: GPT-4o", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("컨텍스트 한도")
                        .foregroundStyle(theme.secondaryText)
                        .gridColumnAlignment(.trailing)
                    TextField("예: 128000", text: $contextLimit)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("입력 가격")
                        .foregroundStyle(theme.secondaryText)
                        .gridColumnAlignment(.trailing)
                    TextField("백만 토큰당 USD, 예: 2.50 (비우면 무료/미등록)", text: $inputPrice)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("출력 가격")
                        .foregroundStyle(theme.secondaryText)
                        .gridColumnAlignment(.trailing)
                    TextField("백만 토큰당 USD, 예: 10.00", text: $outputPrice)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .frame(minWidth: 420)

            if selectedEntry?.provider == .custom && customEndpoints.isEmpty {
                Text("먼저 설정 → 공급자에서 엔드포인트를 추가해 주세요.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("추가") { addModel(); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            if displayName.isEmpty { displayName = modelID }
            selectedEntry = preselectedEntry ?? entries.first { $0.provider != .appleIntelligence || AppleIntelligenceSupport.modelAvailable }
            if selectedEntry?.provider == .custom {
                customEndpoints = CustomEndpointStore(defaults: CustomEndpointStore.suiteDefaults).endpoints
                selectedEndpointID = customEndpoints.first?.id
            }
        }
        .onChange(of: selectedEntry) { _, newEntry in
            if newEntry?.provider == .custom && customEndpoints.isEmpty {
                customEndpoints = CustomEndpointStore(defaults: CustomEndpointStore.suiteDefaults).endpoints
                selectedEndpointID = newEntry?.endpoint?.id ?? customEndpoints.first?.id
            } else {
                selectedEndpointID = nil
            }
        }
    }

    private var canAdd: Bool {
        guard !modelID.isEmpty, !displayName.isEmpty, Int(contextLimit) != nil else { return false }
        if !inputPrice.isEmpty, Double(inputPrice) ?? -1 < 0 { return false }
        if !outputPrice.isEmpty, Double(outputPrice) ?? -1 < 0 { return false }
        if selectedEntry?.provider == .custom { return selectedEndpointID != nil }
        return true
    }

    private func parsedPrices() -> (input: Double?, output: Double?) {
        let i = inputPrice.trimmingCharacters(in: .whitespaces)
        let o = outputPrice.trimmingCharacters(in: .whitespaces)
        return (i.isEmpty ? nil : Double(i), o.isEmpty ? nil : Double(o))
    }

    private func addModel() {
        guard let limit = Int(contextLimit), let entry = selectedEntry else { return }
        let prices = parsedPrices()
        // 가격이 둘 다 비어있으면 무료, 하나라도 있으면 유료 취급 (isFree: false)
        let isFree = prices.input == nil && prices.output == nil
        let model: AIModel
        if entry.provider == .custom, let endpointID = selectedEndpointID,
           let endpoint = customEndpoints.first(where: { $0.id == endpointID }) {
            model = AIModel(
                id: CustomEndpoint.compositeID(endpointID: endpoint.id, modelID: modelID),
                provider: .custom,
                displayName: "\(displayName) (\(endpoint.name))",
                isFree: isFree,
                contextLimit: limit,
                inputPricePerM: prices.input,
                outputPricePerM: prices.output
            )
        } else {
            model = AIModel(
                id: modelID,
                provider: entry.provider,
                displayName: displayName,
                isFree: isFree,
                contextLimit: limit,
                inputPricePerM: prices.input,
                outputPricePerM: prices.output
            )
        }
        catalog.addModel(model)
    }
}

#Preview {
    SettingsView()
}
