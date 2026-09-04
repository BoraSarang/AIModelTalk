import SwiftUI

// MARK: - FittedSheetFrame (Osaurus 스타일 시트 프레임)

/// 시트 크기 표준화 + 비대칭 spring 트랜지션
/// Osaurus의 Common.FittedSheetFrame 참고
/// 기본 크기: 540×620
struct FittedSheetFrame: ViewModifier {
    let width: CGFloat
    let height: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(minWidth: width, maxWidth: width, minHeight: height, maxHeight: height)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
            )
    }
}

extension View {
    /// 표준 시트 프레임 적용 (기본 540×620)
    func fittedSheetFrame(width: CGFloat = 540, height: CGFloat = 620) -> some View {
        modifier(FittedSheetFrame(width: width, height: height))
    }
}

// MARK: - Sheet Transition Helpers

/// Osaurus 스타일 비대칭 spring 트랜지션
/// 등장: opacity + offset(x: 30) + scale(0.98)
/// 퇴장: opacity + offset(x: -30) + scale(0.98)
extension AnyTransition {
    static var sheetAsymmetric: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .offset(x: 30))
                .combined(with: .scale(scale: 0.98)),
            removal: .opacity
                .combined(with: .offset(x: -30))
                .combined(with: .scale(scale: 0.98))
        )
    }

    /// 표준 spring 애니메이션 (response: 0.35, dampingFraction: 0.85)
    static var sheetSpring: Animation {
        .spring(response: 0.35, dampingFraction: 0.85)
    }
}