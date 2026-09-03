import SwiftUI

/// 대화 내 병렬 모델 비교 진입점 (T-201)
///
/// "비교" 버튼 — 누르면 모델 선택 팝오버와 실행 버튼을 제공한다.
/// 선택한 모델들을 현재 대화 컨텍스트로 동시에 호출해 비교 오버레이를 연다.
struct CompareModelPickerButton: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            Image(systemName: viewModel.isComparing ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                .font(.system(size: 14))
                .foregroundStyle(viewModel.isComparing ? Color.accentColor : Color.secondary)
                .frame(minWidth: 22, minHeight: 22)
                .contentShape(Rectangle())
                .background(hovered ? Color.accentColor.opacity(0.15) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { hovered = hovering }
        }
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            compareSelector
        }
        .help("병렬 모델 비교 — 같은 대화를 여러 모델에 동시 전송")
    }

    @State private var showPopover = false
    @State private var hovered = false

    private var compareSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("모델별 나란히 비교")
                .font(.headline)
            Text("행을 클릭해 선택/해제. 여러 모델에 같은 대화 컨텍스트를 보냅니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // 모델 선택 — 공급자 섹션별 토글 리스트 (행 클릭 = 선택/해제)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    let entries = ProviderEntry.currentList()
                    let fallbackID = entries.compactMap(\.endpoint).first?.id
                    ForEach(entries) { entry in
                        let models = ModelCatalog.shared.visibleModels(in: entry, fallbackFirstEndpointID: fallbackID)
                        if !models.isEmpty {
                            section(entry: entry, models: models)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: 320, maxHeight: 240)

            // 모델 파라미터 (T-202) — 전부 기본값이면 공급자 기본값
            VStack(alignment: .leading, spacing: 6) {
                Text("모델 파라미터")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text("temperature")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Picker("", selection: tempBinding) {
                        Text("기본값").tag(Double?.none)
                        ForEach([0.0, 0.2, 0.5, 0.7, 1.0], id: \.self) { v in
                            Text(String(format: "%.1f", v)).tag(Double?.some(v))
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                }
                HStack(spacing: 6) {
                    Text("topP")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Picker("", selection: topPBinding) {
                        Text("기본값").tag(Double?.none)
                        ForEach([0.5, 0.8, 0.9, 1.0], id: \.self) { v in
                            Text(String(format: "%.1f", v)).tag(Double?.some(v))
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                }
                HStack(spacing: 6) {
                    Text("maxTokens")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Picker("", selection: maxTokensBinding) {
                        Text("기본값").tag(Int?.none)
                        ForEach([512, 1024, 2048, 4096], id: \.self) { v in
                            Text("\(v)").tag(Int?.some(v))
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                }
            }

            Divider()
            HStack {
                Text("\(viewModel.selectedCompareModelIDs.count)개 선택")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("취소") { viewModel.cancelComparison() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    startCompare()
                } label: {
                    Label("비교 실행", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.selectedCompareModelIDs.isEmpty)
            }
        }
        .padding(14)
        .frame(width: 360)
    }

    /// 공급자 섹션 — 헤더 + 모델 행(클릭 토글)
    private func section(entry: ProviderEntry, models: [AIModel]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(hex: entry.colorHex) ?? .accentColor)
                    .frame(width: 7, height: 7)
                Text(entry.title)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            ForEach(models) { model in
                Button {
                    toggle(model)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.selectedCompareModelIDs.contains(model.id) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(viewModel.selectedCompareModelIDs.contains(model.id) ? Color.accentColor : Color.secondary)
                        Text(model.displayName)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var tempBinding: Binding<Double?> {
        Binding(
            get: { viewModel.compareParams.temperature },
            set: { viewModel.compareParams.temperature = $0 }
        )
    }

    private var topPBinding: Binding<Double?> {
        Binding(
            get: { viewModel.compareParams.topP },
            set: { viewModel.compareParams.topP = $0 }
        )
    }

    private var maxTokensBinding: Binding<Int?> {
        Binding(
            get: { viewModel.compareParams.maxTokens },
            set: { viewModel.compareParams.maxTokens = $0 }
        )
    }

    private func startCompare() {
        guard let sessionID = viewModel.currentSessionID else { return }
        viewModel.runComparison(in: sessionID)
        showPopover = false
    }

    private func toggle(_ model: AIModel) {
        if viewModel.selectedCompareModelIDs.contains(model.id) {
            viewModel.selectedCompareModelIDs.remove(model.id)
        } else {
            viewModel.selectedCompareModelIDs.insert(model.id)
        }
    }
}