import SwiftUI
import Combine
import AppKit

// MARK: - Appearance Mode

/// 시스템 외형 추종 모드
enum AppearanceMode: String, CaseIterable, Codable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .system: return "시스템 설정 따름"
        case .light: return "라이트"
        case .dark: return "다크"
        }
    }

    var systemAppearance: NSAppearance.Name? {
        switch self {
        case .system: return nil
        case .light: return .aqua
        case .dark: return .darkAqua
        }
    }
}

// MARK: - Custom Theme Model

/// 사용자 커스텀 테마 (JSON 직렬화 가능)
public struct CustomTheme: Codable, Identifiable, Equatable, Hashable {
    public var id: String
    var name: String
    var isDark: Bool
    var followsSystemAccent: Bool = true

    // 색상 오버라이드 (nil = 테마 기본값 사용)
    var primaryTextHex: String?
    var secondaryTextHex: String?
    var primaryBackgroundHex: String?
    var secondaryBackgroundHex: String?
    var cardBackgroundHex: String?
    var cardBorderHex: String?
    var accentColorHex: String?
    var primaryBorderHex: String?
    var successColorHex: String?
    var warningColorHex: String?
    var errorColorHex: String?
    var inputBackgroundHex: String?
    var inputBorderHex: String?

    // 글라스 설정
    var glassEnabled: Bool = false
    var glassOpacityPrimary: Double = 0.25
    var glassOpacitySecondary: Double = 0.18
    var glassBlurRadius: Double = 24

    // 배경 커스터마이징
    var background: ThemeBackground = .solid("#ffffff")

    // 타이포그래피
    var primaryFontName: String = "SF Pro"
    var monoFontName: String = "SF Mono"

    // 말풍선
    var bubbleCornerRadius: Double = 16
    var userBubbleOpacity: Double = 1.0
    var assistantBubbleOpacity: Double = 0.9
    var messageBorderWidth: Double = 0.5
    var showEdgeLight: Bool = true
    var showInlineAvatar: Bool = true
    var inlineAvatarSize: Double = 24
    var showAgentName: Bool = true
    var agentNameSize: Double = 13

    // 코드 하이라이트
    var codeHighlightTheme: String?

    // 기본 라이트/다크 프리셋
    static let lightDefault = CustomTheme(
        id: "light-default",
        name: "기본 라이트",
        isDark: false
    )

    static let darkDefault = CustomTheme(
        id: "dark-default",
        name: "기본 다크",
        isDark: true
    )
}

/// 배경 타입
enum ThemeBackground: Codable, Equatable, Hashable {
    case solid(String)           // 단색 (#hex)
    case gradient([String])      // 그라디언트 [#hex, #hex, ...]
    case image(ThemeBackgroundImage) // 이미지

    var type: BackgroundType {
        switch self {
        case .solid: return .solid
        case .gradient: return .gradient
        case .image: return .image
        }
    }

    enum BackgroundType: String, Codable { case solid, gradient, image }

    var solidColor: String? {
        if case .solid(let c) = self { return c }
        return nil
    }

    var gradientColors: [String]? {
        if case .gradient(let c) = self { return c }
        return nil
    }

    var imageConfig: ThemeBackgroundImage? {
        if case .image(let c) = self { return c }
        return nil
    }
}

struct ThemeBackgroundImage: Codable, Equatable, Hashable {
    var assetName: String?       // Assets.xcassets 이름
    var imageFit: ImageFit = .fill
    var imageOpacity: Double = 1.0
    var overlayColor: String?    // 오버레이 색상 #hex
    var overlayOpacity: Double = 0.5

    enum ImageFit: String, Codable, CaseIterable {
        case fill, fit, stretch, tile
        var displayName: String {
            switch self {
            case .fill: return "채우기"
            case .fit: return "맞추기"
            case .stretch: return "늘리기"
            case .tile: return "타일"
            }
        }
    }
}

// MARK: - Theme Manager

/// 테마 시스템 단일 진실 소스
/// - 시스템 외형/액센트 색상 변경 실시간 감지
/// - 사용자 커스텀 테마 설치/관리
/// - 채팅별 테마 오버라이드 지원 (Phase 3: ChatSession.themeID)
@MainActor
@Observable
public final class ThemeManager {
    static let shared = ThemeManager()

    // MARK: Published State

    /// 액티브 동안 didSet 발화를 잠금 (init)·저장소 복원 시 nonisolated Observation 경로 크래시 방지 (v0.3.1)
    private var isRestoringState = false

    /// 재진입 잠금 — appearanceMode/액센트 didSet 연쇄에서 applyResolvedTheme이 동기 재귀로 쌓이는 것 방지 (v0.3.2)
    private var isApplyingResolvedTheme = false

    /// 현재 활성 테마 (전역, Environment 주입용)
    var currentTheme: ThemeProtocol = LightTheme()

    /// 채팅창 전용 테마 오버라이드 (에이전트/세션별, Phase 3에서 ChatSession.themeID로 연결)
    var chatTheme: ThemeProtocol = LightTheme()

    /// 시스템 외형 추종 모드
    var appearanceMode: AppearanceMode = .system {
        didSet {
            guard !isRestoringState else { return }
            applyResolvedTheme()
        }
    }

    /// 시스템 액센트 색상 따름
    var followsSystemAccent: Bool = true {
        didSet {
            guard !isRestoringState else { return }
            applyResolvedTheme()
        }
    }

    /// 설치된 커스텀 테마 목록
    var installedThemes: [CustomTheme] = [] {
        didSet { savePreferences() }
    }

    /// 현재 적용된 커스텀 테마 (nil = 내장 라이트/다크)
    var activeCustomTheme: CustomTheme? {
        didSet {
            guard !isRestoringState else { return }
            applyResolvedTheme()
        }
    }

    // MARK: Private

    private let store = ThemeConfigurationStore.shared
    private var appearanceObserver: NSObjectProtocol?
    private var accentObserver: NSObjectProtocol?

    private init() {
        isRestoringState = true
        loadPreferences()
        observeSystemChanges()
        isRestoringState = false
        applyResolvedTheme()
    }

    // MARK: Public API

    /// 외형 모드 변경 (시스템/라이트/다크)
    func setAppearanceMode(_ mode: AppearanceMode) {
        appearanceMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "appearanceMode")
    }

    /// AppSettings.appearance 브리지용 — NSApp 외형 변경 시 테마 동기화 (v0.2.6 축1a)
    func syncAppearanceMode(_ mode: AppearanceMode) {
        guard appearanceMode != mode else { return }
        appearanceMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "appearanceMode")
    }

    /// 액센트 색상 따름 설정
    func setFollowsSystemAccent(_ follows: Bool) {
        followsSystemAccent = follows
        UserDefaults.standard.set(follows, forKey: "followsSystemAccent")
    }

    /// 커스텀 테마 설치/업데이트
    func installCustomTheme(_ theme: CustomTheme) {
        if let idx = installedThemes.firstIndex(where: { $0.id == theme.id }) {
            installedThemes[idx] = theme
        } else {
            installedThemes.append(theme)
        }
    }

    /// 커스텀 테마 제거
    func removeCustomTheme(id: String) {
        installedThemes.removeAll { $0.id == id }
        if activeCustomTheme?.id == id {
            activeCustomTheme = nil
        }
    }

    /// 커스텀 테마 활성화
    func activateCustomTheme(_ theme: CustomTheme?) {
        activeCustomTheme = theme
    }

    /// 채팅창 테마만 변경 (전역 currentTheme 영향 없음)
    func applyChatTheme(_ theme: CustomTheme, animated: Bool = true) {
        let themeInstance = CustomizableTheme(config: theme)
        if animated {
            withAnimation(.easeInOut(duration: 0.3)) {
                chatTheme = themeInstance
            }
        } else {
            chatTheme = themeInstance
        }
    }

    /// 채팅 테마를 전역 테마로 동기화
    func syncChatTheme(animated: Bool = true) {
        if animated {
            withAnimation(.easeInOut(duration: 0.3)) {
                chatTheme = currentTheme
            }
        } else {
            chatTheme = currentTheme
        }
    }

    // MARK: Private Implementation

    private func loadPreferences() {
        // 외형 모드
        if let raw = UserDefaults.standard.string(forKey: "appearanceMode"),
           let mode = AppearanceMode(rawValue: raw) {
            appearanceMode = mode
        }

        // 액센트 따름
        followsSystemAccent = UserDefaults.standard.bool(forKey: "followsSystemAccent")

        // 커스텀 테마 목록
        if let data = UserDefaults.standard.data(forKey: "installedThemes"),
           let themes = try? JSONDecoder().decode([CustomTheme].self, from: data) {
            installedThemes = themes
        }

        // 활성 커스텀 테마
        if let data = UserDefaults.standard.data(forKey: "activeCustomTheme"),
           let theme = try? JSONDecoder().decode(CustomTheme.self, from: data) {
            activeCustomTheme = theme
        }

        DebugLogger.shared.info("THEME", "테마 매니저 초기화: mode=\(appearanceMode.rawValue), custom=\(activeCustomTheme?.name ?? "none")")
    }

    private func savePreferences() {
        UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode")
        UserDefaults.standard.set(followsSystemAccent, forKey: "followsSystemAccent")
        if let data = try? JSONEncoder().encode(installedThemes) {
            UserDefaults.standard.set(data, forKey: "installedThemes")
        }
        if let theme = activeCustomTheme,
           let data = try? JSONEncoder().encode(theme) {
            UserDefaults.standard.set(data, forKey: "activeCustomTheme")
        }
    }

    private func observeSystemChanges() {
        // 시스템 외형 변경 감지
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applySystemAppearanceChange()
            }
        }

        // 시스템 액센트 색상 변경 감지
        accentObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleColorPreferencesChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applySystemAccentChange()
            }
        }
    }

    private func applySystemAppearanceChange() {
        guard appearanceMode == .system, activeCustomTheme == nil else { return }
        applyResolvedTheme(for: .system, animated: true)
        NotificationCenter.default.post(name: .globalThemeChanged, object: nil)
    }

    private func applySystemAccentChange() {
        if let custom = activeCustomTheme {
            guard custom.followsSystemAccent else { return }
            applyCustomTheme(custom, persist: false)
            return
        }
        applyResolvedTheme(for: appearanceMode, animated: true)
        NotificationCenter.default.post(name: .globalThemeChanged, object: nil)
    }

    private func applyResolvedTheme(for mode: AppearanceMode? = nil, animated: Bool = true) {
        // 재진입 가드: didSet 연쇄(외형→액센트→커스텀 테마)에서 동기 재귀 방지 (v0.3.2)
        guard !isApplyingResolvedTheme else { return }
        isApplyingResolvedTheme = true
        defer { isApplyingResolvedTheme = false }

        let effectiveMode = mode ?? appearanceMode
        let resolvedTheme: ThemeProtocol

        if let custom = activeCustomTheme {
            resolvedTheme = CustomizableTheme(config: custom)
        } else {
            // 시스템 다크 판별은 NSApp.effectiveAppearance 대신 UserDefaults 기반 —
            // effectiveAppearance 조회가 테마 didSet 경로에서 무한 재귀(스택 가드 SIGSEGV)를 유발 (v0.3.2 크래시 수정)
            let isDark = effectiveMode == .dark
                || (effectiveMode == .system && systemInterfaceIsDark)
            resolvedTheme = isDark ? DarkTheme() : LightTheme()
        }

        // MainActor 격리 보장 — didSet 경로는 nonisolated 컨텍스트일 수 있어
        // assumeIsolated 대신 검증된 메인 스레드 hop 방식 사용 (v0.3.1 트랩 재발 방지)
        let apply: () -> Void = {
            if animated {
                withAnimation(.easeInOut(duration: 0.3)) { self.currentTheme = resolvedTheme }
            } else {
                self.currentTheme = resolvedTheme
            }
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async { apply() }
        }
    }

    /// 시스템 인터페이스(다크 모드) 여부 — macOS 다크 모드로 전환하면
    /// UserDefaults "AppleInterfaceStyle"이 "Dark"로 설정된다. 라이트면 값이 없거나 "Aqua".
    private var systemInterfaceIsDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    private func applyCustomTheme(_ custom: CustomTheme, persist: Bool) {
        let themeInstance = CustomizableTheme(config: custom)
        currentTheme = themeInstance
        if persist {
            activeCustomTheme = custom
        }
    }
}

// MARK: - CustomizableTheme (CustomTheme -> ThemeProtocol 어댑터)

/// CustomTheme 설정을 ThemeProtocol로 변환하는 래퍼
/// 내장 LightTheme/DarkTheme를 베이스로 커스텀 값만 오버라이드
@MainActor
final class CustomizableTheme: ThemeProtocol {
    let baseTheme: ThemeProtocol
    let config: CustomTheme

    init(config: CustomTheme) {
        self.config = config
        self.baseTheme = config.isDark ? DarkTheme() : LightTheme()
    }

    // MARK: 색상 (커스텀 값 있으면 오버라이드)
    var primaryText: Color { color(from: config.primaryTextHex) ?? baseTheme.primaryText }
    var secondaryText: Color { color(from: config.secondaryTextHex) ?? baseTheme.secondaryText }
    var primaryBackground: Color { color(from: config.primaryBackgroundHex) ?? baseTheme.primaryBackground }
    var secondaryBackground: Color { color(from: config.secondaryBackgroundHex) ?? baseTheme.secondaryBackground }
    var cardBackground: Color { color(from: config.cardBackgroundHex) ?? baseTheme.cardBackground }
    var cardBorder: Color { color(from: config.cardBorderHex) ?? baseTheme.cardBorder }
    var accentColor: Color { color(from: config.accentColorHex) ?? baseTheme.accentColor }
    var accentColorLight: Color { baseTheme.accentColorLight }
    var primaryBorder: Color { color(from: config.primaryBorderHex) ?? baseTheme.primaryBorder }
    var successColor: Color { color(from: config.successColorHex) ?? baseTheme.successColor }
    var warningColor: Color { color(from: config.warningColorHex) ?? baseTheme.warningColor }
    var errorColor: Color { color(from: config.errorColorHex) ?? baseTheme.errorColor }
    var inputBackground: Color { color(from: config.inputBackgroundHex) ?? baseTheme.inputBackground }
    var inputBorder: Color { color(from: config.inputBorderHex) ?? baseTheme.inputBorder }

    // MARK: 글라스
    var glassEnabled: Bool { config.glassEnabled }
    var glassOpacityPrimary: Double { config.glassOpacityPrimary }
    var glassOpacitySecondary: Double { config.glassOpacitySecondary }
    var glassOpacityTertiary: Double { baseTheme.glassOpacityTertiary }
    var glassBlurRadius: Double { config.glassBlurRadius }
    var glassMaterial: NSVisualEffectView.Material { baseTheme.glassMaterial }
    var glassTintColor: Color? { baseTheme.glassTintColor }
    var glassTintOpacity: Double { baseTheme.glassTintOpacity }
    var windowBackingOpacity: Double { baseTheme.windowBackingOpacity }

    // MARK: 그림자
    var shadowColor: Color { baseTheme.shadowColor }
    var shadowOpacity: Double { baseTheme.shadowOpacity }
    var cardShadowRadius: Double { baseTheme.cardShadowRadius }
    var cardShadowRadiusHover: Double { baseTheme.cardShadowRadiusHover }
    var cardShadowY: Double { baseTheme.cardShadowY }
    var cardShadowYHover: Double { baseTheme.cardShadowYHover }

    // MARK: 타이포그래피
    var primaryFontName: String { config.primaryFontName }
    var monoFontName: String { config.monoFontName }
    var titleSize: Double { baseTheme.titleSize }
    var headingSize: Double { baseTheme.headingSize }
    var bodySize: Double { baseTheme.bodySize }
    var captionSize: Double { baseTheme.captionSize }
    var codeSize: Double { baseTheme.codeSize }

    // MARK: 애니메이션 (베이스 테마 값 사용)
    var animationDurationQuick: Double { baseTheme.animationDurationQuick }
    var animationDurationMedium: Double { baseTheme.animationDurationMedium }
    var animationDurationSlow: Double { baseTheme.animationDurationSlow }
    var animationSpringResponse: Double { baseTheme.animationSpringResponse }
    var animationSpringDamping: Double { baseTheme.animationSpringDamping }

    // MARK: 코너/보더/스페이싱
    var defaultBorderWidth: Double { baseTheme.defaultBorderWidth }
    var cardCornerRadius: Double { baseTheme.cardCornerRadius }
    var inputCornerRadius: Double { baseTheme.inputCornerRadius }
    var borderOpacity: Double { baseTheme.borderOpacity }
    var space2: CGFloat { baseTheme.space2 }
    var space4: CGFloat { baseTheme.space4 }
    var space6: CGFloat { baseTheme.space6 }
    var space8: CGFloat { baseTheme.space8 }
    var space10: CGFloat { baseTheme.space10 }
    var space12: CGFloat { baseTheme.space12 }
    var space16: CGFloat { baseTheme.space16 }
    var space20: CGFloat { baseTheme.space20 }
    var space24: CGFloat { baseTheme.space24 }
    var space32: CGFloat { baseTheme.space32 }

    // MARK: 말풍선
    var bubbleCornerRadius: Double { config.bubbleCornerRadius }
    var userBubbleOpacity: Double { config.userBubbleOpacity }
    var assistantBubbleOpacity: Double { config.assistantBubbleOpacity }
    var userBubbleColor: Color? { baseTheme.userBubbleColor }
    var assistantBubbleColor: Color? { baseTheme.assistantBubbleColor }
    var messageBorderWidth: Double { config.messageBorderWidth }
    var showEdgeLight: Bool { config.showEdgeLight }
    var showInlineAvatar: Bool { config.showInlineAvatar }
    var inlineAvatarSize: Double { config.inlineAvatarSize }
    var showAgentName: Bool { config.showAgentName }
    var agentNameSize: Double { config.agentNameSize }

    // MARK: 기타
    var codeHighlightTheme: String? { config.codeHighlightTheme }
    var customThemeConfig: CustomTheme? { config }
    var isDark: Bool { config.isDark }

    // MARK: Private Helper

    private func color(from hex: String?) -> Color? {
        guard let hex, !hex.isEmpty else { return nil }
        return Color(hex: hex)
    }
}

// MARK: - NSAppearance Extension

extension NSAppearance {
    var isDarkMode: Bool {
        name == .darkAqua || name == .vibrantDark ||
        name == .accessibilityHighContrastDarkAqua ||
        name == .accessibilityHighContrastVibrantDark
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let globalThemeChanged = Notification.Name("globalThemeChanged")
}