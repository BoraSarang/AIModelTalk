import SwiftUI

// MARK: - ProviderCard (MCP 공급자 카드 - 그리드용)

/// 공급자 카드 — 그리드 뷰용 (MCPSettingsView에서 사용)
/// 아바타 + 이름 + URL + 배지(상단), 도구 수 + 상태(중앙), 토글+편집+삭제(하단)
/// Osaurus의 Settings.ProviderCard 참고
struct ProviderCard: View {
    @Environment(\.theme) private var theme
    let report: MCPServerHubProviderReport
    let animationIndex: Int
    let isTesting: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onTest: () -> Void
    let onCopyDiagnostics: () -> Void
    let onToggleEnabled: (Bool) -> Void
    let onSignIn: () -> Void
    let onSaveBearerToken: (String) -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 12) {
            // 상단: 아바타 + 이름 + URL + 배지
            HStack(spacing: 12) {
                // 아바타
                AvatarView(
                    provider: report.provider,
                    size: 40,
                    showStatusRing: true,
                    status: statusForProvider
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(report.provider.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(report.provider.url)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        AuthModeBadge(mode: report.provider.authMode)
                            .font(.system(size: 8))
                    }
                }

                Spacer()
            }

            // 중간: 상태/도구 수 + 테스트 버튼
            HStack(spacing: 12) {
                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                    Text("테스트 중...")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryText)
                } else if let diagnostics = report.diagnostics {
                    StatusBadge(status: diagnostics.status)
                    Text("도구 \(diagnostics.toolCount)개")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryText)
                } else {
                    StatusBadge(status: .unknown)
                }

                Spacer()

                if !report.provider.isEnabled {
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
            }

            // 하단: 토글 + 편집 + 삭제
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { report.provider.isEnabled },
                    set: { onToggleEnabled($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()

                Spacer()

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryText)
                }
                .buttonStyle(.plain)
                .help("편집")

                Button(action: onCopyDiagnostics) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryText)
                }
                .buttonStyle(.plain)
                .help("진단 정보 복사")

                if report.provider.authMode == .oauth21DCR || report.provider.authMode == .oauth21Manual {
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
        }
        .padding(16)
        .background(MinimalCard(isHovering: isHovering, borderOpacityOverride: 0.9))
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var statusForProvider: StatusBadge.ConnectionStatus {
        guard let diagnostics = report.diagnostics else { return .unknown }
        return diagnostics.status
    }
}

// MARK: - MCPServerHubProviderReport (간소화된 타입 정의)

/// Osaurus의 MCPServerHubProviderReport 참고 - 실제 프로젝트 타입과 연동 필요
struct MCPServerHubProviderReport: Identifiable {
    let id: UUID
    let provider: MCPProviderConfiguration
    let diagnostics: MCPProviderDiagnostics?
}

struct MCPProviderDiagnostics {
    let status: StatusBadge.ConnectionStatus
    let toolCount: Int
    let message: String
}

// MARK: - Preview

#Preview("ProviderCard") {
    let mockProvider = MCPProviderConfiguration(
        templateID: "linear",
        name: "Linear",
        url: "https://mcp.linear.app",
        authMode: .oauth21DCR
    )

    let mockReport = MCPServerHubProviderReport(
        id: UUID(),
        provider: mockProvider,
        diagnostics: MCPProviderDiagnostics(status: .connected, toolCount: 12, message: "Connected")
    )

    ProviderCard(
        report: mockReport,
        animationIndex: 0,
        isTesting: false,
        onEdit: {},
        onDelete: {},
        onConnect: {},
        onDisconnect: {},
        onTest: {},
        onCopyDiagnostics: {},
        onToggleEnabled: { _ in },
        onSignIn: {},
        onSaveBearerToken: { _ in }
    )
    .frame(width: 300)
    .padding()
    .environment(\.theme, ThemeBox(LightTheme()))
}