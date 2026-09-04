import SwiftUI
import AppKit

// MARK: - 빠른 질문 패널 (커서 근처 스포트라이트 스타일)

/// 패널 전용 NSPanel — 엔터 가드용 타입 식별 + key 자격 명시 (T-44)
@MainActor
final class QuickPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class QuickPanelController {
    static let shared = QuickPanelController()
    private var panel: NSPanel?
    private var keyMonitor: Any?

    /// 패널이 현재 key window인지 — 엔터 모니터가 메인 창에서 발화하지 않도록 가드
    var isPanelKey: Bool {
        panel?.isKeyWindow ?? false
    }

    func show(prefill: String?) {
        let panel = makePanelIfNeeded()

        // 패널 열림 세션 수명은 컨트롤러가 소유 — 뷰 onAppear는 재오픈 시 재발화가 보장되지 않아
        // draft 미생성→전송 조용히 차단 버그 발생 (v2.1 T-104)
        ChatViewModel.shared.beginQuickChat()

        if let hosting = panel.contentView as? NSHostingView<AnyView> {
            // 열 때마다 최신 액센트로 재주입 (v2.1 T-100)
            hosting.rootView = AnyView(
                QuickChatView(prefill: prefill, onClose: { [weak self] in self?.hide() })
                    .appAccentTint(AppSettings.shared.accentColor)
            )
        }

        positionNearCursor(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// ⌥Space 런처 토글 — 보이면 숨기고, 없으면 커서 근처에 표시 (v2.0 T-81)
    func toggle() {
        if let panel, panel.isVisible {
            DebugLogger.shared.info("APP", "[FEATURE] 퀵 패널 숨김 실행됨 (⌥Space)")
            hide()
        } else {
            DebugLogger.shared.info("APP", "[FEATURE] 퀵 패널 표시 실행됨 (⌥Space)")
            show(prefill: nil)
        }
    }

    func hide() {
        panel?.orderOut(nil)
        // 닫으면 미저장 draft 폐기 (요구사항 — 저장은 명시적 버튼으로만)
        ChatViewModel.shared.endQuickChat()
    }

    // MARK: - 패널 생성
    private func makePanelIfNeeded() -> NSPanel {
        if let panel { return panel }

        // borderless 패널 (v2.1 T-108) — OS 크롬(타이틀바·safe area) 개입이 없어 macOS 버전과
        // 무관하게 동일 렌더링. 기존 titled+fullSizeContentView+숨김버튼 조합은 버전별 크롬 변화에
        // 매번 수동 대응이 필요했다 (T-107 하단 스트립 사례). 라운딩·재질은 SwiftUI가 직접 소유.
        let panel = QuickPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 540),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.hasShadow = true

        let root = AnyView(
            QuickChatView(prefill: nil, onClose: { [weak self] in self?.hide() })
                .appAccentTint(AppSettings.shared.accentColor)
        )
        panel.contentView = NSHostingView(rootView: root)

        // 엔터 전송 모니터 — 뷰 인스턴스와 무관하게 컨트롤러가 단일 소유 (루트뷰 교체 시 누수 방지)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 36,
                  !event.modifierFlags.contains(.shift),
                  !event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.control),
                  !event.modifierFlags.contains(.option),
                  self?.panel?.isKeyWindow == true else { return event }
            NotificationCenter.default.post(name: .quickPanelReturnPressed, object: nil)
            return nil
        }

        self.panel = panel
        return panel
    }

    private func positionNearCursor(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) else {
            panel.center()
            return
        }
        let visible = screen.visibleFrame
        var origin = CGPoint(x: mouse.x - panel.frame.width / 2, y: mouse.y - 60)
        origin.x = max(visible.minX + 8, min(origin.x, visible.maxX - panel.frame.width - 8))
        origin.y = max(visible.minY + 8, min(origin.y, visible.maxY - panel.frame.height - 8))
        panel.setFrameOrigin(origin)
    }

}

extension Notification.Name {
    static let quickPanelReturnPressed = Notification.Name("AIModelTalk.quickPanelReturnPressed")
}

// MARK: - 패널 콘텐츠 뷰 (전체 스레드 표시 — T-43)

/// 스크롤 지오메트리 스냅샷 (패널 하단 추종용)
private struct QuickScrollSnapshot: Equatable {
    var offset: CGFloat      // contentOffset.y
    var content: CGFloat     // contentSize.height
    var container: CGFloat   // containerSize.height
}

struct QuickChatView: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var viewModel = ChatViewModel.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var input: String = ""
    @State private var pinnedToBottom = true
    @State private var panelScrollView: NSScrollView?
    /// 참조 누락 진단 로그 1회 출력용 (T-48)
    @State private var didWarnMissingScrollRef = false
    @FocusState private var inputFocused: Bool

    /// 하단 판정 임계값(pt)
    private let bottomThreshold: CGFloat = 60

    let prefill: String?
    let onClose: () -> Void

    private var quickSession: ChatSession? {
        guard let id = viewModel.quickSessionID else { return nil }
        return viewModel.sessions.first { $0.id == id }
    }

    private var canSendNow: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isLoading
    }

    /// 미저장 draft에 대화가 있을 때만 저장 가능
    private var canSave: Bool {
        viewModel.isQuickSessionDraft && !(quickSession?.messages.isEmpty ?? true)
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            Divider()
            threadArea
            Divider()
            inputBar
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(width: 500, height: 540)
        .background(.regularMaterial)
        // borderless 창의 모서리·그림자는 콘텐츠 알파에서 따라옴 (v2.1 T-108)
        .clipShape(RoundedRectangle(cornerRadius: theme.radiusPanel, style: .continuous))
        .appAccentTint(settings.accentColor)
        // 전 방향 safe area 해제 — macOS 26 창 하단 안전 영역 여백이 입력창 아래
        // 반투명 빈 스트립으로 남던 문제 수정 (v2.1 T-107). 패널은 부유창이라 하단 해제가 안전
        .ignoresSafeArea()
        .onAppear {
            // 패널 세션은 QuickPanelController.show()에서 시작됨 → prefill → 포커스
            pinnedToBottom = true
            if let p = prefill, !p.isEmpty {
                input = p
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                inputFocused = true
            }
        }
        .onExitCommand {
            onClose()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickPanelReturnPressed)) { _ in
            send()
        }
        .onChange(of: quickSession?.messages.count) { _ in
            jumpToBottom()
        }
        .onReceive(NotificationCenter.default.publisher(for: .scrollToBottom)) { _ in
            // 스트리밍 청크 알림 — 위로 읽는 중이면 무시
            guard pinnedToBottom else { return }
            jumpToBottom()
        }
        .onChange(of: viewModel.isLoading) { loading in
            // 응답 완료 직후 말풍선 최종 높이 반영 보정
            if !loading && pinnedToBottom {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    jumpToBottom()
                }
            }
        }
    }

    // MARK: 헤더 — 모델 선택(전역 공유·자동 저장) · 새 대화로 저장 · 닫기

    private var header: some View {
        HStack(spacing: 10) {
            // 모델 피커가 좌측 선두 — 패널 타이틀 텍스트는 제거(브랜딩은 메뉴바 담당, v2.1 T-103)
            ModelPickerPopover(viewModel: viewModel)

            Spacer()

            Button {
                saveAndOpenInMain()
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 13))
                    .foregroundStyle(canSave ? theme.accentColor : theme.secondaryText.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .help("저장 후 패널을 닫고 메인 창에서 이 대화 열기")

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(theme.secondaryText)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 전체 스레드 (MessageBubbleView 재사용 — 메인과 동일 렌더링)

    @ViewBuilder
    private var threadArea: some View {
        // Finder는 반드시 스크롤 콘텐츠 내부에 있어야 상위 계층에서 NSScrollView를 찾는다 (v2.1 T-104)
        // 바깥 .background에 두면 미탐색으로 패널 자동 스크롤이 동작하지 않았음
        let base = ScrollView {
            Group {
                ScrollViewFinder { found in
                    panelScrollView = found
                }
                .frame(width: 0, height: 0)
                if let session = quickSession, session.messages.isEmpty {
                    VStack(spacing: 14) {
                        // 액센트 그라디언트 타일 (v2.1 T-103)
                        ZStack {
                            RoundedRectangle(cornerRadius: theme.radiusPanel)
                                .fill(LinearGradient(
                                    colors: [theme.accentColor, theme.accentColor.opacity(0.65)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                            Image(systemName: "bolt.horizontal.circle.fill")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 54, height: 54)
                        .shadow(color: theme.accentColor.opacity(0.25), radius: 8, x: 0, y: 4)

                        Text("빠르게 질문하고 답을 받으세요")
                            .font(.subheadline.weight(.medium))

                        // 예시 질문 칩 — 클릭 시 입력창에 채움
                        HStack(spacing: 8) {
                            exampleChip("아이디어 5개만")
                            exampleChip("요약해줘")
                            exampleChip("영어로 번역")
                        }

                        Text("저장하지 않고 닫으면 대화가 사라집니다")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 44)
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 12) {
                        ForEach(quickSession?.messages ?? []) { message in
                            MessageBubbleView(
                                message: message,
                                isStreaming: viewModel.streamingMessageID == message.id,
                                sidePadding: 10
                            )
                        }
                        Spacer().frame(height: 1).id("quickBottom")
                    }
                    .padding(.vertical, 4)
                }
            }
        }

        if #available(macOS 15.0, *) {
            base.onScrollGeometryChange(for: QuickScrollSnapshot.self) { geo in
                QuickScrollSnapshot(
                    offset: geo.contentOffset.y,
                    content: geo.contentSize.height,
                    container: geo.containerSize.height
                )
            } action: { old, new in
                handleScrollChange(old: old, new: new)
            }
        } else {
            base
        }
    }

    /// 빈 상태 예시 질문 칩 (v2.1 T-103)
    private func exampleChip(_ title: String) -> some View {
        Button {
            input = title
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                inputFocused = true
            }
        } label: {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(theme.primaryText.opacity(0.05), in: Capsule())
                .overlay(Capsule().strokeBorder(theme.primaryText.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help("클릭하면 입력창에 채워집니다")
    }

    // MARK: 입력바

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // 입력 카드 — 포커스 시 액센트 링 (v2.1 T-103)
            TextField("무엇이든 물어보세요", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .fixedSize(horizontal: false, vertical: true)
                .focused($inputFocused)
                .onSubmit(send)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(theme.primaryText.opacity(0.06), in: RoundedRectangle(cornerRadius: theme.radiusBubble))
                .overlay(
                    RoundedRectangle(cornerRadius: theme.radiusBubble)
                        .strokeBorder(theme.accentColor.opacity(inputFocused ? 0.5 : 0), lineWidth: 1.5)
                )

            if viewModel.isLoading {
                Button {
                    viewModel.stopStreaming()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("응답 중지")
            } else {
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(canSendNow ? theme.accentColor : theme.secondaryText.opacity(0.4))
                }
                .buttonStyle(.plain)
                .disabled(!canSendNow)
            }
        }
    }

    private func send() {
        guard canSendNow else { return }
        DebugLogger.shared.info("SEND", "패널 전송: \(input.prefix(30))...")
        viewModel.sendQuick(input)
        input = ""
        // 전송 후에도 포커스 유지해 연속 질문 가능
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            inputFocused = true
        }
    }

    /// 저장 → 패널 닫기 → 메인 창에서 해당 대화 열기 (T-49)
    private func saveAndOpenInMain() {
        guard canSave, let savedID = quickSession?.id else { return }
        viewModel.saveQuickSessionAsNew()
        onClose() // 패널 닫기 — 저장된 세션은 endQuickChat에서 유지됨
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            // 창 제목은 T-100에서 "AI Model Talk"로 변경 — 매처도 동기화 (v2.1 T-104)
            let mainWindow = NSApp.windows.first { !$0.isKind(of: NSPanel.self) && $0.title == "AI Model Talk" }
            mainWindow?.makeKeyAndOrderFront(nil)
            viewModel.currentSessionID = savedID
        }
    }

    // MARK: 하단 추종 — 수명이 짧은 패널 특성상 기본 하단 고정, 위로 드래그 시에만 해제

    private func handleScrollChange(old: QuickScrollSnapshot, new: QuickScrollSnapshot) {
        guard new != old else { return }

        let maxOffset = new.content - new.container
        let atBottomNow = new.offset >= maxOffset - bottomThreshold
        let contentStable = abs(new.content - old.content) < 0.5
        let scrolledUp = new.offset < old.offset - 1
        let contentGrew = new.content > old.content + 0.5

        if scrolledUp && contentStable && !atBottomNow {
            pinnedToBottom = false
        }
        if atBottomNow {
            pinnedToBottom = true
        }
        if pinnedToBottom && contentGrew {
            // action은 뷰 갱신 트랜잭션 안에서 호출되므로 다음 런루프로 지연
            DispatchQueue.main.async {
                jumpToBottom()
            }
        }
    }

    /// 문서 끝까지 절대 좌표 이동 (T-39 패턴 — 앵커·프록시 오차 없음)
    private func jumpToBottom() {
        guard let scrollView = panelScrollView else {
            if !didWarnMissingScrollRef {
                didWarnMissingScrollRef = true
                DebugLogger.shared.info("SCROLL", "패널 NSScrollView 미탐색 — 하단 이동 생략")
            }
            return
        }
        guard let doc = scrollView.documentView else { return }
        let clipHeight = scrollView.contentView.bounds.height
        let docHeight = doc.bounds.height
        scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: max(0, docHeight - clipHeight)))
    }
}
