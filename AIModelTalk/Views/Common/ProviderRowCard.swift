import SwiftUI

// MARK: - ProviderRowCard (공급자 행 카드 - 리스트용)

/// 공급자 행 카드 — 리스트/테이블 뷰용 (ProvidersSettingsView에서 사용)
/// 컴팩트한 한 줄 레이아웃: 아바타 + 이름/URL/배지 + 상태 + 토글 + 액션 버튼
/// Osaurus의 Settings.ProviderRowCard 참고
struct ProviderRowCard: View {
    @Environment(\.theme) private var theme
    let provider: MCPProviderConfiguration
    let diagnostics: MCPProviderDiagnostics?
    let isTesting: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onTest: () -> Void
    let onSignIn: () -> Void
    let onSaveBearerToken: (String) -> Void
    let onToggleEnabled: (Bool) -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // 아바타
            AvatarView(
                provider: provider,
                size: 28,
                showStatusRing: true,
                status: statusForProvider
            )

            // 정보
            VStack(alignment: .leading, spacing: 3) {
                Text(provider.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(provider.url)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    AuthModeBadge(mode: provider.authMode)
                        .font(.system(size: 8))
                }
            }

            Spacer()

            // 상태/도구 수
            if isTesting {
                ProgressView()
                    .controlSize(.small)
            } else if let diag = diagnostics {
                HStack(spacing: 8) {
                    StatusBadge(status: diag.status)
                    Text("도구 \(diag.toolCount)개")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryText)
                }
            }

            // 액션 버튼들
            HStack(spacing: 6) {
                if !provider.isEnabled {
                    GradientButton(
                        title: "연결",
                        icon: "link",
                        action: onConnect
                    )
                    .controlSize(.small)
                } else {
                    GradientButton(
                        title: "테스트",
                        icon: "arrow.clockwise",
                        action: onTest,
                        isPrimary: false
                    )
                    .controlSize(.small)
                }

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryText)
                }
                .buttonStyle(.plain)
                .help("편집")

                if provider.authMode == .oauth21DCR || provider.authMode == .oauth21Manual {
                    Button(action: onSignIn) {
                        Image(systemName: "person.badge.key")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help("OAuth 재로그인")
                }

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.errorColor)
                }
                .buttonStyle(.plain)
                .help("삭제")
            }

            // 활성화 토글
            Toggle("", isOn: Binding(
                get: { provider.isEnabled },
                set: { onToggleEnabled($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .modifier(GlassListRow(isSelected: false, isHovering: isHovering))
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var statusForProvider: StatusBadge.ConnectionStatus {
        guard let diagnostics = diagnostics else { return .unknown }
        return diagnostics.status
    }
}

// MARK: - CompactProviderRow (더 컴팩트한 버전)

/// 더 좁은 공간용 컴팩트 행 (사이드바 등)
struct CompactProviderRow: View {
    @Environment(\.theme) private var theme
    let provider: MCPProviderConfiguration
    let isConnected: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            AvatarView(provider: provider, size: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(provider.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Circle()
                        .fill(isConnected ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)

                    Text(provider.authMode.displayName)
                        .font(.caption2)
                        .foregroundStyle(theme.tertiaryText)
                }
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(theme.errorColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.cardBackground)
        )
    }
}

// MARK: - Preview

#Preview("ProviderRowCard") {
    let mockProvider = MCPProviderConfiguration(
        templateID: "linear",
        name: "Linear",
        url: "https://mcp.linear.app",
        authMode: .oauth21DCR
    )

    let mockDiagnostics = MCPProviderDiagnostics(status: .connected, toolCount: 12, message: "Connected")

    ProviderRowCard(
        provider: mockProvider,
        diagnostics: mockDiagnostics,
        isTesting: false,
        onEdit: {},
        onDelete: {},
        onConnect: {},
        onDisconnect: {},
        onTest: {},
        onSignIn: {},
        onSaveBearerToken: { _ in },
        onToggleEnabled: { _ in }
    )
    .frame(width: 700)
    .padding()
    .environment(\.theme, ThemeBox(LightTheme()))
}