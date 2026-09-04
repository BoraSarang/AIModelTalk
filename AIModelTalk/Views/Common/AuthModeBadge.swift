import SwiftUI

// MARK: - AuthModeBadge (인증 방식 뱃지 - 공통화)

/// MCP 공급자 인증 방식을 표시하는 뱃지
/// MCPSettingsView, MCPProviderCatalogView 등에서 중복 사용 방지
struct AuthModeBadge: View {
    @Environment(\.theme) private var theme
    let mode: MCPAuthMode
    var fontSize: CGFloat = 8
    var paddingHorizontal: CGFloat = 6
    var paddingVertical: CGFloat = 2

    var body: some View {
        Text(mode.displayName)
            .font(.system(size: fontSize, weight: .medium))
            .padding(.horizontal, paddingHorizontal)
            .padding(.vertical, paddingVertical)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch mode {
        case .oauth21DCR: return theme.accentColor.opacity(0.15)
        case .oauth21Manual: return Color.purple.opacity(0.15)
        case .apiKey: return theme.successColor.opacity(0.15)
        case .selfHosted: return theme.secondaryText.opacity(0.15)
        }
    }

    private var foregroundColor: Color {
        switch mode {
        case .oauth21DCR: return theme.accentColor
        case .oauth21Manual: return .purple
        case .apiKey: return theme.successColor
        case .selfHosted: return theme.secondaryText
        }
    }
}

// MARK: - CategoryBadge (카테고리 뱃지)

struct CategoryBadge: View {
    @Environment(\.theme) private var theme
    let category: MCPProviderTemplate.Category
    var fontSize: CGFloat = 8
    var paddingHorizontal: CGFloat = 6
    var paddingVertical: CGFloat = 2

    var body: some View {
        Text(category.displayName)
            .font(.system(size: fontSize, weight: .medium))
            .padding(.horizontal, paddingHorizontal)
            .padding(.vertical, paddingVertical)
            .background(theme.accentColor.opacity(0.1))
            .foregroundStyle(theme.accentColor)
            .clipShape(Capsule())
    }
}

// MARK: - StatusBadge (상태 뱃지)

struct StatusBadge: View {
    @Environment(\.theme) private var theme
    let status: ConnectionStatus
    var fontSize: CGFloat = 8

    enum ConnectionStatus {
        case connected
        case connecting
        case disconnected
        case error
        case unknown
    }

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var statusColor: Color {
        switch status {
        case .connected: return theme.successColor
        case .connecting: return theme.warningColor
        case .disconnected: return theme.secondaryText
        case .error: return theme.errorColor
        case .unknown: return theme.tertiaryText
        }
    }

    private var statusText: String {
        switch status {
        case .connected: return "연결됨"
        case .connecting: return "연결 중"
        case .disconnected: return "미연결"
        case .error: return "오류"
        case .unknown: return "알 수 없음"
        }
    }
}

// MARK: - Preview

#Preview("AuthModeBadge") {
    HStack(spacing: 12) {
        AuthModeBadge(mode: .oauth21DCR)
        AuthModeBadge(mode: .oauth21Manual)
        AuthModeBadge(mode: .apiKey)
        AuthModeBadge(mode: .selfHosted)
    }
    .padding()
    .environment(\.theme, ThemeBox(LightTheme()))
}

#Preview("CategoryBadge") {
    HStack(spacing: 12) {
        CategoryBadge(category: .development)
        CategoryBadge(category: .productivity)
        CategoryBadge(category: .communication)
    }
    .padding()
    .environment(\.theme, ThemeBox(LightTheme()))
}

#Preview("StatusBadge") {
    HStack(spacing: 12) {
        StatusBadge(status: .connected)
        StatusBadge(status: .connecting)
        StatusBadge(status: .disconnected)
        StatusBadge(status: .error)
    }
    .padding()
    .environment(\.theme, ThemeBox(LightTheme()))
}