import SwiftUI
import AppKit

// MARK: - 통일된 macOS 디자인 토큰 (v3.8 → ThemeProtocol 연동)

/// @deprecated ThemeProtocol 기반 테마 시스템으로 이전 중.
/// 기존 `DS.*` 코드가 무수정 컴파일되도록 호환 레이어 제공.
/// 신규 코드는 `@Environment(\.theme)` 및 `themedCard()`/`themedBackground()`/`glassBackground()` 사용 권장.
enum DS {

    // MARK: - 코너 반경 (ThemeProtocol 기본값과 동일)

    /// 텍스트필드·버튼·검색 필드·칩 — ThemeProtocol.inputCornerRadius (8)
    static let radiusControl: CGFloat = 6
    /// 카드·행 카드·에디터 시트 내부 요소 — ThemeProtocol.cardCornerRadius (10)
    static let radiusCard: CGFloat = 10
    /// 말풍선·입력바·이미지 썸네일 — ThemeProtocol.bubbleCornerRadius (12/16)
    static let radiusBubble: CGFloat = 12
    /// 플로팅 패널·큰 타일(온보딩 앱 아이콘) — cardCornerRadius + 6
    static let radiusPanel: CGFloat = 16

    // MARK: - 간격 (4pt 그리드) — ThemeProtocol.space*와 동일

    static let space2: CGFloat = 2
    static let space4: CGFloat = 4
    static let space6: CGFloat = 6
    static let space8: CGFloat = 8
    static let space10: CGFloat = 10
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24
    /// 카드 내부 패딩 — ThemeProtocol.space12
    static let cardInset: CGFloat = 12
    /// 창/시트 기본 패딩 — ThemeProtocol.space20
    static let windowInset: CGFloat = 20

    // MARK: - 공급자·상태 도트

    static let dotSmall: CGFloat = 6
    /// 리스트/상태행 도트
    static let dotStandard: CGFloat = 8
    /// 헤더·큰 컨텍스트 도트
    static let dotLarge: CGFloat = 10

    // MARK: - 어댑티브 서피스 (라이트/다크 자동 대응) — ThemeProtocol 속성 위임

    /// @deprecated theme.cardBackground 사용
    static var cardFill: Color { Color.primary.opacity(0.045) }
    /// @deprecated theme.cardBorder.opacity(theme.borderOpacity) 사용
    static var cardStroke: Color { Color.secondary.opacity(0.16) }
    /// @deprecated theme.accentColor.opacity(0.12) 사용
    static var chipFill: Color { Color.secondary.opacity(0.12) }
    /// @deprecated theme.secondaryBackground 사용
    static var sectionHeaderFill: Color { Color.secondary.opacity(0.10) }
    /// @deprecated theme.inputBackground 사용
    static var inputFill: Color { Color(nsColor: .controlBackgroundColor) }
    /// @deprecated theme.inputBorder 사용
    static var inputStroke: Color { Color(nsColor: .separatorColor) }

    // MARK: - 사용자 말풍선

    /// 브랜드 그라디언트 — 흰 텍스트 대비를 위해 모든 액센트에서 일관 유지 (T-82 설계 결정)
    /// @deprecated theme.userBubbleGradient 사용 (ThemeProtocol 기본 구현에서 제공)
    static var userBubbleGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.69, green: 0.32, blue: 0.87),
                     Color(red: 0.48, green: 0.36, blue: 1.0)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - 공통 뷰 모디파이어 (기존 DS.* 기반 — 호환용)

extension View {

    /// @deprecated `.themedCard()` 사용
    /// 카드 서피스 — 소재 대신 어댑티브 채움 + 얇은 테두리 (macOS 그룹 카드 느낌)
    func dsCard(radius: CGFloat = DS.radiusCard,
                fill: Color = DS.cardFill,
                stroke: Color = DS.cardStroke) -> some View {
        self.background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(stroke, lineWidth: 1))
    }

    /// @deprecated `theme.dsDot()` 또는 `theme.font()` 등 직접 사용
    /// 공급자/상태 색상 점 — 리스트에서 일관된 크기 (v3.8 통일)
    func dsDot(_ color: Color, size: CGFloat = DS.dotStandard) -> some View {
        Circle().fill(color).frame(width: size, height: size)
    }

    /// @deprecated `theme.dsBadge()` 사용
    /// 소스/구분 배지 — 텍스트 + 어댑티브 캡슐
    func dsBadge(_ text: String,
                 color: Color = .secondary,
                 textColor: Color = .secondary,
                 fontSize: CGFloat = 8) -> some View {
        Text(text)
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(textColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    /// 가로 라디오 선택 칩 배경 — 선택 시 액센트 채움 + 테두리 (설정 '외관/액센트' 가로 선택)
    func radioChipBackground(isSelected: Bool, theme: ThemeBox) -> some View {
        background(
            RoundedRectangle(cornerRadius: theme.inputCornerRadius, style: .continuous)
                .fill(isSelected ? theme.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.inputCornerRadius, style: .continuous)
                .strokeBorder(
                    isSelected ? theme.accentColor.opacity(0.5) : theme.cardBorder.opacity(theme.borderOpacity),
                    lineWidth: 1
                )
        )
    }
}