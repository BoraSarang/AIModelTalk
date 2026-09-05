import SwiftUI
import AppKit

// MARK: - 테마 빌더 (v0.3.1) — 핵심 색상 + 글라스 + 말풍선을 라이브 미리보기와 함께 편집

/// 테마 생성·편집 시트 — GeneralSettingsView의 '테마 관리' 섹션에서 연다.
/// 저장 즉시 설치(installCustomTheme) + 활성화(activateCustomTheme)된다.
struct ThemeBuilderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var appTheme
    private let themeManager = ThemeManager.shared

    @State private var theme: CustomTheme

    /// 현재 편집 중 테마의 기본 테마 (미지정 hex가 베이스에서 대체)
    private var baseTheme: ThemeProtocol {
        theme.isDark ? DarkTheme() : LightTheme()
    }

    init(theme: CustomTheme? = nil) {
        if let theme {
            _theme = State(initialValue: theme)
        } else {
            _theme = State(initialValue: CustomTheme(id: UUID().uuidString, name: "새 테마", isDark: false))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: appTheme.space12) {
                    identityCard
                    colorCard
                    glassCard
                    bubbleCard
                    previewCard
                }
                .padding(appTheme.space16)
            }

            footer
        }
        .frame(width: 560, height: 640)
        .background(appTheme.primaryBackground)
    }

    // MARK: - 헤더/푸터

    private var header: some View {
        HStack {
            Text(isNew ? "새 테마 만들기" : "테마 편집")
                .font(.headline)
                .foregroundStyle(appTheme.primaryText)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(appTheme.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(appTheme.space16)
        .background(appTheme.secondaryBackground)
        .overlay(alignment: .bottom) {
            Divider().overlay(appTheme.cardBorder.opacity(appTheme.borderOpacity))
        }
    }

    private var isNew: Bool {
        !themeManager.installedThemes.contains { $0.id == theme.id }
    }

    private var footer: some View {
        HStack {
            Text("저장하면 전체 창에 즉시 적용됩니다.")
                .font(.caption)
                .foregroundStyle(appTheme.secondaryText)
            Spacer()
            Button("취소", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("저장") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(theme.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(appTheme.space16)
        .background(appTheme.secondaryBackground)
        .overlay(alignment: .top) {
            Divider().overlay(appTheme.cardBorder.opacity(appTheme.borderOpacity))
        }
    }

    // MARK: - 기본 설정 카드

    private var identityCard: some View {
        ThemedSettingsCard("기본") {
            VStack(alignment: .leading, spacing: appTheme.space10) {
                HStack {
                    Text("이름")
                        .font(.callout)
                        .foregroundStyle(appTheme.primaryText)
                    Spacer()
                    TextField("", text: $theme.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }
                HStack(spacing: appTheme.space16) {
                    Toggle("다크", isOn: $theme.isDark)
                        .toggleStyle(.switch)
                    Toggle("시스템 액센트 따름", isOn: $theme.followsSystemAccent)
                        .toggleStyle(.switch)
                    Spacer()
                }
            }
        }
    }

    // MARK: - 색상 카드

    private var colorCard: some View {
        ThemedSettingsCard("색상") {
            VStack(alignment: .leading, spacing: appTheme.space10) {
                ThemedSettingsCaption("비워두면 \(theme.isDark ? "다크" : "라이트") 기본값을 사용합니다. [기본] 버튼으로 초기화할 수 있습니다.")
                ForEach(colorEntries) { entry in
                    HStack(spacing: appTheme.space8) {
                        Text(entry.label)
                            .font(.callout)
                            .foregroundStyle(appTheme.primaryText)
                        Spacer()
                        Button("기본") {
                            theme[keyPath: entry.keyPath] = nil
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(appTheme.secondaryText)
                        .disabled(theme[keyPath: entry.keyPath] == nil)
                        ColorPicker("", selection: hexBinding(entry.keyPath))
                            .labelsHidden()
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private struct ColorEntry: Identifiable {
        let id = UUID()
        let label: String
        let keyPath: WritableKeyPath<CustomTheme, String?>
    }

    private var colorEntries: [ColorEntry] {
        [
            ColorEntry(label: "본문 텍스트", keyPath: \.primaryTextHex),
            ColorEntry(label: "보조 텍스트", keyPath: \.secondaryTextHex),
            ColorEntry(label: "창 배경", keyPath: \.primaryBackgroundHex),
            ColorEntry(label: "보조 배경", keyPath: \.secondaryBackgroundHex),
            ColorEntry(label: "카드 배경", keyPath: \.cardBackgroundHex),
            ColorEntry(label: "카드 테두리", keyPath: \.cardBorderHex),
            ColorEntry(label: "액센트", keyPath: \.accentColorHex),
            ColorEntry(label: "기본 테두리", keyPath: \.primaryBorderHex),
            ColorEntry(label: "성공", keyPath: \.successColorHex),
            ColorEntry(label: "경고", keyPath: \.warningColorHex),
            ColorEntry(label: "오류", keyPath: \.errorColorHex),
            ColorEntry(label: "입력 배경", keyPath: \.inputBackgroundHex),
            ColorEntry(label: "입력 테두리", keyPath: \.inputBorderHex)
        ]
    }

    /// stored hex → Color, set 시 hex 문자열 저장
    private func hexBinding(_ keyPath: WritableKeyPath<CustomTheme, String?>) -> Binding<Color> {
        Binding(
            get: {
                if let hex = theme[keyPath: keyPath] {
                    return Color(hex: hex)
                }
                return baseColor(for: keyPath)
            },
            set: { newColor in
                theme[keyPath: keyPath] = newColor.toHexString()
            }
        )
    }

    private func baseColor(for keyPath: WritableKeyPath<CustomTheme, String?>) -> Color {
        switch keyPath {
        case \.primaryTextHex: return baseTheme.primaryText
        case \.secondaryTextHex: return baseTheme.secondaryText
        case \.primaryBackgroundHex: return baseTheme.primaryBackground
        case \.secondaryBackgroundHex: return baseTheme.secondaryBackground
        case \.cardBackgroundHex: return baseTheme.cardBackground
        case \.cardBorderHex: return baseTheme.cardBorder
        case \.accentColorHex: return baseTheme.accentColor
        case \.primaryBorderHex: return baseTheme.primaryBorder
        case \.successColorHex: return baseTheme.successColor
        case \.warningColorHex: return baseTheme.warningColor
        case \.errorColorHex: return baseTheme.errorColor
        case \.inputBackgroundHex: return baseTheme.inputBackground
        case \.inputBorderHex: return baseTheme.inputBorder
        default: return baseTheme.primaryText
        }
    }

    // MARK: - 글라스 카드

    private var glassCard: some View {
        ThemedSettingsCard("글라스 (유리) 효과") {
            VStack(alignment: .leading, spacing: appTheme.space8) {
                Toggle("글라스 배경 사용", isOn: $theme.glassEnabled)
                    .toggleStyle(.switch)
                sliderRow("불투명도 (주)", value: $theme.glassOpacityPrimary, range: 0...0.6)
                sliderRow("불투명도 (보조)", value: $theme.glassOpacitySecondary, range: 0...0.6)
                sliderRow("블러 반경", value: $theme.glassBlurRadius, range: 0...60)
            }
        }
    }

    // MARK: - 말풍선 카드

    private var bubbleCard: some View {
        ThemedSettingsCard("말풍선") {
            VStack(alignment: .leading, spacing: appTheme.space8) {
                sliderRow("모서리 라운드", value: $theme.bubbleCornerRadius, range: 0...28)
                sliderRow("사용자 불투명도", value: $theme.userBubbleOpacity, range: 0.2...1.0)
                sliderRow("어시스턴트 불투명도", value: $theme.assistantBubbleOpacity, range: 0.2...1.0)
            }
        }
    }

    private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(appTheme.primaryText)
            Spacer()
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.caption.monospaced())
                .foregroundStyle(appTheme.secondaryText)
                .frame(width: 44, alignment: .trailing)
            Slider(value: value, in: range)
                .frame(width: 160)
        }
    }

    // MARK: - 라이브 미리보기

    private var previewCard: some View {
        let previewTheme = CustomizableTheme(config: theme)
        return ThemedSettingsCard("미리보기") {
            VStack(alignment: .leading, spacing: appTheme.space10) {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("사용자 메시지")
                        .font(.caption)
                        .foregroundStyle(previewTheme.secondaryText)
                    Text("이 글라스/색상이 적용되는 예시입니다.")
                        .font(.system(size: 13))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(previewTheme.userBubbleColor ?? previewTheme.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: previewTheme.bubbleCornerRadius, style: .continuous))
                        .foregroundStyle(previewTheme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("어시스턴트")
                        .font(.caption)
                        .foregroundStyle(previewTheme.secondaryText)
                    Text("테마에 따라 말풍선 라운드와 배경 투명도가 달라집니다.")
                        .font(.system(size: 13))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(previewTheme.cardBackground.opacity(previewTheme.assistantBubbleOpacity), in: RoundedRectangle(cornerRadius: previewTheme.bubbleCornerRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: previewTheme.bubbleCornerRadius, style: .continuous).stroke(previewTheme.cardBorder.opacity(previewTheme.borderOpacity), lineWidth: previewTheme.defaultBorderWidth))
                        .foregroundStyle(previewTheme.primaryText)
                }

                HStack(spacing: 10) {
                    Button { } label: { Label("전송", systemImage: "arrow.up.circle.fill") }
                        .buttonStyle(.borderedProminent)
                        .tint(previewTheme.accentColor)
                    TextField("", text: .constant("입력 예시"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                    Text("스킬")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(previewTheme.accentColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(previewTheme.accentColor)
                }
            }
        }
    }

    // MARK: - 저장

    private func save() {
        var saved = theme
        let trimmed = saved.name.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.name = trimmed.isEmpty ? "테마" : trimmed
        themeManager.installCustomTheme(saved)
        if isNew {
            themeManager.activateCustomTheme(saved)
        } else if theme.id == themeManager.activeCustomTheme?.id {
            themeManager.activateCustomTheme(saved)
        }
        DebugLogger.shared.info("THEME", "[FEATURE] 테마 \(isNew ? "생성" : "편집") 저장: \(saved.name) (\(saved.isDark ? "다크" : "라이트"))")
        dismiss()
    }
}

// MARK: - 설치된 테마 관리 목록 (GeneralSettingsView에서 사용)

/// 설정 → 외관 → 테마 관리: 설치된 테마 목록 + 적용/편집/복제/삭제 + 새 테마
struct InstalledThemesList: View {
    @Environment(\.theme) private var theme
    private let themeManager = ThemeManager.shared

    @State private var editingTheme: CustomTheme?
    @State private var showBuilder = false

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space10) {
            if themeManager.installedThemes.isEmpty {
                ThemedSettingsCaption("저장된 테마가 없습니다. '새 테마 만들기'로 직접 만들어 보세요.")
            } else {
                ForEach(themeManager.installedThemes) { installedTheme in
                    row(for: installedTheme)
                }
            }

            Button {
                showBuilder = true
            } label: {
                Label("새 테마 만들기", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showBuilder) {
            ThemeBuilderSheet()
        }
        .sheet(item: $editingTheme) { installedTheme in
            ThemeBuilderSheet(theme: installedTheme)
        }
    }

    private func row(for installedTheme: CustomTheme) -> some View {
        HStack(spacing: theme.space8) {
            Image(systemName: installedTheme.isDark ? "moon.fill" : "sun.max.fill")
                .font(.caption)
                .foregroundStyle(installedTheme.isDark ? Color.indigo : Color.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(installedTheme.name)
                    .font(.callout)
                    .foregroundStyle(theme.primaryText)
                Text(installedTheme.isDark ? "다크" : "라이트")
                    .font(.caption2)
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer()
            if isActive(installedTheme) {
                Text("적용 중")
                    .font(.caption2)
                    .foregroundStyle(theme.accentColor)
            } else {
                Button("적용") {
                    themeManager.activateCustomTheme(installedTheme)
                    DebugLogger.shared.info("THEME", "[FEATURE] 테마 적용: \(installedTheme.name)")
                }
                .controlSize(.small)
            }
            Button {
                editingTheme = installedTheme
            } label: {
                Image(systemName: "pencil")
            }
            .controlSize(.small)
            .help("편집")
            Menu {
                Button {
                    var copy = installedTheme
                    copy.id = UUID().uuidString
                    copy.name += " (복사)"
                    themeManager.installCustomTheme(copy)
                    DebugLogger.shared.info("THEME", "[FEATURE] 테마 복제: \(copy.name)")
                } label: {
                    Label("복제", systemImage: "plus.square.on.square")
                }
                Button(role: .destructive) {
                    themeManager.removeCustomTheme(id: installedTheme.id)
                    DebugLogger.shared.info("THEME", "[FEATURE] 테마 삭제: \(installedTheme.name)")
                } label: {
                    Label("삭제", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("더 보기")
        }
    }

    private func isActive(_ installedTheme: CustomTheme) -> Bool {
        themeManager.activeCustomTheme?.id == installedTheme.id
    }
}

#Preview {
    ThemeBuilderSheet()
        .environment(\.theme, ThemeBox(LightTheme()))
}