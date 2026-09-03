import SwiftUI
import UniformTypeIdentifiers

// MARK: - 입력창 (모델/스킬/프롬프트 선택 + 토큰 미터 + 전송)

struct ChatInputBarView: View {
    @ObservedObject var viewModel: ChatViewModel

    @State private var keyMonitor: Any?
    @State private var showFileImporter = false

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

            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 12) {
                    ModelPickerPopover(viewModel: viewModel)
                    SkillPickerPopover(viewModel: viewModel)
                    SystemPromptPopover()
                    // 이미지 첨부 버튼 (파일 선택)
                    Button {
                        showFileImporter = true
                    } label: {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("이미지 첨부 (최대 \(ChatViewModel.maxAttachments)개)")
                    // 클립보드 이미지 붙여넣기
                    Button {
                        pasteImageFromClipboard()
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("클립보드의 이미지 붙여넣기 (⌘⇧V)")
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                    // 웹 검색 토글 (v1.8 T-72)
                    if AppSettings.shared.webSearchEnabled {
                        Button {
                            viewModel.webSearchForNextSend.toggle()
                        } label: {
                            Image(systemName: viewModel.webSearchForNextSend ? "globe" : "globe")
                                .font(.system(size: 14))
                                .foregroundStyle(viewModel.webSearchForNextSend ? Color.accentColor : Color.secondary)
                                .background(viewModel.webSearchForNextSend ? Color.accentColor.opacity(0.15) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .help(viewModel.webSearchForNextSend ? "웹 검색 켜짐 — 이번 전송에 적용" : "이번 전송에 웹 검색 사용")
                    }
                    MCPToolSelectorView()
                    // 병렬 모델 비교 (T-201) — 같은 대화 컨텍스트로 여러 모델 비교
                    CompareModelPickerButton(viewModel: viewModel)
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
    }

    // MARK: - 이미지 첨부 (v1.8 T-71)

    private var attachmentThumbnails: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.pendingAttachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        if let image = NSImage(data: attachment.imageData) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: DS.radiusCard))
                                .overlay(RoundedRectangle(cornerRadius: DS.radiusCard).strokeBorder(Color(nsColor: .separatorColor)))
                        }
                        Button {
                            viewModel.removeAttachment(id: attachment.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.white, .black.opacity(0.65))
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
                        .frame(width: 56, height: 56)
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
            Text("토큰")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(used.formatted()) / \(limit.formatted())")
                .font(.caption2.monospaced())
                .foregroundStyle(color)
            if used > limit {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .help("컨텍스트 한도를 초과했습니다. 이전 기록이 잘릴 수 있습니다.")
            }
            if !totals.isEmpty {
                Divider()
                    .frame(height: 10)
                Label(
                    "실측 ↑\(SessionTokens.compact(totals.prompt)) ↓\(SessionTokens.compact(totals.completion))",
                    systemImage: "checkmark.seal"
                )
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Color(nsColor: .systemGray))
                .help("API가 보고한 이 세션의 누적 토큰 (프롬프트/완료)")
            }
        }
    }
}
