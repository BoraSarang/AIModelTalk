import SwiftUI

/// 비용/토큰 설정 — 누적 실비용·모델 가격 테이블·예산 상한 (v0.2.7 축2)
struct CostSettingsView: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var viewModel = ChatViewModel.shared
    @AppStorage("costMonthlyBudget") private var monthlyBudget: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space4) {
            VStack(spacing: theme.space4) {
                Text("비용은 실측 토큰 × 모델 가격(백만 토큰당 USD)으로 자동 계산됩니다. 유료 모델은 말풍선과 모델 목록에 실비용이 표시됩니다.")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(theme.cardInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.cardBackground)
            .overlay(RoundedRectangle(cornerRadius: theme.cardCornerRadius).stroke(theme.cardBorder.opacity(theme.borderOpacity), lineWidth: theme.defaultBorderWidth))
            .clipShape(RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous))

            ScrollView {
                VStack(alignment: .leading, spacing: theme.space4) {
                    // ── 누적 비용 요약 ──
                    VStack(alignment: .leading, spacing: 10) {
                        Text("누적 비용")
                            .font(.headline)
                        HStack(spacing: 20) {
                            summaryCell(title: "현재 세션", value: currentSessionCostText)
                            summaryCell(title: "전체 대화", value: totalCostText)
                            summaryCell(title: "유료 메시지", value: "\(totalPaidCount)개")
                        }
                        if hasBudget, isOverBudget {
                            Label("월 예산 \(budgetText) 초과", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(theme.warningColor)
                        } else if hasBudget {
                            Text("월 예산 \(budgetText)")
                                .font(.caption)
                                .foregroundStyle(theme.secondaryText)
                        }
                    }
                    .padding(theme.cardInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.cardBackground).overlay(RoundedRectangle(cornerRadius: theme.cardCornerRadius).stroke(theme.cardBorder.opacity(theme.borderOpacity), lineWidth: theme.defaultBorderWidth)).clipShape(RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous))

                    // ── 예산 설정 ──
                    VStack(alignment: .leading, spacing: 8) {
                        Text("월 예산 (USD)")
                            .font(.headline)
                        HStack {
                            TextField("예: 5", value: $monthlyBudget, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                            Text("0이면 설정 안 함")
                                .font(.caption)
                                .foregroundStyle(theme.secondaryText)
                        }
                    }
                    .padding(theme.cardInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.cardBackground).overlay(RoundedRectangle(cornerRadius: theme.cardCornerRadius).stroke(theme.cardBorder.opacity(theme.borderOpacity), lineWidth: theme.defaultBorderWidth)).clipShape(RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous))

                    // ── 모델 가격 테이블 ──
                    VStack(alignment: .leading, spacing: 8) {
                        Text("모델 가격")
                            .font(.headline)
                        Text("백만 토큰당 USD (입력 / 출력). 가격 없는 모델은 실비용이 계산되지 않습니다.")
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                        VStack(spacing: 0) {
                            ForEach(paidModels) { model in
                                priceRow(model)
                                if model.id != paidModels.last?.id {
                                    Divider().opacity(0.4)
                                }
                            }
                        }
                    }
                    .padding(theme.cardInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.cardBackground).overlay(RoundedRectangle(cornerRadius: theme.cardCornerRadius).stroke(theme.cardBorder.opacity(theme.borderOpacity), lineWidth: theme.defaultBorderWidth)).clipShape(RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous))
                }
            }
        }
        .padding(.horizontal, 100)
    }

    // MARK: - 데이터

    private var allMessages: [ChatMessage] {
        viewModel.sessions.flatMap(\.messages)
    }

    private var currentSessionMessages: [ChatMessage] {
        viewModel.currentSession?.messages ?? []
    }

    private var currentSessionCostText: String {
        SessionCost.formatUSD(SessionCost.calculated(messages: currentSessionMessages).totalUSD) ?? "$0.00"
    }

    private var totalCostText: String {
        SessionCost.formatUSD(SessionCost.calculated(messages: allMessages).totalUSD) ?? "$0.00"
    }

    private var totalPaidCount: Int {
        SessionCost.calculated(messages: allMessages).paidMessageCount
    }

    private var hasBudget: Bool { monthlyBudget > 0 }

    private var isOverBudget: Bool {
        hasBudget && SessionCost.calculated(messages: allMessages).totalUSD > monthlyBudget
    }

    private var budgetText: String {
        String(format: "$%.2f", monthlyBudget)
    }

    private var paidModels: [AIModel] {
        ModelCatalog.shared.models.filter(\.isPaid).sorted {
            ($0.provider.rawValue, $0.displayName) < ($1.provider.rawValue, $1.displayName)
        }
    }

    // MARK: - 하위 뷰

    @ViewBuilder
    private func summaryCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
            Text(value)
                .font(.title3)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func priceRow(_ model: AIModel) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.provider.accentSwiftUIColor)
                .frame(width: theme.dotStandard, height: theme.dotStandard)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.displayName)
                    .font(.callout)
                    .lineLimit(1)
                Text(model.id)
                    .font(.caption)
                    .foregroundStyle(theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(pricePair(model))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(theme.accentColor)
        }
        .padding(.vertical, 4)
    }

    private func pricePair(_ model: AIModel) -> String {
        func fmt(_ v: Double?) -> String {
            guard let v else { return "—" }
            return v >= 1 ? String(format: "$%.2f", v) : String(format: "$%.3f", v)
        }
        return "\(fmt(model.inputPricePerM)) / \(fmt(model.outputPricePerM))"
    }
}
