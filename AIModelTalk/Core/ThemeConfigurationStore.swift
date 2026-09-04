import Foundation
import SwiftUI

/// 테마 설정 영속화 저장소
/// UserDefaults 기반, CustomTheme 배열 및 활성 테마 저장
@MainActor
final class ThemeConfigurationStore {
    static let shared = ThemeConfigurationStore()

    private let defaults = UserDefaults.standard
    private let installedThemesKey = "installedThemes"
    private let activeCustomThemeKey = "activeCustomTheme"
    private let appearanceModeKey = "appearanceMode"
    private let followsSystemAccentKey = "followsSystemAccent"

    private init() {}

    // MARK: - 설치된 테마 목록

    func loadInstalledThemes() -> [CustomTheme] {
        guard let data = defaults.data(forKey: installedThemesKey),
              let themes = try? JSONDecoder().decode([CustomTheme].self, from: data) else {
            return []
        }
        return themes
    }

    func saveInstalledThemes(_ themes: [CustomTheme]) {
        if let data = try? JSONEncoder().encode(themes) {
            defaults.set(data, forKey: installedThemesKey)
        }
    }

    // MARK: - 활성 커스텀 테마

    func loadActiveCustomTheme() -> CustomTheme? {
        guard let data = defaults.data(forKey: activeCustomThemeKey),
              let theme = try? JSONDecoder().decode(CustomTheme.self, from: data) else {
            return nil
        }
        return theme
    }

    func saveActiveCustomTheme(_ theme: CustomTheme?) {
        if let theme, let data = try? JSONEncoder().encode(theme) {
            defaults.set(data, forKey: activeCustomThemeKey)
        } else {
            defaults.removeObject(forKey: activeCustomThemeKey)
        }
    }

    // MARK: - 외형 모드

    func loadAppearanceMode() -> AppearanceMode {
        if let raw = defaults.string(forKey: appearanceModeKey),
           let mode = AppearanceMode(rawValue: raw) {
            return mode
        }
        return .system
    }

    func saveAppearanceMode(_ mode: AppearanceMode) {
        defaults.set(mode.rawValue, forKey: appearanceModeKey)
    }

    // MARK: - 시스템 액센트 따름

    func loadFollowsSystemAccent() -> Bool {
        defaults.bool(forKey: followsSystemAccentKey)
    }

    func saveFollowsSystemAccent(_ follows: Bool) {
        defaults.set(follows, forKey: followsSystemAccentKey)
    }

    // MARK: - 전체 리셋 (디버그/테스트용)

    func resetAll() {
        defaults.removeObject(forKey: installedThemesKey)
        defaults.removeObject(forKey: activeCustomThemeKey)
        defaults.removeObject(forKey: appearanceModeKey)
        defaults.removeObject(forKey: followsSystemAccentKey)
    }
}