import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject private var viewModel = ChatViewModel.shared
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.openWindow) private var openWindow
    @State private var showPermissionAlert = false
    @State private var showRenameSheet = false
    @State private var renameText = ""
    @State private var renamingSession: ChatSession?
    /// 전역 검색 (v1.9 T-77)
    @State private var showGlobalSearch = false
    /// 첫 실행 온보딩 (v2.0 T-83)
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "onboardingCompleted")

    var body: some View {
        NavigationSplitView {
            SidebarView(
                viewModel: viewModel,
                showGlobalSearch: $showGlobalSearch,
                showRenameSheet: $showRenameSheet,
                renamingSession: $renamingSession,
                renameText: $renameText
            )
        } detail: {
            ChatView(viewModel: viewModel)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            showGlobalSearch = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .help("메시지 검색 (⌘F)")
                        Button {
                            viewModel.createNewSession()
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .help("새 대화 (⌘N)")
                    }
                }
        }
        .preferredColorScheme(settings.colorScheme)
        .onReceive(NotificationCenter.default.publisher(for: .newSession)) { _ in
            viewModel.createNewSession()
        }
        .onReceive(NotificationCenter.default.publisher(for: HotKeyManager.hotKeyPressed)) { note in
            // id:3(⌥Space 런처)은 HotKeyManager에서 직접 토글 처리 — 캡처 흐름 제외 (v2.0 T-81)
            if let id = note.userInfo?["id"] as? Int, id == 3 { return }
            handleGlobalHotKey()
        }
        .alert("접근성 권한 필요", isPresented: $showPermissionAlert) {
            Button("시스템 설정 열기") {
                SelectedTextCapture.openAccessibilitySettings()
            }
            Button("나중에", role: .cancel) {}
        } message: {
            Text("다른 앱에서 선택한 텍스트를 가져오려면 접근성 권한이 필요합니다.\n시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 AIModelTalk를 허용해 주세요.")
        }
        .sheet(isPresented: $showRenameSheet) {
            VStack(spacing: 16) {
                Text("대화 이름 수정")
                    .font(.headline)
                TextField("이름", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                HStack {
                    Button("취소") { showRenameSheet = false }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("저장") {
                        if let session = renamingSession {
                            viewModel.renameSession(session.id, to: renameText)
                        }
                        showRenameSheet = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 320)
        }
        .sheet(isPresented: $showGlobalSearch) {
            GlobalSearchView()
        }
        .onReceive(NotificationCenter.default.publisher(for: HotKeyManager.showOnboardingAgain)) { _ in
            showOnboarding = true
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
                .interactiveDismissDisabled(true)
        }
        .onAppear {
            // Dock 재클릭 시 메인 창 복원용 액션 주입 (v1.7.2 T-63)
            AppDelegate.openMainAction = {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    // MARK: - 글로벌 핫키 처리 (캡처 먼저 → 표시 모드별 동작)
    private func handleGlobalHotKey() {
        Task {
            let captured = await SelectedTextCapture.captureSelectedText()
            await MainActor.run {
                if !SelectedTextCapture.isAccessibilityGranted {
                    showPermissionAlert = true
                }

                switch AppSettings.shared.presentationMode {
                case "popover":
                    QuickPanelController.shared.show(prefill: captured)
                default:
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                    if let text = captured, !text.isEmpty {
                        viewModel.prefillInput(text)
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
