import SwiftUI
import Combine

// MARK: - ToastManager (Osaurus 스타일 토스트 알림)

/// 앱 전역 토스트 알림 관리자
/// 성공/경고/에러/정보 타입 지원, 캐릭터 일러스트 포함
@MainActor
@Observable
final class ToastManager {
    static let shared = ToastManager()

    private(set) var toasts: [Toast] = []
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    // MARK: - Public API

    @discardableResult
    func success(_ title: String, message: String? = nil, duration: TimeInterval = 3.0) -> Toast {
        let toast = Toast(type: .success, title: title, message: message, duration: duration)
        show(toast)
        return toast
    }

    @discardableResult
    func warning(_ title: String, message: String? = nil, duration: TimeInterval = 4.0) -> Toast {
        let toast = Toast(type: .warning, title: title, message: message, duration: duration)
        show(toast)
        return toast
    }

    @discardableResult
    func error(_ title: String, message: String? = nil, duration: TimeInterval = 5.0) -> Toast {
        let toast = Toast(type: .error, title: title, message: message, duration: duration)
        show(toast)
        return toast
    }

    @discardableResult
    func info(_ title: String, message: String? = nil, duration: TimeInterval = 3.0) -> Toast {
        let toast = Toast(type: .info, title: title, message: message, duration: duration)
        show(toast)
        return toast
    }

    func dismiss(_ toast: Toast) {
        withAnimation(.easeOut(duration: 0.2)) {
            toasts.removeAll { $0.id == toast.id }
        }
    }

    func dismissAll() {
        withAnimation(.easeOut(duration: 0.2)) {
            toasts.removeAll()
        }
    }

    // MARK: - Private

    private func show(_ toast: Toast) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            toasts.append(toast)
        }

        // 자동 해제
        Task {
            try? await Task.sleep(for: .seconds(toast.duration))
            await MainActor.run {
                dismiss(toast)
            }
        }
    }
}

// MARK: - Toast Model

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let type: ToastType
    let title: String
    let message: String?
    let duration: TimeInterval
    let createdAt = Date()

    enum ToastType {
        case success
        case warning
        case error
        case info

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }

        var character: CharacterIllustrations.Character {
            switch self {
            case .success: return .success
            case .warning: return .warning
            case .error: return .error
            case .info: return .info
            }
        }
    }
}

// MARK: - ToastView (개별 토스트 뷰)

struct ToastView: View {
    @Environment(\.theme) private var theme
    let toast: Toast
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // 캐릭터 아이콘
            Image(toast.type.character.assetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)

            // 텍스트
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.primaryText)

                if let message = toast.message {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(2)
                }
            }

            Spacer()

            // 닫기 버튼
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.tertiaryText)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(theme.secondaryBackground))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.cardBackground)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderColor, lineWidth: 1.5)
        )
        .padding(.horizontal, 16)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(y: -20)).combined(with: .scale(scale: 0.95)),
            removal: .opacity.combined(with: .offset(x: 20)).combined(with: .scale(scale: 0.95))
        ))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toast.id)
    }

    private var borderColor: Color {
        switch toast.type {
        case .success: return theme.successColor
        case .warning: return theme.warningColor
        case .error: return theme.errorColor
        case .info: return theme.infoColor
        }
    }
}

// MARK: - ToastContainer (토스트 컨테이너 - 화면 모서리에 표시)

struct ToastContainer: View {
    @Environment(\.theme) private var theme
    @State private var manager = ToastManager.shared

    var body: some View {
        VStack(spacing: 10) {
            ForEach(manager.toasts) { toast in
                ToastView(toast: toast) {
                    manager.dismiss(toast)
                }
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: 380)
    }
}

// MARK: - View Extension for Easy Toast Presentation

extension View {
    /// 토스트 컨테이너 오버레이 추가
    func withToasts() -> some View {
        self.overlay(alignment: .topTrailing) {
            ToastContainer()
                .padding(.top, 60) // 툴바 아래 여유
                .padding(.trailing, 16)
                .zIndex(1000)
        }
    }
}

// MARK: - Preview

#Preview("ToastManager") {
    VStack(spacing: 16) {
        Button("Success") {
            ToastManager.shared.success("완료", message: "작업이 성공적으로 완료되었습니다.")
        }
        .buttonStyle(.borderedProminent)

        Button("Warning") {
            ToastManager.shared.warning("주의", message: "이 작업은 되돌릴 수 없습니다.")
        }
        .buttonStyle(.bordered)

        Button("Error") {
            ToastManager.shared.error("오류", message: "네트워크 연결에 실패했습니다.")
        }
        .buttonStyle(.bordered)
        .tint(.red)

        Button("Info") {
            ToastManager.shared.info("알림", message: "새 버전이 출시되었습니다.")
        }
        .buttonStyle(.bordered)
    }
    .padding()
    .environment(\.theme, ThemeBox(LightTheme()))
    .withToasts()
}