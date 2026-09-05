import SwiftUI

/// hex 문자열 → Color 변환 (#RRGGBB / #RGB 지원)
/// 프로젝트 기능 제거(v0.1.2)로 Project.swift가 삭제되어 Core/ColorHex.swift로 이전.
extension Color {
    init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard [3, 6].contains(value.count) else {
            self.init(.clear)
            return
        }

        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }
        guard let rgb = UInt64(value, radix: 16) else {
            self.init(.clear)
            return
        }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    /// sRGB #RRGGBB hex 문자열로 변환 — 테마 빌더 저장용 (v0.3.1)
    func toHexString() -> String? {
        guard let ns = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// 배경색 밝기 기반 전경 글자색 판정 — 밝은 배경(흰색 계열)이면 검정, 어두운 배경이면 흰색.
    /// 다크 테마의 밝은 `accentColor` 위에서 `.white` 글자로 글자가 안 보이던 문제의 전역 해결책 (T-324).
    var isLightColor: Bool {
        guard let ns = NSColor(self).usingColorSpace(.sRGB) else { return false }
        let luminance = 0.2126 * ns.redComponent + 0.7152 * ns.greenComponent + 0.0722 * ns.blueComponent
        return luminance > 0.6
    }
}