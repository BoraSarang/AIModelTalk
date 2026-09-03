import SwiftUI
import UniformTypeIdentifiers

// MARK: - 입력창 (모델/스킬/프롬프트 선택 + 토큰 미터 + 전송)

struct ChatInputBarView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject private var settings = AppSettings.shared

    @State private var keyMonitor: Any?
    @State private var showFileImporter = false
    @State private var showTemplatePopover = false
    @State private var showSystemPrompt = false
    @State private var showCompare = false

    var body: some View {
        VStack(spacing: 8) {
            // 이미지 첨부 썸네일 행 (T-71)
            if !viewModel.pendingAttachments.isEmpty {
                attachmentThumbnails
            }

            // 첨부 안내 문구 (비전 미지원 모델 등)
            if let notice = viewModel.attachmentNotice {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button {
                        viewModel.attachmentNotice = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
            }

            TextEditor(text: $viewModel.inputText)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 36, maxHeight: 120)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: DS.radiusBubble).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: DS.radiusBubble).strokeBorder(Color(nsColor: .separatorColor)))

            // 주 라인 — 자주 쓰는 것만 (모델·스킬·첨부·웹) + ⋯ 더보기
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 8) {
                    ModelPickerPopover(viewModel: viewModel)
                    SkillPickerPopover(viewModel: viewModel)
                    // 통합 첨부 — 파일 선택(클립보드는 Cmd+V 자동 판별)
                    Menu {
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("파일 선택…", systemImage: "photo.on.rectangle")
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 13))
                            Text("첨부")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("이미지 첨부 (최대 \(ChatViewModel.maxAttachments)개) — 붙여넣기(⌘V)로도 첨부")
                    // 웹 검색 토글 (v1.8 T-72)
                    if AppSettings.shared.webSearchEnabled {
                        Button {
                            viewModel.webSearchForNextSend.toggle()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "globe")
                                    .font(.system(size: 13))
                                Text("웹")
                                    .font(.caption)
                            }
                            .foregroundStyle(viewModel.webSearchForNextSend ? Color.accentColor : Color.secondary)
                            .padding(.horizontal, 4)
                            .background(viewModel.webSearchForNextSend ? Color.accentColor.opacity(0.15) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .help(viewModel.webSearchForNextSend ? "웹 검색 켜짐 — 이번 전송에 적용" : "이번 전송에 웹 검색 사용")
                    }
                    // ⋯ 더보기 — 덜 쓰는 기능 (아이콘+라벨 컨텍스트 메뉴)
                    Menu {
                        Button {
                            showCompare = true
                        } label: {
                            Label("병렬 비교", systemImage: "rectangle.split.2x1")
                        }
                        Button {
                            showSystemPrompt = true
                        } label: {
                            Label("시스템 프롬프트", systemImage: "text.badge.plus")
                        }
                        Button {
                            showTemplatePopover = true
                        } label: {
                            Label("프롬프트 템플릿 (⌘⇧T)", systemImage: "text.book.closed")
                        }
                        Divider()
                        Toggle("MCP 도구 사용", isOn: $settings.mcpToolsEnabled)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("더 보기 — 비교·시스템 프롬프트·템플릿·MCP")
                }
                Spacer()
                tokenMeter
                if viewModel.isLoading {
                    Button {
                        viewModel.stopStreaming()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(".", modifiers: .command)
                    .help("응답 중지 (Cmd+.)")
                } else {
                    Button {
                        viewModel.send()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(viewModel.canSend ? Color.accentColor : Color.secondary.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.canSend)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .onDrop(of: [.image], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result else { return }
            for url in urls where viewModel.pendingAttachments.count < ChatViewModel.maxAttachments {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: url) {
                    viewModel.addImageAttachment(data, fileName: url.lastPathComponent)
                }
            }
        }
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // 패널 대상 Return은 패널 모니터가 처리 — 메인 이중 전송 방지 (T-44)
                if event.window is QuickPanel { return event }
                // 붙여넣기 통합 (T-207 v0.2.1) — 클립보드에 이미지가 있으면 첨부, 없으면 텍스트(네이티브)로 통과
                if event.modifierFlags.contains(.command)
                    && !event.modifierFlags.contains(.shift)
                    && !event.modifierFlags.contains(.control)
                    && !event.modifierFlags.contains(.option)
                    && event.charactersIgnoringModifiers?.lowercased() == "v" {
                    if clipboardHasImage() {
                        pasteImageFromClipboard()
                        return nil // 이미지 첨부로 소비
                    }
                    return event // 이미지 없음 → 기본 텍스트 붙여넣기
                }
                // 프롬프트 템플릿 (⌘⇧T) — "⋯" 메뉴 단축키 유지
                if event.modifierFlags.contains(.command)
                    && event.modifierFlags.contains(.shift)
                    && !event.modifierFlags.contains(.control)
                    && !event.modifierFlags.contains(.option)
                    && event.charactersIgnoringModifiers?.lowercased() == "t" {
                    showTemplatePopover = true
                    return nil
                }
                if event.keyCode == 36 && !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.control) && !event.modifierFlags.contains(.option) {
                    if event.modifierFlags.contains(.shift) {
                        // Shift+Return: 줄바꿈 허용 (기본 동작)
                        return event
                    }
                    // Return: 전송
                    if viewModel.canSend {
                        viewModel.send()
                    }
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
        // "⋯" 메뉴에서 연 popover들 — 본체 VStack에 앵커 (v0.2.1)
        .popover(isPresented: $showTemplatePopover, arrowEdge: .bottom) {
            PromptTemplatePopoverView(viewModel: viewModel) {
                showTemplatePopover = false
            }
        }
        .popover(isPresented: $showSystemPrompt, arrowEdge: .bottom) {
            systemPromptEditor
        }
        .popover(isPresented: $showCompare, arrowEdge: .bottom) {
            CompareSelectorView(viewModel: viewModel, isPresented: $showCompare)
        }
    }

    // MARK: - 시스템 프롬프트 편집 (⋯ 메뉴 popover 콘텐츠)

    private var systemPromptEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("기본 시스템 프롬프트")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text("이 프롬프트는 모든 새 대화의 기본 지시로 적용됩니다")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            TextEditor(text: $settings.systemPrompt)
                .font(.system(size: 12))
                .frame(width: 320, height: 120)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: DS.radiusControl).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: DS.radiusControl).strokeBorder(Color(nsColor: .separatorColor)))
        }
        .padding(12)
    }

    // MARK: - 이미지 첨부 (v1.8 T-71)

    private var attachmentThumbnails: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.pendingAttachments) { attachment in
                    let thumb = 72 as CGFloat
                    ZStack(alignment: .topTrailing) {
                        if let image = NSImage(data: attachment.imageData) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: thumb, height: thumb)
                                .clipShape(RoundedRectangle(cornerRadius: DS.radiusCard))
                                .overlay(RoundedRectangle(cornerRadius: DS.radiusCard).strokeBorder(Color(nsColor: .separatorColor)))
                        }
                        // 닫기 오버레이 — 항상 보이는 검은 반투명 원형 배경 + 흰 x (v0.2.1 시인성 강화)
                        Button {
                            viewModel.removeAttachment(id: attachment.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 16, height: 16)
                                .background(Circle().fill(.black.opacity(0.6)))
                                .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
                                .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                        }
                        .buttonStyle(.plain)
                        .offset(x: 5, y: -5)
                        .help("첨부 삭제")
                    }
                }
                if viewModel.pendingAttachments.count < ChatViewModel.maxAttachments {
                    Button {
                        showFileImporter = true
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .medium))
                            Text("\(viewModel.pendingAttachments.count)/\(ChatViewModel.maxAttachments)")
                                .font(.system(size: 9))
                        }
                        .foregroundStyle(.secondary)
                        .frame(width: 72, height: 72)
                        .background(RoundedRectangle(cornerRadius: DS.radiusCard).fill(Color(nsColor: .controlBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: DS.radiusCard).strokeBorder(Color(nsColor: .separatorColor), style: StrokeStyle(lineWidth: 1, dash: [4])))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
        }
        .background(RoundedRectangle(cornerRadius: DS.radiusBubble).fill(Color(nsColor: .controlBackgroundColor).opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusBubble).strokeBorder(Color(nsColor: .separatorColor)))
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { continue }
            handled = true
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in
                    viewModel.addImageAttachment(data, fileName: provider.suggestedName)
                }
            }
        }
        return handled
    }

    // MARK: - 붙여넣기 통합 (v0.2.1) — 클립보드 이미지 첨부/텍스트 통과

    private func clipboardHasImage() -> Bool {
        let pasteboard = NSPasteboard.general
        return pasteboard.data(forType: .png) != nil
            || pasteboard.data(forType: .tiff) != nil
            || pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg")) != nil
    }

    private func pasteImageFromClipboard() {
        let pasteboard = NSPasteboard.general
        guard let imageData = pasteboard.data(forType: .png)
                ?? pasteboard.data(forType: .tiff)
                ?? pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg")) else {
            viewModel.attachmentNotice = "클립보드에 이미지가 없습니다."
            return
        }
        viewModel.addImageAttachment(imageData, fileName: "clipboard.png")
    }

    // MARK: - 토큰 사용량 미터

    private var tokenMeter: some View {
        let session = viewModel.currentSession
        let used = TokenEstimator.estimateConversation(
            systemPrompt: viewModel.buildSystemPrompt(),
            messages: session?.messages ?? []
        )
        let limit = viewModel.selectedModel.contextLimit
        let ratio = Double(used) / Double(limit)
        let color: Color = ratio > 0.9 ? .red : ratio > 0.7 ? .orange : .secondary
        // tokenTick 구독 — 실측 갱신 시 재렌더 (v1.9 T-76)
        _ = viewModel.tokenTick
        let totals = SessionTokens.total(for: session?.messages ?? [])

        return HStack(spacing: 8) {
            // 실측 누적 토큰은 툴팁으로 (v0.2.1 컴팩트) — 게이지 위 호버 시 표시
            let totalsLabel = totals.isEmpty
                ? "현재 대화 예상 토큰"
                : "추정 \(used) · 실측 ↑\(SessionTokens.compact(totals.prompt)) ↓\(SessionTokens.compact(totals.completion))"
            Text("토큰")
                .font(.caption2)
                .foregroundStyle(.secondary)
            // T-208 토큰 예산 게이지 — 사용량 비율 막대 표시
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(color)
                        .frame(width: max(2, geo.size.width * CGFloat(min(max(ratio, 0), 1))))
                }
            }
            .frame(width: 60, height: 5)
            .help(totalsLabel)
            Text("\(used.formatted()) / \(limit.formatted())")
                .font(.caption2.monospaced())
                .foregroundStyle(color)
                .help(totalsLabel)
            if used > limit {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .help("컨텍스트 한도를 초과했습니다. 이전 기록이 잘릴 수 있습니다.")
            }
        }
    }
}
