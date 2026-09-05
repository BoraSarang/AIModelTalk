import SwiftUI

/// 설정 탭 공통 카드 — 테마 배경/보더/라운드를 일관되게 적용해 설정 전 탭 스타일을 통일한다 (v0.3.1)
/// 기존 `.formStyle(.grouped)`는 시스템 그룹 배경을 강제해 테마가 무시됐다 — 대신 이 카드를 사용한다.
/// 카드 안에 개별 섹션/행을 배치하고, 상단에 옵션 섹션 제목을 표시한다.
struct ThemedSettingsCard<Content: View>: View {
    @Environment(\.theme) private var theme
    private let title: String?
    private let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space10) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.space12)
        .background(theme.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
                .stroke(theme.cardBorder.opacity(0.8), lineWidth: theme.defaultBorderWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous))
    }
}

/// 설정 카드 안의 개별 설정 행 — 라벨 + 트레일링 컨트롤/부가 텍스트의 표준 레이아웃
struct ThemedSettingsRow<Content: View>: View {
    @Environment(\.theme) private var theme
    private let label: String
    private let sublabel: String?
    private let content: Content

    init(_ label: String, sublabel: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.sublabel = sublabel
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: theme.space10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(theme.primaryText)
                if let sublabel {
                    Text(sublabel)
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                }
            }
            Spacer(minLength: theme.space16)
            content
        }
    }
}

/// 설정 카드 안의 보조 설명 문구 (secondary 텍스트)
struct ThemedSettingsCaption: View {
    @Environment(\.theme) private var theme
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(theme.secondaryText)
    }
}