import SwiftUI

struct ModelsSettingsView: View {
    @ObservedObject private var catalog = ModelCatalog.shared
    @ObservedObject private var chatVM = ChatViewModel.shared

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

                VStack(spacing: DS.space4) {
                    // ── 상단 카드 (고정) ──
                    VStack(spacing: DS.space4) {
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
                                    let tot = catalog.models(in: entry, fallbackFirstEndpointID: fallbackFirstEndpointID).count
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
                                    .foregroundStyle(hasRefreshError ? Color.orange : Color.secondary)
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
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(DS.cardInset)
                    .dsCard()
                    
                    Spacer(minLength: DS.cardInset)
                    
                    // ── 하단 카드 (스크롤) ──
                    ScrollView {
                        VStack(spacing: 0) {
                            if selectedEntryID.isEmpty && searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "cpu")
                                        .font(.title2)
                                        .foregroundStyle(.tertiary)
                                    Text("공급자를 선택하거나 검색하세요")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                    Text("총 \(allModelCount)개 모델 등록됨")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            } else if searchedModels.isEmpty {
                                Text("'\(searchText)'에 일치하는 모델이 없습니다")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                            } else {
                                ForEach(searchedModels) { model in
                                    ModelRow(
                                        model: model,
                                        isDefault: chatVM.defaultModel?.provider == model.provider
                                        && chatVM.defaultModel?.id == model.id,
                                        isEnabled: catalog.isEnabled(model),
                                        onToggleDefault: { chatVM.setDefaultModel(model) },
                                        onToggleEnabled: { catalog.setEnabled(model, $0) },
                                        onDelete: { deleteModel(model) }
                                    )
                                    if model.id != searchedModels.last?.id {
                                        Divider().padding(.leading, DS.space16)
                                    }
                                }
                            }
                        }
                        .padding(DS.cardInset)
                    }
                    .frame(maxHeight: .infinity)
                    .dsCard()
                    
                    Spacer(minLength: DS.cardInset)
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
                .padding(.horizontal, 100)

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
        refreshResult = CatalogRefreshReport.summaryText(report.results)
    }
}

// MARK: - 모델 행

private struct ModelRow: View {
    let model: AIModel
    let isDefault: Bool
    let isEnabled: Bool
    let onToggleDefault: () -> Void
    let onToggleEnabled: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.provider.accentSwiftUIColor)
                    .frame(width: DS.dotStandard, height: DS.dotStandard)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(model.provider.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(model.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            HStack(spacing: 14) {
                if model.contextLimit > 0 {
                    Text("\(model.contextLimit / 1000)K")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button { onToggleDefault() } label: {
                    Image(systemName: isDefault ? "star.fill" : "star")
                        .foregroundStyle(isDefault ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(isDefault ? "기본 모델 해제" : "새 대화가 이 모델로 시작합니다")

                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { onToggleEnabled($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help("모델 피커 표시 여부")

                Button { onDelete() } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
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

    @State private var selectedEntry: ProviderEntry?
    @State private var modelID = ""
    @State private var displayName = ""
    @State private var contextLimit = "128000"
    @State private var customEndpoints: [CustomEndpoint] = []
    @State private var selectedEndpointID: UUID?

    var body: some View {
        VStack(spacing: 16) {
            Text("모델 추가")
                .font(.headline)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("공급자")
                        .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    TextField("예: gpt-4o", text: $modelID)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("표시 이름")
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    TextField("예: GPT-4o", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("컨텍스트 한도")
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    TextField("예: 128000", text: $contextLimit)
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
        if selectedEntry?.provider == .custom { return selectedEndpointID != nil }
        return true
    }

    private func addModel() {
        guard let limit = Int(contextLimit), let entry = selectedEntry else { return }
        let model: AIModel
        if entry.provider == .custom, let endpointID = selectedEndpointID,
           let endpoint = customEndpoints.first(where: { $0.id == endpointID }) {
            model = AIModel(
                id: CustomEndpoint.compositeID(endpointID: endpoint.id, modelID: modelID),
                provider: .custom,
                displayName: "\(displayName) (\(endpoint.name))",
                contextLimit: limit
            )
        } else {
            model = AIModel(
                id: modelID,
                provider: entry.provider,
                displayName: displayName,
                contextLimit: limit
            )
        }
        catalog.addModel(model)
    }
}

#Preview {
    SettingsView()
}
