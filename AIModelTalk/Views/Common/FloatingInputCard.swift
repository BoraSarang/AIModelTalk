import SwiftUI

// MARK: - FloatingInputCard (Osaurus 스타일 플로팅 입력 카드)

/// 글라스 배경 + 그라데이션 상단 크롬을 가진 플로팅 입력 카드
/// 채팅 입력창, 퀵챗, 팝오버 입력 등에서 사용
/// Osaurus의 Chat.FloatingInputCard 참고
struct FloatingInputCard<Content: View>: View {
    @Environment(\.theme) private var theme
    let content: Content
    var showsBorder: Bool = true
    var cornerRadius: CGFloat = 16
    var glassEnabled: Bool = true

    init(
        showsBorder: Bool = true,
        cornerRadius: CGFloat = 16,
        glassEnabled: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.showsBorder = showsBorder
        self.cornerRadius = cornerRadius
        self.glassEnabled = glassEnabled
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(
                ZStack {
                    // 글라스 배경
                    if glassEnabled && theme.glassEnabled {
                        if #available(macOS 26.0, *) {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(.clear)
                                .glassEffect(
                                    .regular
                                        .tint(theme.glassTintColor ?? .clear)
                                        .interactive(),
                                    in: .rect(cornerRadius: cornerRadius)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(theme.primaryBackground.opacity(theme.glassOpacityPrimary))
                                .background(
                                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                        .fill(.regularMaterial)
                                )
                        }
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(theme.primaryBackground)
                    }

                    // 상단 그라데이션 크롬 (Osaurus 스타일)
                    VStack {
                        LinearGradient(
                            colors: [
                                theme.accentColor.opacity(0.12),
                                theme.accentColor.opacity(0.04),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 1)
                        .blendMode(.overlay)

                        Spacer()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)

                    // 보더
                    if showsBorder {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(theme.cardBorder.opacity(theme.borderOpacity), lineWidth: 1)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: theme.shadowColor.opacity(theme.shadowOpacity),
                radius: 12, y: 4
            )
    }
}

// MARK: - ChatInputCard (채팅 전용 입력 카드)

/// 채팅 입력창에 특화된 플로팅 카드
/// 텍스트 에디터 + 툴바 + 토큰 미터 + 전송 버튼 통합
struct ChatInputCard: View {
    @Environment(\.theme) private var theme
    @Binding var text: String
    let onSend: () -> Void
    let onStop: (() -> Void)?
    let onAttach: (() -> Void)?
    let onWebSearchToggle: (() -> Void)?
    let onMore: (() -> Void)?
    let isLoading: Bool
    let canSend: Bool
    let webSearchEnabled: Bool
    let tokenCount: Int
    let maxTokens: Int
    var isWebSearchActive: Bool = false
    var attachmentsCount: Int = 0

    @State private var isFocused = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        FloatingInputCard {
            VStack(spacing: 8) {
                // 첨부 썸네일 행
                if attachmentsCount > 0 {
                    attachmentThumbnails
                }

                // 메인 입력 영역
                HStack(alignment: .bottom, spacing: 12) {
                    // 툴바 버튼들 (좌측)
                    HStack(spacing: 8) {
                        // 모델 선택 (별도 컴포넌트에서 주입)
                        // SkillPicker (별도 컴포넌트에서 주입)

                        // 첨부
                        if let onAttach = onAttach {
                            Menu {
                                Button(action: onAttach) {
                                    Label("파일 선택…", systemImage: "photo.on.rectangle")
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: 13))
                                    Text("첨부")
                                        .font(.caption)
                                }
                                .foregroundStyle(theme.secondaryText)
                            }
                            .menuStyle(.borderlessButton)
                            .help("이미지 첨부 — 붙여넣기(⌘V)로도 첨부")
                        }

                        // 웹 검색 토글
                        if let onWebSearchToggle = onWebSearchToggle {
                            Button(action: onWebSearchToggle) {
                                HStack(spacing: 3) {
                                    Image(systemName: "globe")
                                        .font(.system(size: 13))
                                    Text("웹")
                                        .font(.caption)
                                }
                                .foregroundStyle(webSearchEnabled ? theme.accentColor : theme.secondaryText)
                                .padding(.horizontal, 4)
                                .background(
                                    webSearchEnabled
                                        ? theme.accentColor.opacity(0.15)
                                        : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                            .help(webSearchEnabled ? "웹 검색 켜짐" : "이번 전송에 웹 검색 사용")
                        }

                        // 더보기 메뉴
                        if let onMore = onMore {
                            Menu {
                                Button(action: onMore) {
                                    Label("더 보기", systemImage: "ellipsis.circle")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(theme.secondaryText)
                            }
                            .menuStyle(.borderlessButton)
                            .help("더 보기")
                        }
                    }

                    // 텍스트 에디터
                    TextEditor(text: $text)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 36, maxHeight: 120)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(theme.inputBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(editorFocused ? theme.focusBorder : theme.inputBorder, lineWidth: editorFocused ? 2 : 1)
                        )
                        .focused($editorFocused)

                    Spacer()

                    // 토큰 미터
                    tokenMeter

                    // 전송/중지 버튼
                    if isLoading, let onStop = onStop {
                        Button(action: onStop) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(theme.errorColor)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(".", modifiers: .command)
                        .help("응답 중지 (Cmd+.)")
                    } else {
                        Button(action: onSend) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(canSend ? theme.accentColor : theme.secondaryText.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend)
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                }
            }
        }
        .animation(theme.animationQuick, value: editorFocused)
    }

    private var attachmentThumbnails: some View {
        HStack(spacing: 6) {
            Image(systemName: "paperclip")
                .font(.caption2)
                .foregroundStyle(theme.secondaryText)
            Text("\(attachmentsCount)개 첨부")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var tokenMeter: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(tokenCount) / \(maxTokens)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(tokenColor)
            ProgressView(value: Double(tokenCount), total: Double(maxTokens))
                .frame(width: 60)
                .tint(tokenColor)
        }
    }

    private var tokenColor: Color {
        let ratio = Double(tokenCount) / Double(maxTokens)
        if ratio > 0.9 { return theme.errorColor }
        if ratio > 0.7 { return theme.warningColor }
        return theme.secondaryText
    }
}

// MARK: - QuickChatInputCard (퀵챗/팝오버용 컴팩트 입력 카드)

struct QuickChatInputCard: View {
    @Environment(\.theme) private var theme
    @Binding var text: String
    let onSend: () -> Void
    let isLoading: Bool
    let canSend: Bool
    let placeholder: String

    @FocusState private var editorFocused: Bool

    var body: some View {
        FloatingInputCard(cornerRadius: 12) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...4)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(theme.inputBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(editorFocused ? theme.focusBorder : theme.inputBorder, lineWidth: editorFocused ? 2 : 1)
                    )
                    .focused($editorFocused)
                    .onSubmit { onSend() }

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(canSend ? theme.accentColor : theme.secondaryText.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Preview

#Preview("FloatingInputCard") {
    FloatingInputCard {
        VStack(alignment: .leading, spacing: 12) {
            Text("플로팅 입력 카드")
                .font(.headline)
            Text("글라스 배경 + 그라데이션 크롬")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    .frame(width: 400)
    .padding()
    .environment(\.theme, ThemeBox(LightTheme()))
}

#Preview("ChatInputCard") {
    ChatInputCard(
        text: .constant(""),
        onSend: {},
        onStop: nil,
        onAttach: nil,
        onWebSearchToggle: nil,
        onMore: nil,
        isLoading: false,
        canSend: true,
        webSearchEnabled: true,
        tokenCount: 1200,
        maxTokens: 4096
    )
    .frame(width: 700)
    .padding()
    .environment(\.theme, ThemeBox(LightTheme()))
}