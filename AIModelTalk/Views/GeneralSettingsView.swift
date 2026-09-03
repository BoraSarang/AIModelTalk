import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var updateService = UpdateCheckService.shared
    @State private var axGranted = SelectedTextCapture.isAccessibilityGranted

    var body: some View {
        Form {
            Section("외관") {
                Picker("모드", selection: $settings.appearance) {
                    Text("시스템 설정").tag("system")
                    Text("다크 모드").tag("dark")
                    Text("라이트 모드").tag("light")
                }
                .pickerStyle(.radioGroup)

                Picker("액센트", selection: $settings.accentColor) {
                    ForEach(AccentTheme.allCases) { theme in
                        HStack(spacing: 6) {
                            if let color = theme.color {
                                Circle().fill(color).frame(width: 10, height: 10)
                            } else {
                                Image(systemName: "circle.lefthalf.filled").font(.caption2)
                            }
                            Text(theme.displayName)
                        }.tag(theme.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)

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

            Section("글로벌 단축키 — 선택 텍스트 캡처") {
                HStack {
                    Image(systemName: axGranted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(axGranted ? .green : .orange)
                    Text(axGranted ? "접근성 권한 허용됨" : "접근성 권한이 필요합니다 (선택 텍스트 가져오기)")
                        .font(.callout)
                    Spacer()
                    if !axGranted {
                        Button("시스템 설정 열기") {
                            SelectedTextCapture.openAccessibilitySettings()
                        }
                    }
                }
                Text("권한 허용 후 AIModelTalk를 다시 실행하면 자동 감지됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("업데이트") {
                HStack {
                    Text("현재 버전")
                        .font(.callout)
                    Spacer()
                    Text(updateService.currentVersion)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                }
                HStack {
                    if updateService.isChecking {
                        ProgressView().controlSize(.small)
                        Text("확인 중…").font(.caption)
                    } else if updateService.hasUpdate, let release = updateService.latestRelease {
                        Text("새 버전 \(release.version) 사용 가능")
                            .font(.callout)
                            .foregroundStyle(Color.accentColor)
                        Spacer()
                        Button("다운로드") { updateService.openReleasePage() }
                    } else if let error = updateService.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red)
                        Spacer()
                        Button("다시 시도") { Task { await updateService.checkForUpdates() } }
                    } else {
                        Text("최신 버전입니다").font(.callout).foregroundStyle(.green)
                        Spacer()
                    }
                    Button("지금 확인") {
                        Task { await updateService.checkForUpdates() }
                    }
                    .disabled(updateService.isChecking)
                }
                Text("업데이트는 GitHub Releases에서 수동으로 내려받습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("비교 모드") {
                Toggle("판정 채점·리포트 사용", isOn: $settings.showJudgeSummary)
                Text("비교 모드에서만 적용됩니다. 일반 대화에는 영향이 없습니다. OFF면 실측 속도 메트릭만 표시됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("보조 모델 — 기억 추출·제목 생성 (v2.3)") {
                Picker("보조 모델", selection: $settings.auxiliaryModelSpec) {
                    Text("자동 (권장)").tag("")
                    ForEach(auxiliaryChoices, id: \.spec) { choice in
                        Text(choice.label).tag(choice.spec)
                    }
                }
                .pickerStyle(.menu)
                Text("백그라운드 작업(자동 기억 추출, 세션 제목 생성)에 경량 모델을 써서 대화 모델 토큰을 절약합니다. 자동이면 flash·mini 계열을 우선 선택하고, 없으면 대화 모델을 사용합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("웹 검색 (Tavily)") {
                Toggle("웹 검색 버튼 표시", isOn: $settings.webSearchEnabled)
                if settings.webSearchEnabled {
                    SecureField("Tavily API 키", text: $settings.tavilyAPIKey, prompt: Text("tvly-..."))
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Text("무료 1,000회/월. 키는 이 Mac에만 저장됩니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let url = WebSearchBackend.tavily.signupURL.flatMap(URL.init(string:)) {
                            Link("API 키 발급", destination: url)
                                .font(.caption)
                        }
                    }
                    Text("입력창의 🌐 버튼으로 이번 전송에만 웹 검색 결과를 반영할 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("에이전트 (내장 도구)") {
                Toggle("에이전트 모드", isOn: $settings.agentMode)
                Text("켜면 웹 검색·페이지 읽기·계산기 내장 도구를 자동 활성화해 에이전트처럼 동작합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("YOLO 모드", isOn: $settings.yoloMode)
                Text("켜면 모든 도구 실행을 사전 확인 없이 자동 승인합니다. 주의해서 사용하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("기본 시스템 프롬프트") {
                Text("모든 새 대화와 모델 변경 시 모델에 전달되는 기본 지시입니다. 선택한 스킬은 이 프롬프트 뒤에 누적됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $settings.systemPrompt)
                    .font(.system(size: 12))
                    .frame(minHeight: 80, maxHeight: 160)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
            }

            Section("호출 동작") {
                Picker("글로벌 단축키 표시 방식", selection: $settings.presentationMode) {
                    Text("기존 대화창을 앞으로").tag("window")
                    Text("커서 근처 팝오버").tag("popover")
                }
                .pickerStyle(.radioGroup)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            axGranted = SelectedTextCapture.isAccessibilityGranted
            if updateService.lastCheckedAt == nil {
                Task { await updateService.checkForUpdates() }
            }
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
        VStack(alignment: .leading, spacing: 10) {
            Text("미리보기 — 액센트가 적용되는 요소")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }
            .controlSize(.regular)

            VStack(alignment: .leading, spacing: 2) {
                Text("'시스템'은 macOS 설정의 강조 색상을 따릅니다.")
                Text("대화 말풍선 본문은 가독성을 위해 액센트와 무관하게 유지됩니다.")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .onAppear {
            DebugLogger.shared.info("APP", "[FEATURE] 액센트 미리보기 카드 표시됨")
        }
    }
}

#Preview {
    GeneralSettingsView()
}