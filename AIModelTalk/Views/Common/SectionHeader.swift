import SwiftUI

// MARK: - SectionHeader (Osaurus 스타일 섹션 헤더)

/// 설정창 등에서 사용하는 섹션 헤더
/// ALL CAPS + tracking 1.4 + secondary 색상
/// Osaurus의 Common.SectionHeader 참고
struct SectionHeader: View {
    @Environment(\.theme) private var theme
    let title: String
    let subtitle: String?
    var action: (() -> Void)?
    var actionLabel: String?

    var body: some View {
        HStack(spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .tracking(1.4)
                .textCase(.uppercase)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiaryText)
            }

            Spacer()

            if let action = action, let label = actionLabel {
                Button(action: action) {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }
}

// MARK: - SectionHeader with Count

/// 개수 뱃지가 있는 섹션 헤더 (예: "공급자 3개")
struct SectionHeaderWithCount: View {
    @Environment(\.theme) private var theme
    let title: String
    let count: Int
    var action: (() -> Void)?
    var actionLabel: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .tracking(1.4)
                .textCase(.uppercase)

            Text("\(count)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.tertiaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(theme.chipFill)
                .clipShape(Capsule())

            Spacer()

            if let action = action, let label = actionLabel {
                Button(action: action) {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }
}

// MARK: - Divider with Label

/// 라벨이 있는 디바이더 (섹션 구분용)
struct DividerWithLabel: View {
    @Environment(\.theme) private var theme
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(theme.primaryBorder.opacity(theme.borderOpacity))
                .frame(height: 1)

            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.tertiaryText)
                .tracking(1.4)
                .textCase(.uppercase)

            Rectangle()
                .fill(theme.primaryBorder.opacity(theme.borderOpacity))
                .frame(height: 1)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#Preview("SectionHeader") {
    VStack(spacing: 20) {
        SectionHeader(title: "공급자", subtitle: "연결된 원격 MCP 공급자 관리")
        SectionHeaderWithCount(title: "모델", count: 12, action: { }, actionLabel: "전체 보기")
        DividerWithLabel(label: "고급 설정")
    }
    .padding()
    .environment(\.theme, ThemeBox(LightTheme()))
}