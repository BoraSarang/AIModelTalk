import SwiftUI

/// 대화 내 병렬 모델 비교 진입점 (T-201)
///
/// "비교" 버튼 — 누르면 모델 선택 팝오버와 실행 버튼을 제공한다.
/// 선택한 모델들을 현재 대화 컨텍스트로 동시에 호출해 비교 오버레이를 연다.
///
/// 팝오버 내용물은 별도 `CompareSelectorView`로 분리해, macOS 팝오버에서
/// 호스트 뷰의 @ObservedObject 구독이 끊어져 행 선택 아이콘이 안 갱신되는
/// 문제(v0.2.2)를 회피한다.
struct CompareModelPickerButton: View {
    @ObservedObject var viewModel: ChatViewModel
    /// 외부(⋯ 더보기 메뉴)에서 팝오버 열림 제어 — 내부 버튼과 공유된다
    @Binding var isPresented: Bool
    @State private var hovered = false

    init(viewModel: ChatViewModel, isPresented: Binding<Bool> = .constant(false)) {
        self.viewModel = viewModel
        self._isPresented = isPresented
    }

    var body: some View {
        Button {
            isPresented.toggle()
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
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            CompareSelectorView(viewModel: viewModel, isPresented: $isPresented)
        }
        .help("병렬 모델 비교 — 같은 대화를 여러 모델에 동시 전송")
    }
}

/// 비교 팝오버 내용물 — 독립 View로 두어 @Published(selectedCompareModelIDs) 변경을
/// 행 아이콘에 즉시 반영한다. (v0.2.2)
struct CompareSelectorView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("모델별 나란히 비교")
                .font(.headline)
            Text("행을 클릭해 선택/해제. 2개 이상 선택해야 실행됩니다. 현재 채팅 모델은 제외.")
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
                HStack(alignment: .firstTextBaseline) {
                    Text("temperature")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Picker("", selection: tempBinding) {
                        Text("기본값").tag(Double?.none)
                        ForEach([0.0, 0.2, 0.5, 0.7, 1.0], id: \.self) { v in
                            Text(String(format: "%.1f", v)).tag(Double?.some(v))
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("topP")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Picker("", selection: topPBinding) {
                        Text("기본값").tag(Double?.none)
                        ForEach([0.5, 0.8, 0.9, 1.0], id: \.self) { v in
                            Text(String(format: "%.1f", v)).tag(Double?.some(v))
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("maxTokens")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                let count = viewModel.selectedCompareModelIDs.count
                HStack(spacing: 6) {
                    Text("\(count)")
                        .font(.callout.bold())
                        .foregroundStyle(count >= 2 ? Color.accentColor : Color.orange)
                    Text(count >= 2 ? "개 모델 선택됨" : "개 선택 — 2개 이상 필요")
                        .font(.caption2)
                        .foregroundStyle(count >= 2 ? Color.secondary : Color.orange)
                }
                Spacer()
                Button {
                    startCompare()
                } label: {
                    Label("비교 실행", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(count < 2)
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
                row(for: model)
            }
        }
    }

    /// 모델 행 — 선택 여부를 배경 하이라이트 + 체크 아이콘으로 뚜렷이 구분 (v0.2.2)
    private func row(for model: AIModel) -> some View {
        let isCurrent = model.id == viewModel.selectedModel.id && model.provider == viewModel.selectedModel.provider
        let isSelected = !isCurrent && viewModel.selectedCompareModelIDs.contains(model.id)
        return Button {
            toggle(model)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : (isCurrent ? "arrow.left.circle" : "circle"))
                    .font(.system(size: 14, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : (isCurrent ? Color.secondary.opacity(0.6) : Color.secondary.opacity(0.8)))
                Text(model.displayName)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.accentColor : (isCurrent ? Color.secondary : Color.primary))
                    .lineLimit(1)
                if isCurrent {
                    Text("현재 채팅")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if isSelected {
                    Text("선택됨")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
        .help(isCurrent ? "현재 채팅 중인 모델은 비교 대상으로 선택할 수 없습니다" : "")
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
        guard viewModel.selectedCompareModelIDs.count >= 2 else { return }
        guard let sessionID = viewModel.currentSessionID else { return }
        viewModel.runComparison(in: sessionID)
        isPresented = false
    }

    private func toggle(_ model: AIModel) {
        // 현재 채팅 중인 모델은 비교 대상에서 제외 (v0.2.2)
        if model.id == viewModel.selectedModel.id && model.provider == viewModel.selectedModel.provider {
            return
        }
        if viewModel.selectedCompareModelIDs.contains(model.id) {
            viewModel.selectedCompareModelIDs.remove(model.id)
        } else {
            viewModel.selectedCompareModelIDs.insert(model.id)
        }
    }
}