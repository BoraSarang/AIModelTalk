import SwiftUI

/// 대화 내 병렬 모델 비교 진입점 (T-201)
///
/// "비교" 버튼 — 누르면 모델 선택 팝오버와 실행 버튼을 제공한다.
/// 선택한 모델들을 현재 대화 컨텍스트로 동시에 호출해 비교 오버레이를 연다.
struct CompareModelPickerButton: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        Button {
            // popover 열기 — 선택·실행은 팝오버 내부에서
            showPopover.toggle()
        } label: {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 14))
                .foregroundStyle(viewModel.isComparing ? Color.accentColor : Color.secondary)
                .background(viewModel.isComparing ? Color.accentColor.opacity(0.15) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            compareSelector
        }
        .help("병렬 모델 비교 — 같은 대화를 여러 모델에 동시 전송")
    }

    @State private var showPopover = false

    private var compareSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("모델별 나란히 비교")
                .font(.headline)
            Text("선택한 모델들에 같은 대화 컨텍스트를 보냅니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // 모델 선택 — 공급자별 메뉴 (ComparisonView 패턴 재사용)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    let entries = ProviderEntry.currentList()
                    let fallbackID = entries.compactMap(\.endpoint).first?.id
                    ForEach(entries) { entry in
                        let models = ModelCatalog.shared.models(in: entry, fallbackFirstEndpointID: fallbackID)
                        if !models.isEmpty {
                            Menu {
                                ForEach(models) { model in
                                    Button {
                                        toggle(model)
                                    } label: {
                                        if viewModel.selectedCompareModelIDs.contains(model.id) {
                                            Label(model.displayName, systemImage: "checkmark")
                                        } else {
                                            Text(model.displayName)
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color(hex: entry.colorHex) ?? .accentColor)
                                        .frame(width: 6, height: 6)
                                    Text("\(entry.title) (\(countFor(entry, fallbackID: fallbackID)))")
                                }
                            }
                            .menuStyle(.borderedButton)
                        }
                    }
                }
            }
            .frame(maxWidth: 320)

            // 온도 (T-202) — nil이면 공급자 기본값
            HStack(spacing: 6) {
                Text("temperature")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: temperatureBinding) {
                    Text("기본값").tag(Double?.none)
                    ForEach([0.0, 0.2, 0.5, 0.7, 1.0], id: \.self) { v in
                        Text(String(format: "%.1f", v)).tag(Double?.some(v))
                    }
                }
                .labelsHidden()
                .controlSize(.small)
            }

            Divider()
            HStack {
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

    private var temperatureBinding: Binding<Double?> {
        Binding(
            get: { viewModel.compareTemperature },
            set: { viewModel.compareTemperature = $0 }
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

    private func countFor(_ entry: ProviderEntry, fallbackID: UUID?) -> Int {
        ModelCatalog.shared.models(in: entry, fallbackFirstEndpointID: fallbackID)
            .filter { viewModel.selectedCompareModelIDs.contains($0.id) }.count
    }
}