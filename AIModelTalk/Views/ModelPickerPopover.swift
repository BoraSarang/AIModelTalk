import SwiftUI

// MARK: - 모델 선택 (커스텀 Popover)

struct ModelPickerPopover: View {
    @ObservedObject var viewModel: ChatViewModel

    @State private var modelSearchText = ""
    @State private var showModelPicker = false
    /// 엔트리 목록 — onAppear에서 1회 로드해 body 재평가마다 UserDefaults I/O를 피한다 (v0.2.2)
    @State private var cachedEntries: [ProviderEntry] = []

    private var privateEntries: [ProviderEntry] {
        cachedEntries.isEmpty ? ProviderEntry.currentList() : cachedEntries
    }

    var body: some View {
        Button {
            showModelPicker.toggle()
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(viewModel.selectedModel.provider.accentSwiftUIColor)
                    .frame(width: DS.dotStandard, height: DS.dotStandard)
                Text(viewModel.selectedModel.label)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showModelPicker) {
            pickerContent
        }
        .help(viewModel.selectedModel.label)
    }

    private var pickerContent: some View {
        let entries = privateEntries
        let fallbackID = entries.compactMap(\.endpoint).first?.id
        let query = modelSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return VStack(spacing: 0) {
            searchField
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    let visibleEntries = entries.filter { entry in
                        !(entry.provider == .appleIntelligence && !AppleIntelligenceSupport.modelAvailable)
                    }
                    let anyMatch = visibleEntries.contains { entry in
                        !enabledModels(in: entry, fallbackID: fallbackID, query: query).isEmpty
                    }
                    if !anyMatch && !modelSearchText.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("'\(modelSearchText)'에 일치하는 모델이 없습니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 16)
                    } else {
                        // 내장 공급자 + 커스텀 엔드포인트별 섹션 (v1.9 T-85)
                        ForEach(visibleEntries) { entry in
                            let providerModels = enabledModels(in: entry, fallbackID: fallbackID, query: query)
                            if !providerModels.isEmpty {
                                sectionHeader(entry.title)
                                ForEach(providerModels) { model in
                                    popoverRow(model)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 300, height: 320)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            if cachedEntries.isEmpty {
                cachedEntries = ProviderEntry.currentList()
            }
        }
    }

    /// 활성화(enabled)된 모델만 엔트리 단위로 조회 — modelsByEntryID O(1) 인덱스 재사용 + 무료 우선 (v0.2.2)
    private func enabledModels(in entry: ProviderEntry, fallbackID: UUID?, query: String) -> [AIModel] {
        let catalog = ModelCatalog.shared
        let visible = catalog.visibleModels(in: entry, fallbackFirstEndpointID: fallbackID)
        let filtered = query.isEmpty ? visible : visible.filter {
            $0.displayName.lowercased().contains(query) ||
            $0.id.lowercased().contains(query) ||
            $0.provider.rawValue.lowercased().contains(query)
        }
        return ModelCatalog.freeFirst(filtered)
    }

    /// 스킬 팝오버와 동일한 🔍아이콘 검색 박스 형태 (v3.7 T-165)
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("모델 검색", text: $modelSearchText)
                .textFieldStyle(.plain)
            if !modelSearchText.isEmpty {
                Button {
                    modelSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .quaternaryLabelColor))
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusControl))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(DS.sectionHeaderFill)
    }

    private func popoverRow(_ model: AIModel) -> some View {
        let isSel = model.id == viewModel.selectedModel.id
        let selColor = model.provider.accentSwiftUIColor
        let rawID = model.id.split(separator: "/").last.map(String.init) ?? model.id
        let rowLabel = rawID == model.displayName ? model.displayName : "\(model.displayName) (\(rawID))"
        return Button {
            viewModel.selectModel(model)
            modelSearchText = ""
            showModelPicker = false
        } label: {
            HStack(spacing: 8) {
                Text(isSel ? "✓" : "")
                    .font(.callout)
                    .frame(width: 16)
                Text(rowLabel)
                    .font(.callout)
                    .foregroundStyle(isSel ? selColor : .primary)
                    .fontWeight(isSel ? .semibold : .regular)
                Spacer()
                if model.supportsVision {
                    Image(systemName: "eye")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help("이미지(멀티모달) 지원 모델")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 행 전체를 클릭 영역으로 — 텍스트 글리프만 히트되던 문제 수정 (v2.1 사용자 피드백)
            .contentShape(Rectangle())
            .background(isSel ? selColor.opacity(0.15) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}
