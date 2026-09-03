import SwiftUI

struct ComparisonView: View {
    @ObservedObject private var service = ComparisonService.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var selectedModelIDs: Set<String> = []

    private var selectedModels: [AIModel] {
        ModelCatalog.shared.models.filter { selectedModelIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            modelSelector
            Divider()
            questionBar
            Divider()
            resultsArea
        }
        .frame(minWidth: 820, minHeight: 560)
        .appAccentTint(settings.accentColor)
    }

    // MARK: - 모델 선택
    private var modelSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("비교할 모델 선택 (2개 이상 권장)")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // 내장 공급자 + 커스텀 엔드포인트별 메뉴 (v1.9 T-85)
                    let entries = ProviderEntry.currentList()
                    let fallbackID = entries.compactMap(\.endpoint).first?.id
                    ForEach(entries) { entry in
                        let models = ModelCatalog.freeFirst(ModelCatalog.shared.visibleModels(in: entry, fallbackFirstEndpointID: fallbackID))
                        if !models.isEmpty {
                            Menu {
                                ForEach(models) { model in
                                    Button {
                                        toggle(model)
                                    } label: {
                                        if selectedModelIDs.contains(model.id) {
                                            Label(model.displayName, systemImage: "checkmark")
                                        } else {
                                            Text(model.displayName)
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    dsDot(Color(hex: entry.colorHex) ?? .accentColor)
                                    Text("\(entry.title) (\(countFor(entry, fallbackID: fallbackID)))")
                                }
                            }
                            .menuStyle(.borderedButton)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(DS.windowInset)
    }

    // MARK: - 질문 입력
    private var questionBar: some View {
        HStack(spacing: 10) {
            TextField("모든 모델에 같은 질문을 보냅니다", text: $service.question)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await service.run(models: selectedModels) } }

            Button("비교 실행") {
                Task { await service.run(models: selectedModels) }
            }
            .disabled(service.isRunning || selectedModels.isEmpty || service.question.trimmingCharacters(in: .whitespaces).isEmpty)

            if service.isRunning {
                ProgressView().controlSize(.small)
            }
        }
        .padding(DS.windowInset)
    }

    // MARK: - 결과
    /// 반응형 격자 — 창 폭에 맞춰 자동 줄바꿈, 4개 선택 시에도 전부 표시 (v1.9 T-86)
    /// 상단에 루브릭 비교 리포트 카드 (v1.9 T-87)
    private var resultsArea: some View {
        ScrollView {
            if service.results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 36))
                        .foregroundStyle(.quaternary)
                    Text("모델을 선택하고 질문을 입력하세요")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 100)
            } else {
                VStack(spacing: 12) {
                    // 루브릭 리포트 — 격자 위 전체 폭 카드
                    if AppSettings.shared.showJudgeSummary || !service.reportScores.isEmpty {
                        reportCard
                            .padding(.horizontal)
                            .padding(.top, 12)
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 340), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(service.results) { result in
                            ResultColumnView(result: result)
                        }
                    }
                    .padding(DS.windowInset)

                    if !service.judgeSummary.isEmpty || service.isJudging {
                        judgeCard
                            .padding(.horizontal)
                            .padding(.bottom)
                    } else {
                        Color.clear.frame(height: 12)
                    }
                }
            }
        }
    }

    // MARK: - 비교 리포트 카드 (v1.9 T-87)

    /// 순위 정렬된 행 + 실측 바 + 루브릭 칩. 채점 전엔 메트릭만, 채점 후 점수가 붙는다.
    private var reportCard: some View {
        let entries = ComparisonService.rankedEntries(service.results, scores: service.reportScores)
        let maxTotal = service.results.compactMap { $0.error == nil ? $0.totalTime : nil }.max() ?? 1

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("비교 리포트", systemImage: "chart.bar.xaxis")
                    .font(.headline)
                Spacer()
                if service.isJudging {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("루브릭 채점 중…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !service.reportScores.isEmpty {
                    Text("루브릭 · 10점 만점")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            ForEach(entries.indices, id: \.self) { i in
                let entry = entries[i]
                reportRow(rank: i, candidateIndex: entry.index, result: entry.result, maxTotal: maxTotal)
                if i < entries.count - 1 {
                    Divider()
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: DS.radiusCard).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusCard).strokeBorder(Color.accentColor.opacity(0.3)))
    }

    @ViewBuilder
    private func reportRow(rank: Int, candidateIndex: Int, result: ComparisonResult, maxTotal: Double) -> some View {
        let score = ComparisonService.scoreFor(result, index: candidateIndex, scores: service.reportScores)
        let isWinner = isWinnerRow(result, score: score)

        HStack(alignment: .top, spacing: 12) {
            rankBadge(index: rank, winner: isWinner)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    dsDot(Color(result.model.provider.accentColor))
                    Text(result.model.displayName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    // 공급자 구분 — 동명 모델이 여러 공급자에 있을 수 있음 (v1.9 T-88)
                    Text("· \(originName(result))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if result.error != nil {
                        Text("응답 실패")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }

                metricsLine(result: result, maxTotal: maxTotal)

                if let score {
                    chipsRow(score)
                    if !score.comment.isEmpty {
                        Text(score.comment)
                            .font(.caption)
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    /// 공급자 표시명 — 커스텀은 소속 엔드포인트 이름 우선 (v1.9 T-88)
    private func originName(_ result: ComparisonResult) -> String {
        if result.model.provider == .custom,
           let endpointID = result.model.customEndpointID,
           let endpoint = CustomEndpointStore(defaults: CustomEndpointStore.suiteDefaults).endpoints.first(where: { $0.id == endpointID }) {
            return endpoint.name
        }
        return result.model.provider.rawValue
    }

    /// 승자 판정 — 판정 지정 우선, 없으면 정렬상 최고 점수(첫 행), 채점 전엔 최단 시간
    private func isWinnerRow(_ result: ComparisonResult, score: JudgeScore?) -> Bool {
        if !service.reportScores.isEmpty {
            if let winner = service.winnerName, !winner.isEmpty {
                return winner == result.model.displayName
            }
            return ComparisonService.rankedEntries(service.results, scores: service.reportScores)
                .first?.result.id == result.id
        }
        guard result.error == nil,
              let total = result.totalTime,
              let fastest = service.results.compactMap({ $0.error == nil ? $0.totalTime : nil }).min() else { return false }
        return abs(total - fastest) < 0.001 && service.results.count > 1
    }

    @ViewBuilder
    private func rankBadge(index: Int, winner: Bool) -> some View {
        ZStack {
            Circle()
                .fill(winner ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondary.opacity(0.15)))
                .frame(width: 26, height: 26)
            if winner {
                Image(systemName: "crown.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
            } else {
                Text("\(index + 1)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
        }
        .help(winner ? "종합 1위" : "\(index + 1)위")
    }

    @ViewBuilder
    private func metricsLine(result: ComparisonResult, maxTotal: Double) -> some View {
        HStack(spacing: 10) {
            if let ttft = result.ttft {
                Label(String(format: "%.0fms", ttft * 1000), systemImage: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .help("첫 응답까지(TTFT)")
            }
            if let total = result.totalTime {
                Label(String(format: "%.1fs", total), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .help("전체 응답 시간")
                speedBar(fraction: speedFraction(total))
            }
            if result.answerLength > 0 {
                Label("\(result.answerLength)자", systemImage: "textformat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if result.ttft == nil && result.totalTime == nil && result.error == nil {
                Text("응답 대기 중…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// 속도 바 — 가장 빠른 성공 답변이 꽉 찬다 (빠를수록 길게)
    @ViewBuilder
    private func speedBar(fraction: Double) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 64, height: 5)
            Capsule()
                .fill(Color.accentColor.opacity(0.8))
                .frame(width: max(4, 64 * fraction), height: 5)
        }
        .help("상대 속도 — 길수록 빠름")
    }

    private func speedFraction(_ total: Double) -> Double {
        let fastest = service.results.compactMap { $0.error == nil ? $0.totalTime : nil }.min() ?? total
        guard total > 0 else { return 0 }
        // 최단 시간 = 1.0, 3배 이상 느리면 ≈ 0.33 하한
        return min(1, max(0.15, fastest / total))
    }

    @ViewBuilder
    private func chipsRow(_ score: JudgeScore) -> some View {
        HStack(spacing: 6) {
            chip("정", score.accuracy, "정확성")
            chip("명", score.clarity, "명확성")
            chip("깊", score.depth, "깊이")
            chip("한", score.koreanFluency, "한국어 자연스러움")
            chip("속", score.speedFeel, "속도 체감")
            chip("종합", score.overall, "종합", emphasized: true)
        }
    }

    private func chip(_ label: String, _ value: Double, _ name: String, emphasized: Bool = false) -> some View {
        let text = value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
        return Text("\(label) \(text)")
            .font(.caption2)
            .fontWeight(emphasized ? .semibold : .regular)
            .monospacedDigit()
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(emphasized ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
            )
            .foregroundStyle(emphasized ? Color.accentColor : Color.primary)
            .help("\(name): \(String(format: "%.1f", value))/10")
    }

    private var judgeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("판정 모델 요약", systemImage: "scalemass")
                    .font(.headline)
                Spacer()
                if service.isJudging {
                    ProgressView().controlSize(.small)
                }
            }
            MarkdownRenderer(text: service.judgeSummary.isEmpty ? "요약 생성 중…" : service.judgeSummary)
                .font(.system(size: 13))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: DS.radiusCard).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusCard).strokeBorder(Color.accentColor.opacity(0.3)))
    }

    // MARK: - 헬퍼
    private func toggle(_ model: AIModel) {
        if selectedModelIDs.contains(model.id) {
            selectedModelIDs.remove(model.id)
        } else {
            selectedModelIDs.insert(model.id)
        }
    }

    private func countFor(_ entry: ProviderEntry, fallbackID: UUID?) -> Int {
        ModelCatalog.shared.visibleModels(in: entry, fallbackFirstEndpointID: fallbackID)
            .filter { selectedModelIDs.contains($0.id) }.count
    }
}

// MARK: - 개별 결과 컬럼

struct ResultColumnView: View {
    let result: ComparisonResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                dsDot(Color(result.model.provider.accentColor))
                Text(result.model.provider.rawValue)
                    .font(.caption).fontWeight(.medium)
                Text(result.model.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if let ttft = result.ttft {
                    Text(String(format: "%.0fms", ttft * 1000))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                // 실측 토큰 칩 (v1.9 T-78 완결)
                if let pt = result.promptTokens.map({ SessionTokens.compact($0) }),
                   let ct = result.completionTokens.map({ SessionTokens.compact($0) }) {
                    Label("\(pt)/\(ct)", systemImage: "arrow.up.arrow.down")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .help("실측 토큰 프롬프트/완료")
                }
            }

            // 웹 문서 자체 스크롤 모드 — 중첩 ScrollView 이벤트 충돌 해소 (v1.9 T-89)
            // 고정 높이로 카드 높이 정렬 유지 (T-86)
            Group {
                if let error = result.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(4)
                } else if result.isStreaming && result.text.isEmpty {
                    TypingIndicatorView()
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                } else {
                    MarkdownRenderer(text: result.text, isStreaming: result.isStreaming, fixedHeight: 320)
                }
            }
            .frame(height: 320, alignment: .top)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: DS.radiusCard).fill(.regularMaterial))
    }
}

#Preview {
    ComparisonView()
}