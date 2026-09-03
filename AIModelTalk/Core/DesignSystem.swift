import SwiftUI
import AppKit

// MARK: - 통일된 macOS 디자인 토큰 (v3.8 전면 재설계)

/// 앱 전체가 참조하는 단일 디자인 토큰 — 여백·코너·도트·서피스 색상을 여기서만 정의한다.
/// 이전에는 뷰마다 코너(6/8/10/12/22), 도트(7/8/10), 하드코딩 hex가 흩어져 있어
/// 라이트/다크·창마다 이질감이 있었다. (T-166)
enum DS {

    // MARK: - 코너 반경

    /// 텍스트필드·버튼·검색 필드·칩
    static let radiusControl: CGFloat = 6
    /// 카드·행 카드·에디터 시트 내부 요소
    static let radiusCard: CGFloat = 10
    /// 말풍선·입력바·이미지 썸네일
    static let radiusBubble: CGFloat = 12
    /// 플로팅 패널·큰 타일(온보딩 앱 아이콘)
    static let radiusPanel: CGFloat = 16

    // MARK: - 간격 (4pt 그리드)

    static let space2: CGFloat = 2
    static let space4: CGFloat = 4
    static let space6: CGFloat = 6
    static let space8: CGFloat = 8
    static let space10: CGFloat = 10
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24
    /// 카드 내부 패딩
    static let cardInset: CGFloat = 12
    /// 창/시트 기본 패딩
    static let windowInset: CGFloat = 20

    // MARK: - 공급자·상태 도트

    static let dotSmall: CGFloat = 6
    /// 리스트/상태행 도트
    static let dotStandard: CGFloat = 8
    /// 헤더·큰 컨텍스트 도트
    static let dotLarge: CGFloat = 10

    // MARK: - 어댑티브 서피스 (라이트/다크 자동 대응)

    /// 가벼운 카드 채움 — 배경 위 미묘한 구분
    static var cardFill: Color { Color.primary.opacity(0.045) }
    /// 카드·입력 테두리
    static var cardStroke: Color { Color.secondary.opacity(0.16) }
    /// 칩/배지 배경
    static var chipFill: Color { Color.secondary.opacity(0.12) }
    /// 팝오버/피커 섹션 헤더 배경 — 라이트 모드에서도 보이는 어댑티브 색
    static var sectionHeaderFill: Color { Color.secondary.opacity(0.10) }
    /// 입력 필드 배경
    static var inputFill: Color { Color(nsColor: .controlBackgroundColor) }
    /// 입력 필드 테두리
    static var inputStroke: Color { Color(nsColor: .separatorColor) }

    // MARK: - 사용자 말풍선

    /// 브랜드 그라디언트 — 흰 텍스트 대비를 위해 모든 액센트에서 일관 유지 (T-82 설계 결정)
    static var userBubbleGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.69, green: 0.32, blue: 0.87),
                     Color(red: 0.48, green: 0.36, blue: 1.0)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - 공통 뷰 모디파이어

extension View {

    /// 카드 서피스 — 소재 대신 어댑티브 채움 + 얇은 테두리 (macOS 그룹 카드 느낌)
    func dsCard(radius: CGFloat = DS.radiusCard,
                fill: Color = DS.cardFill,
                stroke: Color = DS.cardStroke) -> some View {
        self.background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(stroke, lineWidth: 1))
    }

    /// 공급자/상태 색상 점 — 리스트에서 일관된 크기 (v3.8 통일)
    func dsDot(_ color: Color, size: CGFloat = DS.dotStandard) -> some View {
        Circle().fill(color).frame(width: size, height: size)
    }

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
}