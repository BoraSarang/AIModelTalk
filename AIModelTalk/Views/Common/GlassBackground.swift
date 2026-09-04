import SwiftUI

// MARK: - GlassBackground (Liquid Glass 래퍼)

/// macOS 26+ Liquid Glass 효과 + 폴백 지원
/// Osaurus의 Common.GlassBackground 참고
struct GlassBackground: ViewModifier {
    @Environment(\.theme) private var theme
    let enabled: Bool
    let opacity: Double?
    let material: NSVisualEffectView.Material?
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if enabled && theme.glassEnabled {
            if #available(macOS 26.0, *) {
                content
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.clear)
                            .glassEffect(
                                .regular
                                    .tint(theme.glassTintColor ?? .clear)
                                    .interactive(),
                                in: .rect(cornerRadius: cornerRadius)
                            )
                    )
            } else {
                content
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(material?.color ?? theme.primaryBackground.opacity(opacity ?? theme.glassOpacityPrimary))
                    )
            }
        } else {
            content.background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(material?.color ?? theme.primaryBackground.opacity(opacity ?? theme.glassOpacityPrimary))
            )
        }
    }
}

// MARK: - GlassListRow (리스트 행 글라스 배경)

/// 리스트/테이블 행에 적용하는 글라스 배경
/// 선택/호버 상태 반응
struct GlassListRow: ViewModifier {
    @Environment(\.theme) private var theme
    let isSelected: Bool
    let isHovering: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: theme.defaultBorderWidth)
            )
            .animation(theme.animationQuick, value: isSelected)
            .animation(theme.animationQuick, value: isHovering)
    }

    private var backgroundColor: Color {
        if isSelected {
            return theme.accentColor.opacity(0.15)
        } else if isHovering {
            return theme.primaryBorder.opacity(0.08)
        } else {
            return theme.cardBackground
        }
    }

    private var borderColor: Color {
        if isSelected {
            return theme.accentColor.opacity(0.5)
        } else if isHovering {
            return theme.primaryBorder.opacity(0.3)
        } else {
            return theme.cardBorder.opacity(theme.borderOpacity)
        }
    }
}

// MARK: - NSVisualEffectView.Material 편의 확장

extension NSVisualEffectView.Material {
    var color: Color {
        switch self {
        case .hudWindow, .windowBackground: return Color(nsColor: .windowBackgroundColor)
        case .popover, .menu: return Color(nsColor: .controlBackgroundColor)
        case .sidebar: return Color(nsColor: .controlBackgroundColor)
        case .headerView: return Color(nsColor: .controlBackgroundColor)
        case .sheet: return Color(nsColor: .windowBackgroundColor)
        case .titlebar: return Color(nsColor: .controlBackgroundColor)
        case .selection: return Color(nsColor: .selectedControlColor)
        case .underWindowBackground, .underPageBackground: return Color(nsColor: .underPageBackgroundColor)
        @unknown default: return Color(nsColor: .windowBackgroundColor)
        }
    }
}