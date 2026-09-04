import SwiftUI

// MARK: - SearchField (Osaurus 스타일 검색 필드)

/// 툴바/전역 검색용 검색 필드
/// Cmd-F 포커스, 클리어 버튼, 플레이스홀더 지원
/// Osaurus의 Common.SearchField 참고
struct SearchField: View {
    @Environment(\.theme) private var theme
    @Binding var text: String
    let placeholder: String
    var onSubmit: (() -> Void)?
    var onClear: (() -> Void)?

    @State private var isFocused = false
    @FocusState private var isFocusedState: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isFocusedState ? theme.accentColor : theme.tertiaryText)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(theme.primaryText)
                .focused($isFocusedState)
                .onSubmit {
                    onSubmit?()
                }
                .onChange(of: isFocusedState) { _, newValue in
                    isFocused = newValue
                }

            if !text.isEmpty {
                Button(action: {
                    text = ""
                    onClear?()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.inputBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            isFocusedState ? theme.focusBorder : theme.inputBorder,
                            lineWidth: isFocusedState ? 2 : 1
                        )
                )
        )
        .animation(theme.animationQuick, value: isFocusedState)
        .frame(minWidth: 200, maxWidth: 360)
    }
}

// MARK: - ToolbarSearchField (툴바 임베디드 검색)

/// .searchable(text:)과 연동되는 툴바 검색 필드
/// macOS 네이티브 툴바 검색 동작 활용
struct ToolbarSearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .frame(width: 280)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
    }
}