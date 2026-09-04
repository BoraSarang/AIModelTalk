import SwiftUI

// MARK: - ThemedAlertDialog (Osaurus 스타일 알림 다이얼로그)

/// 테마 적용 알림 다이얼로그
/// contained/wide 스타일 지원, 악세서리 뷰 가능
struct ThemedAlertDialog<Accessory: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    let title: String
    let message: String?
    let accessory: Accessory?
    let buttons: [ThemedAlertButton]
    let width: CGFloat?
    let presentationStyle: PresentationStyle
    let onDismiss: (() -> Void)?

    enum PresentationStyle {
        case contained   // 기본: 모서리 라운딩, 내부 패딩
        case wide        // 넓은 다이얼로그 (버튼 라벨 한 줄 유지)
    }

    init(
        _ title: String,
        message: String? = nil,
        accessory: Accessory? = nil,
        buttons: [ThemedAlertButton],
        width: CGFloat? = nil,
        presentationStyle: PresentationStyle = .contained,
        onDismiss: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.accessory = accessory
        self.buttons = buttons
        self.width = width
        self.presentationStyle = presentationStyle
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            // 헤더 영역
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(theme.primaryText)
                    .multilineTextAlignment(.center)

                if let message = message {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let accessory = accessory {
                    accessory
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()
                .background(theme.primaryBorder.opacity(theme.borderOpacity))

            // 버튼 영역
            HStack(spacing: 12) {
                ForEach(buttons.indices, id: \.self) { idx in
                    let button = buttons[idx]
                    GradientButton(
                        title: button.title,
                        icon: button.icon,
                        action: {
                            button.action()
                            dismiss()
                            onDismiss?()
                        },
                        isDestructive: button.role == .destructive,
                        isPrimary: button.role == .primary,
                        isDisabled: button.isDisabled
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: width ?? 420)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.primaryBackground)
                .shadow(color: .black.opacity(0.2), radius: 24, y: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.primaryBorder.opacity(theme.borderOpacity), lineWidth: 1)
        )
    }
}

// MARK: - ThemedAlertButton

struct ThemedAlertButton {
    let title: String
    let icon: String?
    let role: Role
    let isDisabled: Bool
    let action: () -> Void

    enum Role { case primary, secondary, cancel, destructive }

    init(
        title: String,
        icon: String? = nil,
        role: Role = .secondary,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.role = role
        self.isDisabled = isDisabled
        self.action = action
    }

    static func primary(_ title: String, icon: String? = nil, isDisabled: Bool = false, action: @escaping () -> Void) -> ThemedAlertButton {
        ThemedAlertButton(title: title, icon: icon, role: .primary, isDisabled: isDisabled, action: action)
    }

    static func secondary(_ title: String, icon: String? = nil, action: @escaping () -> Void) -> ThemedAlertButton {
        ThemedAlertButton(title: title, icon: icon, role: .secondary, action: action)
    }

    static func cancel(_ title: String, action: @escaping () -> Void) -> ThemedAlertButton {
        ThemedAlertButton(title: title, role: .cancel, action: action)
    }

    static func destructive(_ title: String, icon: String? = nil, isDisabled: Bool = false, action: @escaping () -> Void) -> ThemedAlertButton {
        ThemedAlertButton(title: title, icon: icon, role: .destructive, isDisabled: isDisabled, action: action)
    }
}

// MARK: - View Extension for Easy Presentation

extension View {
    /// 테마 알림 다이얼로그 표시
    func themedAlert<Accessory: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        message: String? = nil,
        accessory: Accessory? = nil,
        buttons: [ThemedAlertButton],
        width: CGFloat? = nil,
        presentationStyle: ThemedAlertDialog<Accessory>.PresentationStyle = .contained,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        // SwiftUI의 기본 alert는 커스터마이징이 제한적이므로
        // 커스텀 시트 기반 다이얼로그 사용
        Color.clear
            .frame(width: 0, height: 0)
            .sheet(isPresented: isPresented) {
            ThemedAlertDialog(
                title,
                message: message,
                accessory: accessory,
                buttons: buttons,
                width: width,
                presentationStyle: presentationStyle,
                onDismiss: { isPresented.wrappedValue = false }
            )
            .interactiveDismissDisabled()
        }
    }
}

// MARK: - Preview

#Preview("Contained Alert") {
    ThemedAlertDialog<EmptyView>(
        "Disable request timeout?",
        message: "Requests can hang indefinitely. This affects all providers.",
        accessory: nil,
        buttons: [
            .cancel("Cancel") {},
            .destructive("Disable Timeout") {},
        ],
        width: 420,
        presentationStyle: .contained
    )
    .environment(\.theme, ThemeBox(LightTheme()))
    .padding()
    .background(Color.gray.opacity(0.2))
}

#Preview("Wide Alert") {
    ThemedAlertDialog<EmptyView>(
        "This looks like an MCP server",
        message: "This URL answers like an MCP server, not a chat completions API. Osaurus can add it as an MCP connection instead — the URL and token you entered will be carried over.",
        accessory: nil,
        buttons: [
            .cancel("Cancel") {},
            .primary("Add as MCP Connection") {},
        ],
        width: 420,
        presentationStyle: .wide
    )
    .environment(\.theme, ThemeBox(LightTheme()))
    .padding()
    .background(Color.gray.opacity(0.2))
}