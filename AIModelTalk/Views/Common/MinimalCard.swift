import SwiftUI

// MARK: - MinimalCard (Osaurus 스타일 카드 배경)

/// 호버/프레스 상태에 반응하는 미니멀 카드 배경
/// Osaurus의 SimpleComponents.MinimalCard 참고
struct MinimalCard: View {
    @Environment(\.theme) private var theme
    var cornerRadius: CGFloat = 12
    var borderWidth: CGFloat = 1
    var isHovering: Bool = false
    var isPressed: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(theme.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        isPressed ? theme.focusBorder : isHovering ? theme.primaryBorder : theme.cardBorder.opacity(theme.borderOpacity),
                        lineWidth: borderWidth
                    )
            )
            .shadow(
                color: theme.shadowColor.opacity(theme.shadowOpacity),
                radius: isHovering ? theme.cardShadowRadiusHover : theme.cardShadowRadius,
                x: 0,
                y: isHovering ? theme.cardShadowYHover : theme.cardShadowY
            )
            .animation(theme.animationQuick, value: isHovering)
            .animation(theme.animationQuick, value: isPressed)
    }
}

// MARK: - SimpleCard (콘텐츠 래퍼 카드)

/// 콘텐츠를 감싸는 카드 — 패딩 + MinimalCard 배경 + 호버/프레스 상태
struct SimpleCard<Content: View>: View {
    @Environment(\.theme) private var theme
    let content: Content
    let padding: CGFloat
    @State private var isHovering = false
    @State private var isPressed = false

    init(padding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(MinimalCard(isHovering: isHovering, isPressed: isPressed))
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