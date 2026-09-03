import SwiftUI

/// 대화 내 병렬 모델 비교 오버레이 (T-201)
///
/// ChatViewModel.runComparison()으로 같은 대화 컨텍스트를 여러 모델에 동시 발송한 결과를
/// 나란히(그리드) 표시한다. 각 래인에서 "이 답변으로 대화 계속"을 선택하면 해당 래인을
/// 세션의 어시스턴트 답변으로 채택한다.
struct CompareOverlayView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject private var service = ComparisonService.shared

    @State private var showSentPanel = false

    /// 어시스턴트 채택 대상 세션 — 현재 대화 세션
    private var sessionID: UUID { viewModel.currentSessionID ?? UUID() }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            resultsGrid
        }
        .padding(12)
        .background(.regularMaterial)
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.split.2x1.fill")
                .foregroundStyle(Color.accentColor)
            Text("병렬 모델 비교")
                .font(.headline)
            if service.isRunning {
                ProgressView().controlSize(.small)
                Text("답변 생성 중…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !service.results.isEmpty {
                Text("완료 — 결과 중 하나를 선택해 대화를 계속하세요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.compareParams.hasAny {
                Text(paramSummary)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            Button {
                showSentPanel.toggle()
            } label: {
                Label("무엇을 보냈나", systemImage: "doc.text.magnifyingglass")
                    .font(.caption2)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .popover(isPresented: $showSentPanel, arrowEdge: .top) {
                SentPayloadPanel(viewModel: viewModel, service: service)
            }
            Button("취소") {
                viewModel.cancelComparison()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    /// 설정된 파라미터 한 줄 요약 (T-202)
    private var paramSummary: String {
        var parts: [String] = []
        if let t = viewModel.compareParams.temperature { parts.append(String(format: "T %.1f", t)) }
        if let p = viewModel.compareParams.topP { parts.append(String(format: "topP %.1f", p)) }
        if let m = viewModel.compareParams.maxTokens { parts.append("maxTokens \(m)") }
        return parts.joined(separator: " · ")
    }

    private var resultsGrid: some View {
        ScrollView {
            if service.results.isEmpty {
                Text("모델을 선택하고 비교를 시작하세요")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 40)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 300), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(Array(service.results.enumerated()), id: \.element.id) { index, result in
                        compareLane(index: index, result: result)
                    }
                }
                .padding(.top, 10)
            }
        }
    }

    private func compareLane(index: Int, result: ComparisonResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                dsDot(Color(result.model.provider.accentColor))
                Text(result.model.displayName)
                    .font(.caption.bold())
                    .lineLimit(1)
                Text(result.model.provider.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let ttft = result.ttft {
                    Text(String(format: "%.0fms", ttft * 1000))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            metricsLine(result: result)

            Group {
                if let error = result.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if result.isStreaming && result.text.isEmpty {
                    TypingIndicatorView()
                        .padding(.vertical, 6)
                } else {
                    MarkdownRenderer(text: result.text, isStreaming: result.isStreaming, fixedHeight: 220)
                }
            }
            .frame(height: 220, alignment: .top)

            if !result.isStreaming, result.error == nil {
                Button {
                    viewModel.adoptCompareLane(index: index, in: sessionID)
                } label: {
                    Label("이 답변으로 대화 계속", systemImage: "checkmark.circle")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: DS.radiusCard).fill(.quaternary.opacity(0.2)))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusCard).strokeBorder(Color.accentColor.opacity(0.3)))
    }

    private func metricsLine(result: ComparisonResult) -> some View {
        HStack(spacing: 10) {
            if let total = result.totalTime {
                Label(String(format: "%.1fs", total), systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let tps = result.tokensPerSecond {
                Text(String(format: "%.1f tok/s", tps))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .help("실측 완료 토큰 ÷ 총 응답 시간")
            }
            if let pt = result.promptTokens.map({ SessionTokens.compact($0) }),
               let ct = result.completionTokens.map({ SessionTokens.compact($0) }) {
                Label("\(pt)/\(ct)", systemImage: "arrow.up.arrow.down")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .help("실측 토큰 프롬프트/완료")
            }
            if result.answerLength > 0 {
                Text("\(result.answerLength)자")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

/// "무엇을 보냈는지" 투명 패널 (T-202) — 파라미터·실측 토큰·시스템 프롬프트를 한눈에 표시
private struct SentPayloadPanel: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var service: ComparisonService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("보낸 요청 정보")
                .font(.headline)

            // 공통 파라미터 — 전부 기본값이면 "공급자 기본값 사용"
            let p = viewModel.compareParams
            Text(parameterText(p))
                .font(.caption)
                .monospacedDigit()

            Divider()

            // 시스템 프롬프트 — 채팅을 발송한 컨텍스트의 시스템 프롬프트 (비밀 아닌 부분만)
            Text("시스템 프롬프트")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(systemPromptPreview)
                .font(.caption2)
                .foregroundStyle(.primary)
                .frame(maxWidth: 320, alignment: .leading)
                .textSelection(.enabled)

            Divider()

            // 래인별 실측 토큰
            Text("래인별 사용량")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(service.results) { result in
                let pt = result.promptTokens.map { SessionTokens.compact($0) } ?? "—"
                let ct = result.completionTokens.map { SessionTokens.compact($0) } ?? "—"
                let t = result.totalTime.map { String(format: "%.1fs", $0) } ?? "…"
                HStack {
                    Text(result.model.displayName)
                        .font(.caption2)
                        .lineLimit(1)
                    Spacer()
                    Text("\(pt)/\(ct)")
                        .font(.caption2)
                        .monospacedDigit()
                    Text(t)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private func parameterText(_ p: ModelParams) -> String {
        var parts: [String] = []
        if let t = p.temperature { parts.append(String(format: "temperature %.1f", t)) }
        if let top = p.topP { parts.append(String(format: "topP %.1f", top)) }
        if let m = p.maxTokens { parts.append("maxTokens \(m)") }
        return parts.isEmpty ? "파라미터: 공급자 기본값" : "파라미터: " + parts.joined(separator: " · ")
    }

    /// 시스템 프롬프트 — 발송 컨텍스트 재구성의 일부만 요약 표시 (과다 노출 방지)
    private var systemPromptPreview: String {
        let p = viewModel.buildSystemPrompt()
        return p.isEmpty ? "(없음)" : String(p.prefix(400))
    }
}