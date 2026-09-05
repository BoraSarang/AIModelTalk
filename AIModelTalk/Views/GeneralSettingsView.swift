import SwiftUI
import AppKit

struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var updateService = UpdateCheckService.shared
    @State private var axGranted = SelectedTextCapture.isAccessibilityGranted
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.space12) {
                settingsCard("외관") { appearanceSection }
                settingsCard("접근성 권한") { accessibilitySection }
                settingsCard("업데이트") { updateSection }
                settingsCard("비교 모드") { comparisonSection }
                settingsCard("보조 모델 — 기억 추출·제목 생성 (v2.3)") { auxiliarySection }
                settingsCard("웹 검색 (Tavily)") { webSearchSection }
                settingsCard("에이전트 (내장 도구)") { agentSection }
                settingsCard("워크스페이스 폴더 (로컬 파일 도구)") { workspaceSection }
                settingsCard("기본 시스템 프롬프트") { systemPromptSection }
                settingsCard("호출 동작") { presentationSection }
            }
            .padding(theme.space16)
        }
        .onAppear {
            axGranted = SelectedTextCapture.isAccessibilityGranted
            if updateService.lastCheckedAt == nil {
                Task { await updateService.checkForUpdates() }
            }
        }
    }

    private func settingsCard(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        ThemedSettingsCard(title) {
            content()
        }
    }

    // MARK: - 외관

    @ViewBuilder
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: theme.space10) {
            Text("모드")
                .font(.callout)
                .foregroundStyle(theme.primaryText)
            HStack(spacing: theme.space8) {
                modeRadioButton("시스템 설정", value: "system", icon: "circle.lefthalf.filled")
                modeRadioButton("다크 모드", value: "dark", icon: "moon.fill")
                modeRadioButton("라이트 모드", value: "light", icon: "sun.max.fill")
            }

            Divider()

            Text("액센트")
                .font(.callout)
                .foregroundStyle(theme.primaryText)
            HStack(spacing: theme.space8) {
                ForEach(AccentTheme.allCases) { accent in
                    accentRadioButton(accent)
                }
            }

            Divider()
                Text("테마 관리")
                    .font(.callout)
                    .foregroundStyle(theme.primaryText)
                InstalledThemesList()

            accentPreviewCard

            HStack {
                Button("온보딩 다시 보기") {
                    UserDefaults.standard.set(false, forKey: "onboardingCompleted")
                    NotificationCenter.default.post(name: HotKeyManager.showOnboardingAgain, object: nil)
                    DebugLogger.shared.info("APP", "[FEATURE] 온보딩 재실행 요청됨")
                }
                Spacer()
            }
        }
    }

    // MARK: - 가로 라디오 선택 (외형/액센트)

    private func modeRadioButton(_ title: String, value: String, icon: String) -> some View {
        let isSelected = settings.appearance == value
        return Button {
            settings.appearance = value
            DebugLogger.shared.info("THEME", "[FEATURE] 외형 모드 변경 → 테마 동기화: \(value)")
        } label: {
            HStack(spacing: 6) {
                radioIndicator(isSelected: isSelected)
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(isSelected ? theme.accentColor : theme.secondaryText)
                Text(title)
                    .font(.callout)
                    .foregroundStyle(isSelected ? theme.primaryText : theme.secondaryText)
            }
            .radioChipBackground(isSelected: isSelected, theme: theme)
        }
        .buttonStyle(.plain)
        .help("\(title) 모드로 전환")
    }

    private func accentRadioButton(_ accent: AccentTheme) -> some View {
        let isSelected = settings.accentColor == accent.rawValue
        return Button {
            settings.accentColor = accent.rawValue
        } label: {
            HStack(spacing: 6) {
                radioIndicator(isSelected: isSelected)
                if let color = accent.color {
                    Circle().fill(color).frame(width: 12, height: 12)
                } else {
                    Image(systemName: "circle.lefthalf.filled").font(.caption2)
                }
                Text(accent.displayName)
                    .font(.callout)
                    .foregroundStyle(isSelected ? theme.primaryText : theme.secondaryText)
            }
            .radioChipBackground(isSelected: isSelected, theme: theme)
        }
        .buttonStyle(.plain)
        .help("액센트 \(accent.displayName)")
    }

    private func radioIndicator(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(isSelected ? theme.accentColor : theme.cardBorder, lineWidth: 1)
                .frame(width: 14, height: 14)
            if isSelected {
                Circle().fill(theme.accentColor).frame(width: 8, height: 8)
            }
        }
    }

    private var accessibilitySection: some View {
        VStack(alignment: .leading, spacing: theme.space8) {
            HStack {
                Image(systemName: axGranted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(axGranted ? .green : .orange)
                Text(axGranted ? "접근성 권한 허용됨" : "접근성 권한이 필요합니다 (선택 텍스트 가져오기)")
                    .font(.callout)
                    .foregroundStyle(theme.primaryText)
                Spacer()
                if !axGranted {
                    Button("시스템 설정 열기") {
                        SelectedTextCapture.openAccessibilitySettings()
                    }
                }
            }
            ThemedSettingsCaption("권한 허용 후 AIModelTalk를 다시 실행하면 자동 감지됩니다.")
        }
    }

    private var updateSection: some View {
        VStack(alignment: .leading, spacing: theme.space8) {
            HStack {
                Text("현재 버전")
                    .font(.callout)
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Text(updateService.currentVersion)
                    .font(.callout.monospaced())
                    .foregroundStyle(theme.secondaryText)
            }
            HStack {
                if updateService.isChecking {
                    ProgressView().controlSize(.small)
                    Text("확인 중…").font(.caption)
                } else if updateService.hasUpdate, let release = updateService.latestRelease {
                    Text("새 버전 \(release.version) 사용 가능")
                        .font(.callout)
                        .foregroundStyle(theme.accentColor)
                    Spacer()
                    Button("다운로드") { updateService.openReleasePage() }
                } else if let error = updateService.errorMessage {
                    Text(error).font(.caption).foregroundStyle(theme.errorColor)
                    Spacer()
                    Button("다시 시도") { Task { await updateService.checkForUpdates() } }
                } else {
                    Text("최신 버전입니다").font(.callout).foregroundStyle(theme.successColor)
                    Spacer()
                }
                Button("지금 확인") {
                    Task { await updateService.checkForUpdates() }
                }
                .disabled(updateService.isChecking)
            }
            ThemedSettingsCaption("업데이트는 GitHub Releases에서 수동으로 내려받습니다.")
        }
    }

    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: theme.space8) {
            Toggle("판정 채점·리포트 사용", isOn: $settings.showJudgeSummary)
                .toggleStyle(.switch)
            ThemedSettingsCaption("비교 모드에서만 적용됩니다. 일반 대화에는 영향이 없습니다. OFF면 실측 속도 메트릭만 표시됩니다.")
        }
    }

    private var auxiliarySection: some View {
        VStack(alignment: .leading, spacing: theme.space8) {
            ThemedSettingsRow("보조 모델") {
                Picker("", selection: $settings.auxiliaryModelSpec) {
                    Text("자동 (권장)").tag("")
                    ForEach(auxiliaryChoices, id: \.spec) { choice in
                        Text(choice.label).tag(choice.spec)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            ThemedSettingsCaption("백그라운드 작업(자동 기억 추출, 세션 제목 생성)에 경량 모델을 써서 대화 모델 토큰을 절약합니다. 자동이면 flash·mini 계열을 우선 선택하고, 없으면 대화 모델을 사용합니다.")
        }
    }

    @ViewBuilder
    private var webSearchSection: some View {
        VStack(alignment: .leading, spacing: theme.space8) {
            Toggle("웹 검색 버튼 표시", isOn: $settings.webSearchEnabled)
                .toggleStyle(.switch)
            if settings.webSearchEnabled {
                SecureField("Tavily API 키", text: $settings.tavilyAPIKey, prompt: Text("tvly-..."))
                    .textFieldStyle(.roundedBorder)
                HStack {
                    ThemedSettingsCaption("무료 1,000회/월. 키는 이 Mac에만 저장됩니다.")
                    Spacer()
                    if let url = WebSearchBackend.tavily.signupURL.flatMap(URL.init(string:)) {
                        Link("API 키 발급", destination: url)
                            .font(.caption)
                    }
                }
                ThemedSettingsCaption("입력창의 🌐 버튼으로 이번 전송에만 웹 검색 결과를 반영할 수 있습니다.")
            }
        }
    }

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: theme.space10) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("에이전트 모드", isOn: $settings.agentMode)
                    .toggleStyle(.switch)
                ThemedSettingsCaption("켜면 웹 검색·페이지 읽기·계산기 내장 도구를 자동 활성화해 에이전트처럼 동작합니다.")
            }
            VStack(alignment: .leading, spacing: 6) {
                Toggle("YOLO 모드", isOn: $settings.yoloMode)
                    .toggleStyle(.switch)
                ThemedSettingsCaption("켜면 모든 도구 실행을 사전 확인 없이 자동 승인합니다. 주의해서 사용하세요.")
            }
        }
    }

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: theme.space10) {
            HStack(alignment: .top, spacing: theme.space10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(settings.workspaceFolder == nil
                         ? "지정 안 됨 — 파일 도구(list_dir/read_file/write_file/edit_file) 비활성"
                         : "\(urlForWorkspace.lastPathComponent)")
                        .font(.callout)
                        .foregroundStyle(settings.workspaceFolder == nil ? theme.secondaryText : theme.primaryText)
                    if let path = settings.workspaceFolder {
                        Text(path)
                            .font(.caption.monospaced())
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        ThemedSettingsCaption("모델이 이 폴더 안에서만 파일을 읽고 쓸 수 있습니다.")
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Button(settings.workspaceFolder == nil ? "폴더 선택…" : "변경…") { pickWorkspaceFolder() }
                    if settings.workspaceFolder != nil {
                        Button("해제") { settings.workspaceFolder = nil }
                    }
                }
            }
        }
    }

    private var systemPromptSection: some View {
        VStack(alignment: .leading, spacing: theme.space8) {
            ThemedSettingsCaption("모든 새 대화와 모델 변경 시 모델에 전달되는 기본 지시입니다. 선택한 스킬은 이 프롬프트 뒤에 누적됩니다.")
            TextEditor(text: $settings.systemPrompt)
                .font(.system(size: 12))
                .frame(minHeight: 80, maxHeight: 160)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: theme.inputCornerRadius).fill(theme.inputBackground))
                .overlay(RoundedRectangle(cornerRadius: theme.inputCornerRadius).strokeBorder(theme.inputBorder))
        }
    }

    private var presentationSection: some View {
        VStack(alignment: .leading, spacing: theme.space8) {
            Text("글로벌 단축키 표시 방식")
                .font(.callout)
                .foregroundStyle(theme.primaryText)
            Picker("", selection: $settings.presentationMode) {
                Text("기존 대화창을 앞으로").tag("window")
                Text("커서 근처 팝오버").tag("popover")
            }
            .labelsHidden()
            .pickerStyle(.radioGroup)
        }
    }

    /// 액센트 라이브 미리보기 — 선택 즉시 색이 변하는 샘플 요소 (v2.1 T-105)
    /// 보조 모델 선택지 — 활성화된 카탈로그 모델 (provider: id 스펙)
    private var auxiliaryChoices: [(spec: String, label: String)] {
        ModelCatalog.shared.models
            .filter { ModelCatalog.shared.isEnabled($0) }
            .map { (spec: "\($0.provider.rawValue):\($0.id)", label: "\($0.provider.rawValue) · \($0.displayName)") }
    }

    private var accentPreviewCard: some View {
        VStack(alignment: .leading, spacing: theme.space10) {
            Text("미리보기 — 액센트가 적용되는 요소")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondaryText)

            HStack(spacing: 14) {
                Button {} label: {
                    Label("전송", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.borderedProminent)

                Button("취소") {}
                    .buttonStyle(.bordered)

                Toggle("웹 검색", isOn: .constant(true))
                    .toggleStyle(.switch)

                Text("스킬")
                    .font(.caption)
                    .padding(.horizontal, theme.space10)
                    .padding(.vertical, 4)
                    .background(theme.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(theme.accentColor)
            }
            .controlSize(.regular)

            VStack(alignment: .leading, spacing: 2) {
                Text("'시스템'은 macOS 설정의 강조 색상을 따릅니다.")
                Text("대화 말풍선 본문은 가독성을 위해 액센트와 무관하게 유지됩니다.")
            }
            .font(.caption2)
            .foregroundStyle(theme.tertiaryText)
        }
        .padding(theme.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.secondaryBackground, in: RoundedRectangle(cornerRadius: theme.inputCornerRadius))
        .onAppear {
            DebugLogger.shared.info("APP", "[FEATURE] 액센트 미리보기 카드 표시됨")
        }
    }

    /// 워크스페이스 폴더 URL (v0.3.0 축3) — 표시용 lastPathComponent 계산
    private var urlForWorkspace: URL {
        URL(fileURLWithPath: settings.workspaceFolder ?? "")
    }

    private func pickWorkspaceFolder() {
        let panel = NSOpenPanel()
        panel.title = "워크스페이스 폴더 선택"
        panel.prompt = "선택"
        panel.message = "모델이 읽고 쓸 수 있는 로컬 폴더를 선택하세요."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.workspaceFolder = url.path
            DebugLogger.shared.info("APP", "[FEATURE] 워크스페이스 폴더 지정: \(url.path)")
        }
    }
}

#Preview {
    GeneralSettingsView()
        .environment(\.theme, ThemeBox(LightTheme()))
}