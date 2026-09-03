import SwiftUI

struct BenchmarkView: View {
    @ObservedObject private var service = BenchmarkService.shared
    @ObservedObject private var catalog = ModelCatalog.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if service.rankedModels().isEmpty {
                emptyState
            } else {
                rankingTable
            }
        }
        .frame(minWidth: 560, minHeight: 400)
        .appAccentTint(settings.accentColor)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("모델 벤치마크 랭킹")
                    .font(.headline)
                Text("TTFT(첫 토큰 도달 시간) 기준 정렬 · 측정된 모델만 표시")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await service.benchmarkAll(models: configuredModels) }
            } label: {
                if service.isRunning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("전체 벤치마크", systemImage: "speedometer")
                }
            }
            .disabled(service.isRunning || configuredModels.isEmpty)
        }
        .padding(DS.windowInset)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "speedometer")
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)
            Text("아직 측정된 모델이 없습니다")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("「전체 벤치마크」를 눌러 측정을 시작하세요")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rankingTable: some View {
        Table(service.rankedModels(), selection: .constant(nil)) {
            TableColumn("#") { model in
                Text("\(rank(of: model))")
                    .foregroundStyle(rank(of: model) <= 3 ? Color.accentColor : Color.secondary)
                    .fontWeight(.semibold)
            }
            .width(30)

            TableColumn("공급자") { model in
                HStack(spacing: 4) {
                    dsDot(Color(model.provider.accentColor))
                    Text(model.provider.rawValue)
                }
            }
            .width(90)

            TableColumn("모델") { model in
                Text(model.displayName)
            }

            TableColumn("TTFT") { model in
                Text(formatMs(model.ttft))
                    .monospacedDigit()
            }
            .width(80)

            TableColumn("총 시간") { model in
                Text(formatMs(model.totalTime))
                    .monospacedDigit()
            }
            .width(80)

            TableColumn("") { model in
                if service.runningModelID == model.id {
                    ProgressView().controlSize(.small)
                } else {
                    Button("측정") {
                        Task { _ = await service.benchmark(model: model) }
                    }
                    .buttonStyle(.link)
                }
            }
            .width(50)
        }
    }

    // MARK: - 헬퍼
    private var configuredModels: [AIModel] {
        catalog.models.filter { model in
            ModelCatalog.shared.isEnabled(model) &&
            (!model.provider.isAutoDetected || !AppSettings.shared.apiKey(for: model.provider).isEmpty)
        }
    }

    private func rank(of model: AIModel) -> Int {
        (service.rankedModels().firstIndex(where: { $0.id == model.id && $0.provider == model.provider }) ?? 0) + 1
    }

    private func formatMs(_ interval: TimeInterval?) -> String {
        guard let t = interval else { return "-" }
        return String(format: "%.0fms", t * 1000)
    }
}

#Preview {
    BenchmarkView()
}