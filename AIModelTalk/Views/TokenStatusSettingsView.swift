import SwiftUI

/// 토큰 상태 — 사용 중인 공급자·모델의 실측 토큰 사용/남음 테이블 (v0.3.2)
/// 비용(USD) 아웃, "실제 토큰 상황"만 표시합니다.
struct TokenStatusSettingsView: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var viewModel = ChatViewModel.shared
    @ObservedObject private var quotaStore = TokenQuotaStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.space4) {
                headerCard

                if !quotaStore.accountQuotas.isEmpty {
                    accountQuotaCard
                }

                if usedRows.isEmpty {
                    emptyCard
                } else {
                    modelTableCard
                }
            }
        }
        .padding(theme.space16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 카드 구성

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("토큰은 응답 시점의 실측 usage로 집계됩니다. 사용한 공급자·모델의 한도 대비 사용량/남음만 표시하며, 공급자 계정 잔량(Anthropic)은 마지막 응답 기준입니다.")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
        .padding(theme.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: theme.cardCornerRadius).stroke(theme.cardBorder.opacity(theme.borderOpacity), lineWidth: theme.defaultBorderWidth))
        .clipShape(RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous))
    }

    private var accountQuotaCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("공급자 계정 잔량")
                .font(.headline)
            ForEach(Array(quotaStore.accountQuotas.values), id: \.provider) { quota in
                HStack(spacing: 8) {
                    Circle()
                        .fill(quota.provider.accentSwiftUIColor)
                        .frame(width: theme.dotStandard, height: theme.dotStandard)
                    Text(quota.provider.rawValue)
                        .font(.callout)
                    Spacer()
                    Text("남음 \(TokenQuotaStore.compact(quota.remaining)) / \(TokenQuotaStore.compact(quota.limit))")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(quota.ratio > 0.9 ? Color.red : theme.accentColor)
                }
                Text("갱신: \(quota.updatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(theme.tertiaryText)
            }
        }
        .padding(theme.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: theme.cardCornerRadius).stroke(theme.cardBorder.opacity(theme.borderOpacity), lineWidth: theme.defaultBorderWidth))
        .clipShape(RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous))
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("모델 토큰 상태")
                .font(.headline)
            Text("아직 실측 토큰이 있는 사용 기록이 없습니다. 채팅에서 응답을 받으면 여기에 모델별 사용량이 나타납니다.")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
        .padding(theme.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: theme.cardCornerRadius).stroke(theme.cardBorder.opacity(theme.borderOpacity), lineWidth: theme.defaultBorderWidth))
        .clipShape(RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous))
    }

    private var modelTableCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("모델 토큰 상태")
                .font(.headline)
            VStack(spacing: 0) {
                ForEach(usedRows) { row in
                    modelRow(row)
                    if row.id != usedRows.last?.id {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .padding(theme.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: theme.cardCornerRadius).stroke(theme.cardBorder.opacity(0.8), lineWidth: theme.defaultBorderWidth))
        .clipShape(RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous))
    }

    private func modelRow(_ row: ModelTokenUsageRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(row.model.provider.accentSwiftUIColor)
                    .frame(width: theme.dotStandard, height: theme.dotStandard)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.model.displayName)
                        .font(.callout)
                        .lineLimit(1)
                    Text(row.model.id)
                        .font(.caption)
                        .foregroundStyle(theme.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(row.model.contextLimit > 0 ? "\(row.model.contextLimit / 1000)K" : "—")
                    .font(.caption2)
                    .foregroundStyle(theme.secondaryText)
            }

            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                    Text("\(TokenQuotaStore.compact(row.snapshot.measuredPrompt))")
                    Image(systemName: "arrow.down")
                    Text("\(TokenQuotaStore.compact(row.snapshot.measuredCompletion))")
                }
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(theme.secondaryText)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(row.snapshot.ratio > 0.9 ? Color.red : theme.accentColor)
                            .frame(width: max(2, geo.size.width * CGFloat(min(max(row.snapshot.ratio, 0), 1))))
                    }
                }
                .frame(height: 5)

                Text("사용 \(TokenQuotaStore.compact(row.snapshot.used)) · 남음 \(TokenQuotaStore.compact(row.snapshot.remaining))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(row.snapshot.ratio > 0.9 ? Color.red : theme.accentColor)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - 데이터

    private var usedRows: [ModelTokenUsageRow] {
        rows.filter { $0.snapshot.source == .measured }
    }

    private var rows: [ModelTokenUsageRow] {
        let all = viewModel.sessions.flatMap(\.messages)
        var uniqueModels: [String: AIModel] = [:]
        for message in all {
            guard let provider = message.provider, let modelID = message.modelID,
                  let model = ModelCatalog.shared.model(id: modelID, provider: provider) else { continue }
            uniqueModels["\(provider.rawValue):\(modelID)"] = model
        }
        return uniqueModels.values
            .sorted { ($0.provider.rawValue, $0.displayName) < ($1.provider.rawValue, $1.displayName) }
            .map { model in
                ModelTokenUsageRow(
                    model: model,
                    snapshot: TokenQuotaStore.snapshot(model: model, messages: all, systemPrompt: "")
                )
            }
    }
}

/// 설정 탭 테이블 행 모델 (v0.3.2)
private struct ModelTokenUsageRow: Identifiable, Equatable {
    let model: AIModel
    let snapshot: ModelTokenSnapshot

    var id: String { "\(model.provider.rawValue):\(model.id)" }
}