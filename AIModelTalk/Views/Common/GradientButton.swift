import SwiftUI

// MARK: - GradientButton (Osaurus 스타일 버튼)

/// Primary/Secondary/Destructive 상태를 지원하는 그라데이션 버튼
/// Osaurus의 SimpleComponents.GradientButton 참고
struct GradientButton: View {
    @Environment(\.theme) private var theme
    let title: String
    let icon: String?
    let action: () -> Void
    var isDestructive: Bool = false
    var isPrimary: Bool = true
    var isLoading: Bool = false
    var isDisabled: Bool = false

    @State private var isPressed = false
    @State private var isHovering = false

    var buttonColor: Color {
        if isDestructive { return theme.errorColor }
        return theme.accentColor
    }

    /// primary 배경색 대비 자동 반전 글자색 — 다크 테마의 밝은 accent 위 흰 글자 미노출 방지 (T-324)
    private var primaryForeground: Color {
        buttonColor.isLightColor ? .black : .white
    }

    var body: some View {
        Button(action: {
            guard !isDisabled, !isLoading else { return }
            action()
        }) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(isPrimary ? primaryForeground : buttonColor)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(isPrimary ? primaryForeground : buttonColor)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Group {
                    if isPrimary {
                        AnyView(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(buttonColor)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(buttonColor, lineWidth: 1.5)
                                )
                        )
                    } else {
                        AnyView(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(theme.inputBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(
                                            isPressed
                                                ? buttonColor : isHovering ? buttonColor.opacity(0.8) : theme.inputBorder,
                                            lineWidth: 1.5
                                        )
                                )
                        )
                    }
                }
            )
            .shadow(
                color: theme.shadowColor.opacity(
                    isHovering ? theme.shadowOpacity * 2 : theme.shadowOpacity
                ),
                radius: isHovering ? 6 : 4,
                x: 0,
                y: 2
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isDisabled || isLoading)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(theme.animationQuick, value: isPressed)
        .animation(theme.animationQuick, value: isHovering)
        .opacity(isDisabled ? 0.5 : 1.0)
        .onHover { hovering in
            guard !isDisabled else { return }
            isHovering = hovering
        }
        .onLongPressGesture(
            minimumDuration: .infinity,
            maximumDistance: .infinity,
            pressing: { pressing in
                guard !isDisabled else { return }
                isPressed = pressing
            },
            perform: {}
        )
    }
}

// MARK: - SimpleToggleButton (토글 버튼)

/// 켜기/끄기 상태를 토글하는 버튼 (연결/해제, 활성/비활성 등)
/// Osaurus의 SimpleComponents.SimpleToggleButton 참고
struct SimpleToggleButton: View {
    @Environment(\.theme) private var theme
    let isOn: Bool
    let title: String
    let icon: String
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    var buttonColor: Color {
        isOn ? theme.errorColor : theme.successColor
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .rotationEffect(.degrees(isHovering ? 8 : 0))
                    .scaleEffect(isHovering ? 1.06 : 1.0)
                    .animation(theme.animationQuick, value: isHovering)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(buttonColor)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.inputBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                isPressed
                                    ? buttonColor
                                    : (isHovering ? buttonColor.opacity(0.95) : buttonColor.opacity(0.75)),
                                lineWidth: 1.8
                            )
                    )
            )
            .shadow(
                color: theme.shadowColor.opacity(
                    isHovering ? theme.shadowOpacity * 2 : theme.shadowOpacity
                ),
                radius: isHovering ? 6 : 4,
                x: 0,
                y: 2
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(theme.animationQuick, value: isPressed)
        .animation(theme.animationQuick, value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .onLongPressGesture(
            minimumDuration: .infinity,
            maximumDistance: .infinity,
            pressing: { pressing in
                isPressed = pressing
            },
            perform: {}
        )
    }
}