import SwiftUI

/// 평가(Eval) 그리드 (v0.2.0 T-203)
/// 프롬프트×모델 매트릭스를 병렬로 실행해 셀별 TTFT·tok/s·점수(1~10)·회귀를 보여주고,
/// CSV/Markdown으로 내보낼 수 있다.
struct EvalView: View {
    @ObservedObject private var service = EvalService.shared
    @ObservedObject private var catalog = ModelCatalog.shared
    @ObservedObject private var settings = AppSettings.shared

    @State private var newPrompt = ""
    @State private var showingExport = false
    @State private var sortKey: EvalService.SortKey = .model
    @State private var filterModelID: String? = nil
    @State private var filterKeyword = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            promptEditor
            Divider()
            modelSelector
            Divider()
            gridArea
        }
        .frame(minWidth: 720, minHeight: 500)
        .appAccentTint(settings.accentColor)
        .sheet(isPresented: $showingExport) {
            exportSheet
        }
    }

    // MARK: - 헤더

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("모델 평가 그리드")
                    .font(.headline)
                Text("프롬프트 × 모델 매트릭스 · 5-at-a-time 병렬 · 셀별 점수(1~10) · 회귀 추적")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                service.run()
            } label: {
                if service.isRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Label("평가 실행", systemImage: "play.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(service.isRunning || service.selectedModelIDs.isEmpty || service.prompts.isEmpty)
            Button("내보내기") {
                showingExport = true
            }
            .buttonStyle(.bordered)
            .disabled(service.cells.isEmpty)
        }
        .padding(DS.windowInset)
    }

    // MARK: - 프롬프트 리스트 편집

    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("프롬프트")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("한 줄 프롬프트 입력 후 추가", text: $newPrompt)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .onSubmit { addPrompt() }
                Button("추가", action: addPrompt)
                    .controlSize(.small)
                    .disabled(newPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(service.prompts.enumerated()), id: \.element) { index, prompt in
                        PromptChip(text: prompt) {
                            service.removePrompt(at: index)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, DS.windowInset)
        .padding(.bottom, 6)
    }

    private func addPrompt() {
        service.addPrompt(newPrompt)
        newPrompt = ""
    }

    // MARK: - 모델 선택

    private var modelSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("모델")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                modelToggleAll
                ForEach(visibleModels) { model in
                    ModelChip(model: model, selected: service.selectedModelIDs.contains(model.id)) {
                        toggle(model)
                    }
                }
                Spacer()
            }
        }
        .padding(.horizontal, DS.windowInset)
        .padding(.bottom, 8)
    }

    private var visibleModels: [AIModel] {
        catalog.models.filter { ModelCatalog.shared.isEnabled($0) }
    }

    private var modelToggleAll: some View {
        Button {
            if service.selectedModelIDs.count == visibleModels.count {
                service.selectedModelIDs = []
            } else {
                service.selectedModelIDs = Set(visibleModels.map(\.id))
            }
        } label: {
            Text(service.selectedModelIDs.count == visibleModels.count ? "전체 해제" : "전체 선택")
                .font(.caption2)
        }
        .buttonStyle(.borderless)
        .disabled(visibleModels.isEmpty)
    }

    private func toggle(_ model: AIModel) {
        if service.selectedModelIDs.contains(model.id) {
            service.selectedModelIDs.remove(model.id)
        } else {
            service.selectedModelIDs.insert(model.id)
        }
    }

    // MARK: - 그리드

    private var gridArea: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Picker("정렬", selection: $sortKey) {
                    Text("모델").tag(EvalService.SortKey.model)
                    Text("TTFT").tag(EvalService.SortKey.ttft)
                    Text("tok/s").tag(EvalService.SortKey.tokensPerSecond)
                    Text("점수").tag(EvalService.SortKey.score)
                    Text("프롬프트").tag(EvalService.SortKey.prompt)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                TextField("프롬프트 필터…", text: $filterKeyword)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(maxWidth: 180)
                Spacer()
                if service.history.count > 1 {
                    Text("이전 실행과 비교 표시")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Button("내역 지우기") {
                    service.clearHistory()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(service.history.isEmpty)
            }

            if service.cells.isEmpty {
                emptyState
            } else {
                gridTable
            }
        }
        .padding(.horizontal, DS.windowInset)
        .padding(.bottom, DS.windowInset)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tablecells")
                .font(.system(size: 32))
                .foregroundStyle(.quaternary)
            Text("프롬프트와 모델을 선택하고 「평가 실행」을 누르세요")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gridTable: some View {
        let filtered = service.filteredCells(
            filter: EvalService.EvalFilter(modelID: filterModelID, promptContains: filterKeyword),
            sort: sortKey)
        return ScrollView(.vertical) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                ForEach(filtered) { cell in
                    evalCell(cell)
                }
            }
            .padding(.top, 4)
        }
    }

    private func evalCell(_ cell: EvalCell) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // 상단: 모델명 + 상태
            HStack(spacing: 4) {
                dsDot(Color(cell.model.provider.accentColor))
                Text(cell.model.displayName)
                    .font(.caption.bold())
                    .lineLimit(1)
                Spacer()
                stateBadge(cell.state)
            }
            // 프롬프트
            Text(cell.prompt)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(cell.prompt)

            // 상태별 본문
            switch cell.state {
            case .idle:
                Text("대기")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            case .run:
                TypingIndicatorView()
                    .frame(height: 28)
            case .failed(let reason):
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            case .done:
                metricsRow(cell)
                Text(cell.text.prefix(120))
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
            }

            // 점수 + 회귀 (완료 셀만)
            if cell.state.isDone || cell.state.isFailed {
                scoreRow(cell)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: DS.radiusCard).fill(.quaternary.opacity(0.15)))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusCard).strokeBorder(
            cell.state.isFailed ? Color.red.opacity(0.4) : Color.accentColor.opacity(0.25)))
    }

    private func stateBadge(_ state: EvalCell.EvalState) -> some View {
        let (text, color): (String, Color) = {
            switch state {
            case .idle: return ("대기", .secondary)
            case .run: return ("…", .accentColor)
            case .done: return ("✓", .green)
            case .failed: return ("!", .red)
            }
        }()
        return Text(text)
            .font(.caption2.bold())
            .foregroundStyle(color)
    }

    private func metricsRow(_ cell: EvalCell) -> some View {
        HStack(spacing: 6) {
            if let ttft = cell.ttft {
                Text(String(format: "%.0fms", ttft * 1000))
                    .font(.caption2)
                    .monospacedDigit()
                    .help("첫 토큰 도달")
            }
            if let total = cell.totalTime {
                Text(String(format: "%.1fs", total))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if let tps = cell.tokensPerSecond {
                Text("\(String(format: "%.1f", tps)) tok/s")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .help("완료 토큰 ÷ 총 시간")
            }
            Spacer()
        }
    }

    private func scoreRow(_ cell: EvalCell) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("점수")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { service.scores[cell.id] },
                    set: { service.setScore(cellID: cell.id, value: $0) }
                )) {
                    Text("·").tag(Int?.none)
                    ForEach(1...10, id: \.self) { v in
                        Text("\(v)").tag(Int?.some(v))
                    }
                }
                .labelsHidden()
                .controlSize(.mini)
            }
            // 회귀 — 이전 실행 대비 (더 낮아지면 경고)
            if let prev = service.previousScore(prompt: cell.prompt, model: cell.model),
               let cur = service.scores[cell.id] {
                let delta = cur - prev
                regressionCaption(current: cur, previous: prev, delta: delta)
            }
        }
    }

    private func regressionCaption(current: Int, previous: Int, delta: Int) -> some View {
        Group {
            if delta < 0 {
                Label("회귀 \(current - previous)점 (이전 \(previous)점)", systemImage: "arrow.down")
                    .foregroundStyle(.orange)
            } else if delta > 0 {
                Label("\(delta)점 상승 (이전 \(previous)점)", systemImage: "arrow.up")
                    .foregroundStyle(.green)
            } else {
                Text("이전과 동일 (\(previous)점)")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
    }

    // MARK: - 내보내기

    private var exportSheet: some View {
        EvaluatorExportView(service: service)
    }
}

/// 프롬프트 칩 (제거 버튼 포함)
private struct PromptChip: View {
    let text: String
    let onRemove: () -> Void
    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption2)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(.quaternary.opacity(0.25)))
    }
}

/// 모델 칩 (토글)
private struct ModelChip: View {
    let model: AIModel
    let selected: Bool
    let onToggle: () -> Void
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 4) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                dsDot(Color(model.provider.accentColor))
                Text(model.displayName)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.2)))
            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(selected ? 0.4 : 0)))
        }
        .buttonStyle(.plain)
    }
}

/// 내보내기 시트 — CSV/Markdown 미리보기 + 저장
private struct EvaluatorExportView: View {
    @ObservedObject var service: EvalService
    @Environment(\.dismiss) private var dismiss
    @State private var format: ExportFormat = .csv

    enum ExportFormat: String, CaseIterable {
        case csv = "CSV"
        case markdown = "Markdown"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("결과 내보내기")
                    .font(.headline)
                Spacer()
                Picker("형식", selection: $format) {
                    ForEach(ExportFormat.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            TextEditor(text: .constant(content))
                .font(.system(.caption2, design: .monospaced))
                .frame(height: 260)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            HStack {
                Button("복사") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content, forType: .string)
                }
                .buttonStyle(.bordered)
                Button("파일로 저장…") {
                    saveToFile()
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Button("닫기") { dismiss() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(width: 560, height: 420)
    }

    private var content: String {
        switch format {
        case .csv: return service.exportCSV()
        case .markdown: return service.exportMarkdown()
        }
    }

    private func saveToFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = format == .csv ? "eval.csv" : "eval.md"
        panel.allowedContentTypes = [format == .csv ? .commaSeparatedText : .plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

#Preview {
    EvalView()
}