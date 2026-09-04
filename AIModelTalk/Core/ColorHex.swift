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
}