import SwiftUI

// MARK: - EmptyStateView (Osaurus 스타일 빈 상태)

/// 빈 상태 화면 — 캐릭터 일러스트 + 제목 + 설명 + 액션 버튼
/// 채팅 빈 상태, 공급자 없음, 검색 결과 없음 등에서 사용
struct EmptyStateView: View {
    @Environment(\.theme) private var theme
    let character: CharacterIllustrations.Character
    let title: String
    let message: String
    let primaryAction: EmptyStateAction?
    let secondaryAction: EmptyStateAction?

    struct EmptyStateAction {
        let label: String
        let icon: String?
        let action: () -> Void
        var isPrimary: Bool = true
    }

    var body: some View {
        VStack(spacing: 20) {
            // 캐릭터 일러스트 (SF Symbol 폴백 포함)
            CharacterIllustrations.CharacterImage(character: character, size: 160)
                .opacity(0.9)

            // 텍스트
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 320)
            }

            // 액션 버튼들
            if primaryAction != nil || secondaryAction != nil {
                HStack(spacing: 12) {
                    if let secondary = secondaryAction {
                        GradientButton(
                            title: secondary.label,
                            icon: secondary.icon,
                            action: secondary.action,
                            isPrimary: false
                        )
                        .controlSize(.regular)
                    }

                    if let primary = primaryAction {
                        GradientButton(
                            title: primary.label,
                            icon: primary.icon,
                            action: primary.action,
                            isPrimary: true
                        )
                        .controlSize(.regular)
                    }
                }
            }
        }
        .padding(32)
        .frame(maxWidth: 420)
    }
}

// MARK: - Convenience Initializers

extension EmptyStateView {
    /// 채팅 빈 상태
    static func chatEmpty(
        hasModels: Bool,
        onAddModel: @escaping () -> Void,
        onUseFoundation: (() -> Void)? = nil
    ) -> EmptyStateView {
        EmptyStateView(
            character: hasModels ? .thinking : .empty,
            title: hasModels ? "대화를 시작하세요" : "모델이 필요합니다",
            message: hasModels
                ? "아래 입력창에 메시지를 입력해 대화를 시작하세요."
                : "먼저 모델을 추가하거나 Apple Foundation Models를 사용하세요.",
            primaryAction: .init(
                label: hasModels ? "새 대화" : (onUseFoundation != nil ? "Foundation Models 사용" : "모델 추가"),
                icon: hasModels ? "plus.bubble" : "brain",
                action: hasModels ? {} : (onUseFoundation ?? onAddModel),
                isPrimary: true
            ),
            secondaryAction: hasModels ? nil : .init(
                label: "모델 추가",
                icon: "plus",
                action: onAddModel,
                isPrimary: false
            )
        )
    }

    /// 공급자 없음 빈 상태
    static func noProviders(onConnect: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            character: .empty,
            title: "연결된 공급자가 없습니다",
            message: "'공급자 연결'로 Linear, Notion, GitHub 등\n잘 알려진 서비스를 원탭 연결하세요.",
            primaryAction: .init(
                label: "공급자 연결",
                icon: "plus",
                action: onConnect
            ),
            secondaryAction: nil
        )
    }

    /// 검색 결과 없음
    static func noSearchResults(query: String, onClear: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            character: .thinking,
            title: "검색 결과가 없습니다",
            message: "'\(query)'에 해당하는 결과가 없습니다.\n다른 검색어를 시도해보세요.",
            primaryAction: .init(
                label: "검색 초기화",
                icon: "xmark.circle",
                action: onClear,
                isPrimary: false
            ),
            secondaryAction: nil
        )
    }
}

// MARK: - SettingsEmptyState (설정창용 빈 상태)

struct SettingsEmptyState: View {
    @Environment(\.theme) private var theme
    let character: CharacterIllustrations.Character
    let title: String
    let message: String
    let actionLabel: String?
    let actionIcon: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            CharacterIllustrations.CharacterImage(character: character, size: 120)
                .opacity(0.8)

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.primaryText)

                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            if let action = action, let label = actionLabel, let icon = actionIcon {
                GradientButton(
                    title: label,
                    icon: icon,
                    action: action
                )
                .controlSize(.regular)
            }
        }
        .padding(24)
    }
}

// MARK: - Preview

#Preview("EmptyStateView - Chat Empty") {
    EmptyStateView.chatEmpty(hasModels: true, onAddModel: {})
        .padding()
        .environment(\.theme, ThemeBox(LightTheme()))
}

#Preview("EmptyStateView - No Providers") {
    EmptyStateView.noProviders(onConnect: {})
        .padding()
        .environment(\.theme, ThemeBox(LightTheme()))
}

#Preview("SettingsEmptyState") {
    SettingsEmptyState(
        character: .empty,
        title: "MCP 서버가 없습니다",
        message: "아래 '추가' 버튼으로 stdio MCP 서버를 등록하세요.",
        actionLabel: "추가",
        actionIcon: "plus",
        action: {}
    )
    .frame(width: 400)
    .padding()
    .environment(\.theme, ThemeBox(LightTheme()))
}