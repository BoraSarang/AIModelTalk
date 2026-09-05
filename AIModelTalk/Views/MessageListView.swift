import SwiftUI
import AppKit

// MARK: - 메시지 리스트 (스크롤 제어 전담)

/// 콘텐츠 하단의 뷰포트 기준 Y 위치를 보고하는 PreferenceKey (macOS 14 폴백용)
private struct ScrollBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

/// 말풍선별 chatScroll 좌표계 minY 수집 — 검색 점프 대상 위치 계산용 (v2.1 T-97 고도화)
/// 말풍선 NSView 레지스트리 — 검색 점프의 문서 좌표 조회용 (v2.1 T-109b)
/// SwiftUI preference 좌표는 macOS 26에서 스크롤 의존 값이 되어 진동 루프를 만들었으므로
/// AppKit 뷰 계층에서 직접 변환한다. 뷰 해제 시 weak 참조 자동 정리.
@MainActor
final class MessageAnchorRegistry {
    static let shared = MessageAnchorRegistry()
    private let map = NSMapTable<NSUUID, NSView>(keyOptions: .strongMemory, valueOptions: .weakMemory)

    func register(_ view: NSView, for id: UUID) {
        map.setObject(view, forKey: id as NSUUID)
    }

    func view(for id: UUID) -> NSView? {
        map.object(forKey: id as NSUUID)
    }
}

/// 말풍선 앵커 — 자기 NSView를 레지스트리에 등록하는 0크기 뷰 (v2.1 T-109b)
private struct MessageAnchor: NSViewRepresentable {
    let id: UUID

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        MessageAnchorRegistry.shared.register(view, for: id)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        MessageAnchorRegistry.shared.register(nsView, for: id)
    }
}

/// 스크롤 지오메트리 스냅샷 — 하단 판정·핀 로직용
private struct ScrollSnapshot: Equatable {
    var offset: CGFloat      // contentOffset.y
    var content: CGFloat     // contentSize.height
    var container: CGFloat   // containerSize.height
}

/// 상위 NSScrollView 탐색 — ScrollViewProxy의 레이아웃 스냅샷 오차 없이 절대 좌표로 스크롤하기 위한 AppKit 진입점
/// (메인 리스트·빠른 대화 패널 공용)
struct ScrollViewFinder: NSViewRepresentable {
    let onFound: (NSScrollView) -> Void

    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        DispatchQueue.main.async { [weak host] in
            guard let host else { return }
            // 계층 부착이 늦는 경우(오프스크린 패널 생성 등)가 있어 재시도 — 발견 시 즉시 중단
            var attempt = 0
            func walk() {
                var current: NSView? = host
                while let candidate = current {
                    if let scrollView = candidate as? NSScrollView {
                        onFound(scrollView)
                        return
                    }
                    current = candidate.superview
                }
                attempt += 1
                if attempt < 40 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: walk)
                }
            }
            walk()
        }
        return host
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct MessageListView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.theme) private var theme

    @State private var lastMessageCount = 0
    @State private var pendingScrollWorks: [DispatchWorkItem] = []
    @State private var isAtBottom = true
    /// 핀 ON이면 콘텐츠가 자랄 때마다 즉시 하단을 따라간다 (WKWebView 비동기 높이 추적)
    @State private var pinnedToBottom = true
    @State private var viewportHeight: CGFloat = 0
    /// 실제 백킹 NSScrollView — 절대 좌표 스크롤·진단 대조용
    @State private var chatScrollViewRef: NSScrollView?
    @State private var didLogGeometryDiagnostic = false
    /// 말풍선 문서 좌표 캐시 — 점프 대상 탐색에만 사용(수집 창 활성 시에만 갱신)
    /// 말풍선 문서 좌표 캐시 — (v2.1 T-109b에서 폐기: preference 좌표가 스크롤 의존이라 진동)
    /// 대신 MessageAnchorRegistry의 AppKit 뷰에서 직접 변환한다.
    @State private var pendingJumpMessageID: UUID?
    /// 되돌리기 확인 대기 메시지 — 파괴적 삭제라 alert 확인 필수 (T-339)
    @State private var pendingRewindMessageID: UUID?
    /// 마지막 점프 적용 offset — 동일 값 재적용 방지(수렴 판정)용 (v2.1 T-109)
    @State private var lastAppliedJumpOffset: CGFloat?

    /// 하단 판정 임계값(pt) — 서브픽셀 흔들림·고무줄 효과로 인한 깜빡임 방지
    private let bottomThreshold: CGFloat = 60

    var body: some View {
        messageList
            .overlay(alignment: .bottomTrailing) {
                if !isAtBottom {
                    Button {
                        DebugLogger.shared.info("SCROLL", "플로팅 버튼: 하단으로 이동")
                        setPin(true)
                        scrollToFitBottom()
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(theme.accentColor)
                            .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                    )
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .animation(.easeOut(duration: 0.18), value: isAtBottom)
            .alert("되돌리기", isPresented: Binding(
                get: { pendingRewindMessageID != nil },
                set: { if !$0 { pendingRewindMessageID = nil } }
            )) {
                Button("되돌리기", role: .destructive) {
                    if let id = pendingRewindMessageID, let sid = viewModel.currentSessionID {
                        viewModel.rewindSession(to: id, from: sid)
                    }
                    pendingRewindMessageID = nil
                }
                Button("취소", role: .cancel) { pendingRewindMessageID = nil }
            } message: {
                Text(rewindConfirmText)
            }
            .onChange(of: viewModel.currentSessionID) { _ in
                if let session = viewModel.currentSession {
                    viewModel.restoreSessionState(session)
                }
                lastMessageCount = viewModel.currentSession?.messages.count ?? 0
                if pendingJumpMessageID != nil {
                    // 검색 점프 예약 중 — 하단 추종 건너뛰고 점프가 위치를 잡는다 (v2.1 T-97 고도화)
                    setPin(false)
                    return
                }
                // 세션 전환: 새 대화는 하단부터 관람
                setPin(true)
                scrollToFitBottom()
            }
    }

    private var messageList: some View {
        GeometryReader { viewport in
            chatScrollView()
                .onAppear {
                    // 앱 첫 진입: init에서 세션이 이미 선택되어 onChange(currentSessionID)가 발화하지 않으므로 여기서 처리
                    viewportHeight = viewport.size.height
                    lastMessageCount = viewModel.currentSession?.messages.count ?? 0
                    scrollToFitBottom()
                }
                .onChange(of: viewport.size.height) { newHeight in
                    viewportHeight = newHeight
                }
                .onChange(of: viewModel.currentSession?.messages.count) { newCount in
                    guard let newCount = newCount, newCount > lastMessageCount else { return }
                    lastMessageCount = newCount
                    // 검색 점프 수집 창 중엔 하단 강제가 점프와 경합한다 — 스킵 (v2.1 T-109)
                    guard pendingJumpMessageID == nil else { return }
                    // 새 메시지(사용자 입력 포함)는 하단 관람 의사로 해석
                    setPin(true)
                    jumpToBottom()
                }
                .onReceive(NotificationCenter.default.publisher(for: .scrollToBottom)) { _ in
                    // ViewModel의 스트리밍 하단 추종 신호 — 위로 읽는 중이면 무시 (핀이 이미 처리)
                    guard isAtBottom else { return }
                    jumpToBottom()
                }
                .onChange(of: viewModel.isLoading) { loading in
                    // 응답 완료·정지·에러 공통: 마지막 위치로 이동 (읽던 위치 유지를 위해 하단일 때만)
                    if !loading && isAtBottom {
                        scrollToFitBottom()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: ChatViewModel.scrollToMessage)) { note in
                    guard let id = note.userInfo?["id"] as? UUID else { return }
                    beginMessageJump(to: id)
                }
        }
    }

    /// 스크롤 뷰 + 하단 감지.
    /// macOS는 AppKit NSScrollView 기반으로 스크롤 중 preference가 재평가되지 않으므로,
    /// macOS 15+에서는 전용 onScrollGeometryChange를, 14에서는 preference 폴백을 쓴다.
    /// 이동은 전부 실제 NSScrollView 절대 좌표로 수행한다(프록시 레이아웃 스냅샷 오차 배제).
    @ViewBuilder
    private func chatScrollView() -> some View {
        let base = ScrollView {
            // VStack: 전체 즉시 렌더링 (LazyVStack 지연 렌더링이 위치 오차 유발)
            VStack(spacing: 12) {
                if let session = viewModel.currentSession, session.messages.isEmpty {
                    emptyState
                }
                ForEach(viewModel.currentSession?.messages ?? []) { message in
                    let canRewindMessage = message.role == .user
                        && viewModel.streamingMessageID != message.id
                    MessageBubbleView(message: message, isStreaming: viewModel.streamingMessageID == message.id, onFork: {
                        if let sessionID = viewModel.currentSessionID {
                            viewModel.forkSession(at: message.id, from: sessionID)
                        }
                    }, onSendFollowUp: { text in
                        if let sessionID = viewModel.currentSessionID {
                            viewModel.sendFollowUp(text, in: sessionID)
                        }
                    }, onRewind: {
                        pendingRewindMessageID = message.id
                    }, canRewind: canRewindMessage)
                        .id(message.id)
                        // 검색 결과 이동 시 대상 메시지 플래시 하이라이트 (v2.1 T-97)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.yellow.opacity(viewModel.highlightedMessageID == message.id ? 0.30 : 0))
                                .animation(.easeInOut(duration: 0.4), value: viewModel.highlightedMessageID)
                        )
                        // 문서 좌표 앵커 — 점프 시 AppKit 계층에서 직접 조회 (v2.1 T-109b)
                        .background(MessageAnchor(id: message.id))
                        .contextMenu {
                            if viewModel.streamingMessageID != message.id, let sessionID = viewModel.currentSessionID {
                                Button {
                                    viewModel.forkSession(at: message.id, from: sessionID)
                                } label: {
                                    Label("이 지점부터 분기", systemImage: "arrow.triangle.branch")
                                }
                                Button {
                                    viewModel.forkSessionAndRerun(at: message.id, from: sessionID)
                                } label: {
                                    Label("이 지점에서 재실행 (현재 모델)", systemImage: "arrow.counterclockwise")
                                }
                                if message.role == .user {
                                    Divider()
                                    Button(role: .destructive) {
                                        pendingRewindMessageID = message.id
                                    } label: {
                                        Label("이 지점부터 되돌리기", systemImage: "arrow.uturn.backward")
                                    }
                                }
                            }
                        }
                }
                Spacer().frame(height: 1).id("bottomAnchor")
            }
            .padding(.vertical, 16)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollBottomKey.self,
                        value: geo.frame(in: .named("chatScroll")).maxY
                    )
                }
            )
            .background(
                ScrollViewFinder { found in
                    chatScrollViewRef = found
                }
                .frame(width: 0, height: 0)
            )
        }
        .coordinateSpace(name: "chatScroll")

        if #available(macOS 15.0, *) {
            base.onScrollGeometryChange(for: ScrollSnapshot.self) { geo in
                ScrollSnapshot(
                    offset: geo.contentOffset.y,
                    content: geo.contentSize.height,
                    container: geo.containerSize.height
                )
            } action: { old, new in
                handleScrollChange(old: old, new: new)
            }
        } else {
            base.onPreferenceChange(ScrollBottomKey.self) { bottomMaxY in
                guard viewportHeight > 0 else { return }
                setAtBottom(bottomMaxY <= viewportHeight + bottomThreshold)
            }
        }
    }

    /// Sticky-Pin 핵심 규칙:
    /// 1) 콘텐츠 성장 + 핀 ON → 즉시 하단 재스크롤 (말풍선 높이가 비동기로 확정되는 동안 타이머 없이 추적)
    /// 2) 오프셋 상승 드래그(콘텐츠 불변, 하단 아님) → 핀 OFF — 읽던 위치 유지, 버튼 표시
    /// 3) 수동으로 맨 아래 도달 → 핀 ON 재개
    private func handleScrollChange(old: ScrollSnapshot, new: ScrollSnapshot) {
        guard new != old else { return }

        let maxOffset = new.content - new.container
        let atBottomNow = new.offset >= maxOffset - bottomThreshold
        let contentGrew = new.content > old.content + 0.5
        let contentStable = abs(new.content - old.content) < 0.5
        let scrolledUp = new.offset < old.offset - 1

        logGeometryDiagnostic(new)

        // 사용자 드래그 판정은 콘텐츠 크기가 변하지 않았을 때만 (고무줄 반동 오탈 방지)
        if scrolledUp && contentStable && !atBottomNow {
            setPin(false)
        }
        if atBottomNow {
            setPin(true)
        }
        setAtBottom(atBottomNow)

        if pinnedToBottom && contentGrew {
            // action은 뷰 갱신 트랜잭션 안에서 호출되므로 다음 런루프로 지연해 적용
            DebugLogger.shared.debug("SCROLL", String(format: "핀 추종 재스크롤: 콘텐츠 %.0f → %.0f", old.content, new.content))
            DispatchQueue.main.async {
                jumpToBottom()
            }
        }
    }

    /// ScrollGeometry 값과 실제 AppKit 상태를 한 번 대조해 숨은 좌표 불일치를 노출한다.
    private func logGeometryDiagnostic(_ snapshot: ScrollSnapshot) {
        guard !didLogGeometryDiagnostic, let scrollView = chatScrollViewRef, let doc = scrollView.documentView else { return }
        didLogGeometryDiagnostic = true
        let clip = scrollView.contentView
        DebugLogger.shared.debug("SCROLL", String(
            format: "지오메트리 대조: geo(content=%.1f container=%.1f offset=%.1f) | appkit(doc=%.1f clip=%.1f originY=%.1f insets=%.1f/%.1f)",
            snapshot.content, snapshot.container, snapshot.offset,
            doc.bounds.height, clip.bounds.height, clip.bounds.origin.y,
            scrollView.contentInsets.top, scrollView.contentInsets.bottom
        ))
    }

    private func setPin(_ value: Bool) {
        guard value != pinnedToBottom else { return }
        DebugLogger.shared.debug("SCROLL", "하단 핀 \(value ? "설정" : "해제")")
        pinnedToBottom = value
    }

    private func setAtBottom(_ value: Bool) {
        guard value != isAtBottom else { return }
        DebugLogger.shared.debug("SCROLL", "하단 판정 변경: \(value ? "복귀" : "이탈")")
        isAtBottom = value
    }

    /// 문서 끝까지의 절대 최대 오프셋으로 즉시 이동.
    /// 프록시 앵커 정렬과 달리 패딩·스냅샷·좌표계 해석 오차가 없다.
    private func jumpToBottom() {
        guard let scrollView = chatScrollViewRef, let doc = scrollView.documentView else { return }
        let clipHeight = scrollView.contentView.bounds.height
        let docHeight = doc.bounds.height
        let targetY = max(0, docHeight - clipHeight)
        scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: targetY))
    }

    /// 초기 위치 보정용 수렴 스크롤 (이후 추종은 핀이 담당).
    /// 새 요청이 오면 이전 예약을 취소해 누적 스크롤 폭탄을 방지한다.
    private func scrollToFitBottom() {
        pendingScrollWorks.forEach { $0.cancel() }
        pendingScrollWorks.removeAll()
        for delay in [0.0, 0.15, 0.4, 0.9] {
            let work = DispatchWorkItem {
                jumpToBottom()
            }
            pendingScrollWorks.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    // MARK: - 검색 결과 메시지 점프 (v2.1 T-97 고도화)

    /// 되돌리기 확인 문구 (T-339) — 선택 메시지 포함 삭제 수 + 기억 회수 안내
    private var rewindConfirmText: String {
        guard let id = pendingRewindMessageID,
              let messages = viewModel.currentSession?.messages,
              let cutIndex = messages.firstIndex(where: { $0.id == id }) else {
            return "이 지점부터 대화가 삭제됩니다."
        }
        let count = messages.count - cutIndex
        return "이 메시지 포함 \(count)개 메시지가 삭제되고 입력창에 담깁니다. 겹치는 자동 기억도 함께 회수됩니다. (수동·핀 기억은 보호)"
    }

    /// 점프 시작 — WKWebView 비동기 높이 수렴을 고려해 수렴형 보정 점프를 예약한다 (v1.3 패턴 재사용)
    private func beginMessageJump(to id: UUID) {
        pendingJumpMessageID = id
        lastAppliedJumpOffset = nil
        DebugLogger.shared.info("SCROLL", "[FEATURE] 메시지 점프 시작: \(id)")
        for delay in [0.15, 0.4, 0.9, 1.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                jumpToPendingMessage()
            }
        }
        // 안전 종료 — 수집 창 닫기 (하이라이트 해제는 VM이 5초 담당)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard pendingJumpMessageID == id else { return }
            if MessageAnchorRegistry.shared.view(for: id) == nil {
                DebugLogger.shared.warn("SCROLL", "메시지 점프 포기: 앵커 미발견 (대상 말풍선 미렌더링?)")
            }
            pendingJumpMessageID = nil
        }
    }

    /// 대상 말풍선이 뷰포트 상단 90pt 지점에 오도록 절대 오프셋 이동 (v2.1 T-109b).
    /// 위치는 MessageAnchorRegistry의 NSView를 documentView 좌표로 직접 변환해 구한다 —
    /// 스크롤과 무관한 안정 값이라 preference 방식의 진동 루프가 원천적으로 없다.
    /// WKWebView 높이가 비동기로 늦게 자라므로 수집 창(2초) 동안 재적용으로 수렴시킨다.
    private func jumpToPendingMessage() {
        guard let id = pendingJumpMessageID,
              let scrollView = chatScrollViewRef,
              let doc = scrollView.documentView,
              let anchor = MessageAnchorRegistry.shared.view(for: id) else { return }
        let docY = doc.convert(anchor.bounds, from: anchor).minY
        guard docY > 0 else { return } // 아직 0높이 미렌더링 — 다음 재시도에서 수렴
        let targetOffset = max(0, docY - 90)
        if let last = lastAppliedJumpOffset, abs(last - targetOffset) < 1 {
            return // 위치 수렴 — 재적용 불필요
        }
        scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: targetOffset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        setPin(false)
        setAtBottom(false)
        lastAppliedJumpOffset = targetOffset
        DebugLogger.shared.info("SCROLL", "[FEATURE] 메시지 점프 적용(AppKit): docY=\(Int(docY)) → offset=\(Int(targetOffset))")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(theme.tertiaryText)
            Text("메시지를 입력해 대화를 시작하세요")
                .font(.callout)
                .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        // 뷰포트를 채워 수직 중앙에 배치 (T-41) — 초기 0일 때는 최소값 폴백
        .frame(minHeight: max(viewportHeight - 32, 200))
    }
}
