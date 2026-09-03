import SwiftUI

/// 액센트 테마 — 전역 틴트 컬러 선택 (v2.0 T-82)
enum AccentTheme: String, CaseIterable, Identifiable {
    case system
    case blue
    case purple
    case green
    case orange
    case pink

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "시스템"
        case .blue: return "블루"
        case .purple: return "퍼플"
        case .green: return "그린"
        case .orange: return "오렌지"
        case .pink: return "핑크"
        }
    }

    /// nil이면 시스템 액센트 유지
    var color: Color? {
        switch self {
        case .system: return nil
        case .blue: return Color(hex: "#0A84FF")
        case .purple: return Color(hex: "#BF5AF2")
        case .green: return Color(hex: "#30D158")
        case .orange: return Color(hex: "#FF9F0A")
        case .pink: return Color(hex: "#FF375F")
        }
    }

    static func theme(_ raw: String?) -> AccentTheme {
        guard let raw else { return .system }
        return AccentTheme(rawValue: raw) ?? .system
    }
}

extension View {
    /// 설정된 액센트를 전역 틴트로 적용 — 갱신 반영을 위해 호출부가 AppSettings를 관찰해야 함
    func appAccentTint(_ raw: String?) -> some View {
        if let color = AccentTheme.theme(raw).color {
            return AnyView(self.tint(color))
        }
        return AnyView(self)
    }
}
