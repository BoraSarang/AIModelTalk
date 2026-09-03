import SwiftUI
import AppKit

@main
struct AIModelTalkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// 액센트 테마 — 모든 Scene 루트에 공통 적용 (v2.1 T-100)
    @ObservedObject private var settings = AppSettings.shared

    init() {
        // 커스텀 엔드포인트 .standard → 고정 스위트 1회 이전 (v3.8.1 T-1008)
        CustomEndpointStore.migrateToSuiteIfNeeded()
        
        // 레거시 단일 커스텀 설정 → 엔드포인트 목록 1회 이전 (v1.9 T-84)
        var endpointStore = CustomEndpointStore(defaults: .standard)
        endpointStore.migrateLegacyIfNeeded()
    }

    var body: some Scene {
        // Window 씬은 단일 인스턴스를 보장 — openWindow 재호출 시 기존 창을 앞으로 가져옴 (T-40)
        Window("AI Model Talk", id: "main") {
            ContentView()
                .frame(minWidth: 630, minHeight: 420)
                .appAccentTint(settings.accentColor)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            ModelTalkCommands()
            CommandGroup(replacing: .importExport) {
                Button("세션 가져오기…") {
                    importSession()
                }
            }
        }

        Window("벤치마크 랭킹", id: "benchmark") {
            BenchmarkView()
                .appAccentTint(settings.accentColor)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 640, height: 460)

        Window("브레인스토밍", id: "brainstorm") {
            BrainstormView()
                .appAccentTint(settings.accentColor)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 760, height: 620)

        Window("비교 모드", id: "comparison") {
            ComparisonView()
                .appAccentTint(settings.accentColor)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 900, height: 620)

        Window("스플릿 채팅", id: "splitChat") {
            SplitChatView()
                .appAccentTint(settings.accentColor)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1020, height: 660)

        MenuBarExtra {
            MenuBarExtraContent()
        } label: {
            Image(systemName: "bubble.left.and.text.bubble.right")
        }
        .menuBarExtraStyle(.menu)

        Window("디버그 패널", id: "debug") {
            DebugPanelView()
                .appAccentTint(settings.accentColor)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 800, height: 500)

        Settings {
            SettingsView()
                .appAccentTint(settings.accentColor)
        }
    }
}

// MARK: - AppDelegate (핫키 등록)

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// ContentView가 주입하는 메인 창 열기 액션 — Dock reopen 시 사용 (v1.7.2 T-63)
    static var openMainAction: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        HotKeyManager.shared.rebind()
        DebugLogger.shared.info("APP", "AIModelTalk v1.0.0 시작됨")
        // Dock 아이콘 표시 정책 — 저장값 기준 즉시 적용 (기본: 숨김, v3.5 T-163)
        AppSettings.shared.applyDockPolicy()
        Task { await UpdateCheckService.shared.checkForUpdates() }
        // 시작 시 모델 목록 백그라운드 갱신 — 키 설정된 공급자만 조회 (v1.7 T-52)
        Task { await ModelCatalog.shared.refresh() }
    }

    /// Dock 아이콘 클릭(reopen) 시 메인 대화창이 닫혀 있으면 복원 (v1.7.2 T-63)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 다른 창(디버그 패널 등)만 열려 있어도 메인을 우선 복원
        let mainVisible = sender.windows.contains { $0.isVisible && $0.title == "AI Model Talk" }
        if !mainVisible {
            DebugLogger.shared.info("APP", "Dock 클릭 — 메인 대화창 복원")
            Self.openMainAction?()
        }
        return true
    }
}

// MARK: - 메뉴바 팝오버 콘텐츠

struct MenuBarExtraContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("대화창 열기") {
            openMain()
        }
        .keyboardShortcut("1")
        Button("새 대화") {
            openMain()
            NotificationCenter.default.post(name: .newSession, object: nil)
        }
        Button("비교 모드") { openWindow(id: "comparison") }
        Button("스플릿 채팅") { openWindow(id: "splitChat") }
        Button("벤치마크 랭킹") { openWindow(id: "benchmark") }
        Divider()
        SettingsLink {
            Text("설정…")
        }
        Divider()
        Button("AI Model Talk 종료") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func openMain() {
        // Window 씬이 단일 인스턴스를 보장하므로 타이틀 매칭 불필요 (T-40)
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - 메뉴 커맨드

struct ModelTalkCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("새 대화") {
                NotificationCenter.default.post(name: .newSession, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Divider()

            Button("비교 모드") {
                openWindow(id: "comparison")
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Button("스플릿 채팅") {
                openWindow(id: "splitChat")
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("벤치마크 랭킹") {
                openWindow(id: "benchmark")
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])

            Divider()

            Button("디버그 패널") {
                openWindow(id: "debug")
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }
    }
}

extension Notification.Name {
    static let newSession = Notification.Name("AIModelTalk.newSession")
}

// MARK: - 세션 가져오기

private func importSession() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.begin { response in
        guard response == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let session = try SessionExportService.importJSON(data)
            ChatViewModel.shared.importSession(session)
            DebugLogger.shared.info("SESSION", "세션 가져오기: \(session.title)")
        } catch {
            DebugLogger.shared.error("E-MAC-STR-1003", "세션 가져오기 실패: \(error.localizedDescription)")
        }
    }
}