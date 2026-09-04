import SwiftUI
import AppKit

// MARK: - Theme Protocol

/// 앱 전체 테마 시스템의 단일 진실 소스.
/// LightTheme/DarkTheme/CustomTheme가 준수하며, `@Environment(\.theme)`로 뷰에 주입된다.
public protocol ThemeProtocol {
    // MARK: 색상 (시맨틱)
    var primaryText: Color { get }
    var secondaryText: Color { get }
    var tertiaryText: Color { get }
    var placeholderText: Color { get }

    var primaryBackground: Color { get }
    var secondaryBackground: Color { get }
    var tertiaryBackground: Color { get }

    var cardBackground: Color { get }
    var cardBorder: Color { get }
    var accentColor: Color { get }
    var accentColorLight: Color { get }

    var primaryBorder: Color { get }
    var secondaryBorder: Color { get }
    var focusBorder: Color { get }

    var successColor: Color { get }
    var warningColor: Color { get }
    var errorColor: Color { get }
    var infoColor: Color { get }

    var inputBackground: Color { get }
    var inputBorder: Color { get }
    var inputFill: Color { get }

    // MARK: 글라스 / 머티리얼 (macOS 26+ Liquid Glass)
    var glassEnabled: Bool { get }
    var glassOpacityPrimary: Double { get }
    var glassOpacitySecondary: Double { get }
    var glassOpacityTertiary: Double { get }
    var glassBlurRadius: Double { get }
    var glassMaterial: NSVisualEffectView.Material { get }
    var glassTintColor: Color? { get }
    var glassTintOpacity: Double { get }
    var windowBackingOpacity: Double { get }

    // MARK: 그림자 / 고도
    var shadowColor: Color { get }
    var shadowOpacity: Double { get }
    var cardShadowRadius: Double { get }
    var cardShadowRadiusHover: Double { get }
    var cardShadowY: Double { get }
    var cardShadowYHover: Double { get }

    // MARK: 타이포그래피
    var primaryFontName: String { get }
    var monoFontName: String { get }
    var titleSize: Double { get }
    var headingSize: Double { get }
    var bodySize: Double { get }
    var captionSize: Double { get }
    var codeSize: Double { get }

    func font(size: CGFloat, weight: Font.Weight) -> Font
    func monoFont(size: CGFloat, weight: Font.Weight) -> Font

    // MARK: 애니메이션
    var animationDurationQuick: Double { get }
    var animationDurationMedium: Double { get }
    var animationDurationSlow: Double { get }
    var animationSpringResponse: Double { get }
    var animationSpringDamping: Double { get }

    var animationQuick: Animation { get }
    var animationMedium: Animation { get }
    var animationSlow: Animation { get }
    var springAnimation: Animation { get }
    func springAnimation(responseMultiplier: Double, dampingMultiplier: Double) -> Animation

    // MARK: 코너 / 보더 / 스페이싱
    var defaultBorderWidth: Double { get }
    var cardCornerRadius: Double { get }
    var inputCornerRadius: Double { get }
    var borderOpacity: Double { get }

    var space2: CGFloat { get }
    var space4: CGFloat { get }
    var space6: CGFloat { get }
    var space8: CGFloat { get }
    var space10: CGFloat { get }
    var space12: CGFloat { get }
    var space16: CGFloat { get }
    var space20: CGFloat { get }
    var space24: CGFloat { get }
    var space32: CGFloat { get }

    // MARK: 말풍선 / 채팅 커스터마이징
    var bubbleCornerRadius: Double { get }
    var userBubbleOpacity: Double { get }
    var assistantBubbleOpacity: Double { get }
    var userBubbleColor: Color? { get }
    var assistantBubbleColor: Color? { get }
    var messageBorderWidth: Double { get }
    var showEdgeLight: Bool { get }
    var showInlineAvatar: Bool { get }
    var inlineAvatarSize: Double { get }
    var showAgentName: Bool { get }
    var agentNameSize: Double { get }

    // MARK: 코드 하이라이트
    var codeHighlightTheme: String? { get }

    // MARK: 커스텀 테마 참조 (편집용)
    var customThemeConfig: CustomTheme? { get }
}

// MARK: - ThemeProtocol 기본 구현 (호환 레이어 + 공통 로직)

extension ThemeProtocol {
    // 색상 기본값 (라이트 테마 기준, 다크는 오버라이드)
    var tertiaryText: Color { secondaryText.opacity(0.7) }
    var placeholderText: Color { secondaryText }
    var tertiaryBackground: Color { secondaryBackground }
    var secondaryBorder: Color { primaryBorder.opacity(0.5) }
    var focusBorder: Color { accentColor }
    var infoColor: Color { secondaryText }
    var inputFill: Color { inputBackground }

    // 글라스 기본값
    var glassEnabled: Bool { false }
    var glassOpacityPrimary: Double { 0.25 }
    var glassOpacitySecondary: Double { 0.18 }
    var glassOpacityTertiary: Double { 0.10 }
    var glassBlurRadius: Double { 24 }
    var glassMaterial: NSVisualEffectView.Material { .hudWindow }
    var glassTintColor: Color? { nil }
    var glassTintOpacity: Double { 0 }
    var windowBackingOpacity: Double { 0.55 }

    // 그림자 기본값
    var shadowColor: Color { Color.black }
    var shadowOpacity: Double { 0.08 }
    var cardShadowRadius: Double { 8 }
    var cardShadowRadiusHover: Double { 16 }
    var cardShadowY: Double { 2 }
    var cardShadowYHover: Double { 6 }

    // 타이포그래피 기본값
    var primaryFontName: String { "SF Pro" }
    var monoFontName: String { "SF Mono" }
    var titleSize: Double { 28 }
    var headingSize: Double { 18 }
    var bodySize: Double { 14 }
    var captionSize: Double { 12 }
    var codeSize: Double { 13 }

    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if primaryFontName.lowercased().contains("sf pro") || primaryFontName.isEmpty {
            return .system(size: size, weight: weight)
        }
        return .custom(primaryFontName, size: size).weight(weight)
    }

    func monoFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if monoFontName.lowercased().contains("sf mono") || monoFontName.isEmpty {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        return .custom(monoFontName, size: size).weight(weight)
    }

    // 애니메이션 기본값
    var animationDurationQuick: Double { 0.15 }
    var animationDurationMedium: Double { 0.25 }
    var animationDurationSlow: Double { 0.35 }
    var animationSpringResponse: Double { 0.35 }
    var animationSpringDamping: Double { 0.85 }

    var animationQuick: Animation { .easeInOut(duration: animationDurationQuick) }
    var animationMedium: Animation { .easeInOut(duration: animationDurationMedium) }
    var animationSlow: Animation { .easeInOut(duration: animationDurationSlow) }
    var springAnimation: Animation { .spring(response: animationSpringResponse, dampingFraction: animationSpringDamping) }
    func springAnimation(responseMultiplier: Double = 1.0, dampingMultiplier: Double = 1.0) -> Animation {
        .spring(
            response: animationSpringResponse * responseMultiplier,
            dampingFraction: min(1.0, animationSpringDamping * dampingMultiplier)
        )
    }

    // 코너/보더/스페이싱 기본값 (기존 DS enum 값과 동일)
    var defaultBorderWidth: Double { 1.0 }
    var cardCornerRadius: Double { 10 }
    var inputCornerRadius: Double { 8 }
    var borderOpacity: Double { 0.3 }

    var space2: CGFloat { 2 }
    var space4: CGFloat { 4 }
    var space6: CGFloat { 6 }
    var space8: CGFloat { 8 }
    var space10: CGFloat { 10 }
    var space12: CGFloat { 12 }
    var space16: CGFloat { 16 }
    var space20: CGFloat { 20 }
    var space24: CGFloat { 24 }
    var space32: CGFloat { 32 }

    // 말풍선 기본값
    var bubbleCornerRadius: Double { 12 }
    var userBubbleOpacity: Double { 1.0 }
    var assistantBubbleOpacity: Double { 0.85 }
    var userBubbleColor: Color? { nil }
    var assistantBubbleColor: Color? { nil }
    var messageBorderWidth: Double { 0.5 }
    var showEdgeLight: Bool { true }
    var showInlineAvatar: Bool { true }
    var inlineAvatarSize: Double { 24 }
    var showAgentName: Bool { true }
    var agentNameSize: Double { 13 }

    // 기타
    var codeHighlightTheme: String? { nil }
    var customThemeConfig: CustomTheme? { nil }

    // MARK: - 호환 레이어 (기존 DS.* 코드 무수정 컴파일용)
    /// @deprecated Use theme.cardCornerRadius
    var radiusControl: CGFloat { CGFloat(inputCornerRadius) }
    /// @deprecated Use theme.cardCornerRadius
    var radiusCard: CGFloat { CGFloat(cardCornerRadius) }
    /// @deprecated Use theme.bubbleCornerRadius
    var radiusBubble: CGFloat { CGFloat(bubbleCornerRadius) }
    /// @deprecated Use theme.cardCornerRadius + 6
    var radiusPanel: CGFloat { CGFloat(cardCornerRadius + 6) }

    var dotSmall: CGFloat { 6 }
    var dotStandard: CGFloat { 8 }
    var dotLarge: CGFloat { 10 }

    var cardFill: Color { cardBackground }
    var cardStroke: Color { cardBorder.opacity(borderOpacity) }
    var chipFill: Color { accentColor.opacity(0.12) }
    var sectionHeaderFill: Color { secondaryBackground }
    var inputStroke: Color { inputBorder }

    // 기존 DS.userBubbleGradient 유지
    var userBubbleGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.69, green: 0.32, blue: 0.87), Color(red: 0.48, green: 0.36, blue: 1.0)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var cardInset: CGFloat { space12 }
    var windowInset: CGFloat { space20 }
}

// MARK: - Light Theme (Warm 톤, WCAG AA 준수)

struct LightTheme: ThemeProtocol {
    let isDark = false

    // Primary colors - Warm, rich blacks
    let primaryText = Color(hex: "1a1a18")
    let secondaryText = Color(hex: "555550")
    let primaryBackground = Color(hex: "ffffff")
    let secondaryBackground = Color(hex: "f9f9f7")
    let cardBackground = Color(hex: "ffffff")
    let cardBorder = Color(hex: "d0d0cc")
    let accentColor = Color(hex: "1a1a18")
    let accentColorLight = Color(hex: "3d3d3a")
    let primaryBorder = Color(hex: "d0d0cc")
    let successColor = Color(hex: "15803d")
    let warningColor = Color(hex: "a16207")
    let errorColor = Color(hex: "dc2626")
    let inputBackground = Color(hex: "ffffff")
    let inputBorder = Color(hex: "a8a8a3")

    // Glass - Light mode
    let glassEnabled = false
    let glassOpacityPrimary = 0.25
    let glassOpacitySecondary = 0.18
    let glassOpacityTertiary = 0.10
    let glassBlurRadius = 24
    let glassEdgeLight = Color.white.opacity(0.5)

    // Shadows
    let shadowColor = Color.black
    let shadowOpacity = 0.08
    let cardShadowRadius = 12.0
    let cardShadowRadiusHover = 20.0
    let cardShadowY = 3.0
    let cardShadowYHover = 8.0

    // Chat bubbles
    let bubbleCornerRadius = 16.0
    let userBubbleOpacity = 1.0
    let assistantBubbleOpacity = 0.9
    let messageBorderWidth = 0.5
    let showEdgeLight = true
}

// MARK: - Dark Theme (Cool 톤, WCAG AA 준수)

struct DarkTheme: ThemeProtocol {
    let isDark = true

    // Primary colors - Cool whites
    let primaryText = Color(hex: "f5f5f0")
    let secondaryText = Color(hex: "b8b8b0")
    let primaryBackground = Color(hex: "181816")
    let secondaryBackground = Color(hex: "1e1e1c")
    let cardBackground = Color(hex: "1e1e1c")
    let cardBorder = Color(hex: "3a3a36")
    let accentColor = Color(hex: "f5f5f0")
    let accentColorLight = Color(hex: "d8d8d0")
    let primaryBorder = Color(hex: "3a3a36")
    let successColor = Color(hex: "4ade80")
    let warningColor = Color(hex: "fbbf24")
    let errorColor = Color(hex: "f87171")
    let inputBackground = Color(hex: "282826")
    let inputBorder = Color(hex: "4a4a46")

    // Glass - Dark mode
    let glassEnabled = false
    let glassOpacityPrimary = 0.35
    let glassOpacitySecondary = 0.25
    let glassOpacityTertiary = 0.15
    let glassBlurRadius = 32
    let glassEdgeLight = Color.white.opacity(0.15)

    // Shadows
    let shadowColor = Color.black
    let shadowOpacity = 0.25
    let cardShadowRadius = 16.0
    let cardShadowRadiusHover = 28.0
    let cardShadowY = 4.0
    let cardShadowYHover = 12.0

    // Chat bubbles
    let bubbleCornerRadius = 16.0
    let userBubbleOpacity = 1.0
    let assistantBubbleOpacity = 0.95
    let messageBorderWidth = 0.5
    let showEdgeLight = true
}

// MARK: - Theme Environment Key

/// 테마 프로토콜을 감싸는 구체적 타입 (SwiftUI Environment 저장용)
/// @dynamicMemberLookup으로 내부 value의 프로퍼티에 직접 접근 가능
@dynamicMemberLookup
public struct ThemeBox {
    var value: ThemeProtocol
    
    init(_ value: ThemeProtocol) {
        self.value = value
    }
    
    subscript<T>(dynamicMember keyPath: KeyPath<ThemeProtocol, T>) -> T {
        value[keyPath: keyPath]
    }
}

public struct ThemeEnvironmentKey: EnvironmentKey {
    public static var defaultValue: ThemeBox = ThemeBox(LightTheme())
}

extension EnvironmentValues {
    var theme: ThemeBox {
        get { self[ThemeEnvironmentKey.self] }
        set { self[ThemeEnvironmentKey.self] = newValue }
    }
}

/// 현재 활성 테마에 접근하는 편의 함수 (DesignSystem 등에서 Environment 없이 사용 가능)
@MainActor
public func currentTheme() -> ThemeProtocol {
    ThemeManager.shared.currentTheme
}

// MARK: - View Extensions (테마 적용 편의)

extension View {
    /// 테마 배경 적용
    func themedBackground(_ style: ThemedBackgroundStyle = .primary) -> some View {
        modifier(ThemedBackgroundModifier(style: style))
    }

    /// 테마 카드 스타일 적용
    func themedCard(radius: CGFloat? = nil) -> some View {
        modifier(ThemedCardModifier(radius: radius))
    }

    /// 글라스 배경 적용 (macOS 26+ Liquid Glass, 폴백: regularMaterial)
    func glassBackground(
        enabled: Bool = true,
        opacity: Double? = nil,
        material: NSVisualEffectView.Material? = nil,
        cornerRadius: CGFloat = 16
    ) -> some View {
        modifier(GlassBackgroundModifier(
            enabled: enabled,
            opacity: opacity,
            material: material,
            cornerRadius: cornerRadius
        ))
    }
}

// MARK: - Background Styles

enum ThemedBackgroundStyle { case primary, secondary, tertiary }

// MARK: - Modifiers (currentTheme() 직접 사용 — Environment 주입 불필요)

private struct ThemedBackgroundModifier: ViewModifier {
    let style: ThemedBackgroundStyle

    func body(content: Content) -> some View {
        let theme = currentTheme()
        content.background(backgroundColor(for: theme))
    }

    private func backgroundColor(for theme: ThemeProtocol) -> Color {
        switch style {
        case .primary: return theme.primaryBackground
        case .secondary: return theme.secondaryBackground
        case .tertiary: return theme.tertiaryBackground
        }
    }
}

private struct ThemedCardModifier: ViewModifier {
    let radius: CGFloat?

    func body(content: Content) -> some View {
        let theme = currentTheme()
        content
            .background(theme.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: radius ?? theme.cardCornerRadius, style: .continuous)
                    .stroke(theme.cardBorder.opacity(theme.borderOpacity), lineWidth: theme.defaultBorderWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius ?? theme.cardCornerRadius, style: .continuous))
            .shadow(
                color: theme.shadowColor.opacity(theme.shadowOpacity),
                radius: theme.cardShadowRadius,
                x: 0, y: theme.cardShadowY
            )
    }
}

private struct GlassBackgroundModifier: ViewModifier {
    let enabled: Bool
    let opacity: Double?
    let material: NSVisualEffectView.Material?
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let theme = currentTheme()
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

// MARK: - NSVisualEffectView.Material 편의 확장 (GlassBackground.swift에 정의됨)