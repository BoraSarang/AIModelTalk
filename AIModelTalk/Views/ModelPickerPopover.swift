import SwiftUI

// MARK: - 모델 선택 (커스텀 Popover)

struct ModelPickerPopover: View {
    @ObservedObject var viewModel: ChatViewModel

    @State private var modelSearchText = ""
    @State private var showModelPicker = false

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
        VStack(spacing: 0) {
            searchField
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    if filteredModels().isEmpty && !modelSearchText.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("'\(modelSearchText)'에 일치하는 모델이 없습니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 16)
                    } else {
                        // 내장 공급자 + 커스텀 엔드포인트별 섹션 (v1.9 T-85)
                        let entries = ProviderEntry.currentList()
                        let fallbackID = entries.compactMap(\.endpoint).first?.id
                        ForEach(entries) { entry in
                            // 미지원 환경의 Apple Intelligence 섹션 숨김 (v2.1 T-102)
                            if entry.provider == .appleIntelligence && !AppleIntelligenceSupport.modelAvailable {
                                EmptyView()
                            } else {
                                let providerModels = ModelCatalog.freeFirst(filteredModels().filter { $0.belongs(to: entry, fallbackFirstEndpointID: fallbackID) })
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
        }
        .frame(width: 300, height: 320)
        .background(Color(nsColor: .controlBackgroundColor))
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

    private func filteredModels() -> [AIModel] {
        let all = ModelCatalog.shared.models.filter { ModelCatalog.shared.isEnabled($0) }
        let query = modelSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.displayName.lowercased().contains(query) ||
            $0.id.lowercased().contains(query) ||
            $0.provider.rawValue.lowercased().contains(query)
        }
    }
}
