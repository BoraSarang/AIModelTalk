import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - 입력창 (모델/스킬/프롬프트 선택 + 토큰 미터 + 전송)

struct ChatInputBarView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.theme) private var theme

    @State private var keyMonitor: Any?
    @State private var showFileImporter = false
    @State private var showTemplatePopover = false
    @State private var showSystemPrompt = false
    @State private var showCompare = false
    @State private var showTokenStatus = false
    @State private var showWorkspaceFiles = false
    @State private var expandedWorkspacePaths: Set<String> = []
    @State private var workspaceRootNodes: [WorkspaceFileNode] = []
    @State private var showImageModelPicker = false
    @State private var showCodingModelPicker = false
    @State private var showAudioModelPicker = false

    var body: some View {
        VStack(spacing: 8) {
            // 용도 모드 세그먼트 (v0.3.x 축4, T-329) — 채팅/이미지/코딩
            if let sessionID = viewModel.currentSessionID {
                HStack {
                    Picker("", selection: Binding(
                        get: { viewModel.currentSession?.mode ?? .chat },
                        set: { viewModel.setMode($0, for: sessionID) }
                    )) {
                        ForEach(ChatMode.allCases) { mode in
                            Label(mode.label, systemImage: mode.icon).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 344, alignment: .leading)
                    Spacer()
                }
            }

            // 모드 전용 컨트롤 줄 (이미지/코딩) — T-329
            if let sessionID = viewModel.currentSessionID,
               let mode = viewModel.currentSession?.mode, mode != .chat {
                modeControlBar(sessionID: sessionID, mode: mode)
            }

            // 코딩: 워크스페이스 파일 목록 접이식 패널 (T-329)
            if showWorkspaceFiles {
                workspaceFilesPanel
            }

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
                .background(RoundedRectangle(cornerRadius: theme.radiusBubble).fill(theme.inputBackground))
                .overlay(RoundedRectangle(cornerRadius: theme.radiusBubble).strokeBorder(theme.inputBorder))

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
                            .foregroundStyle(viewModel.webSearchForNextSend ? theme.accentColor : theme.secondaryText)
                            .padding(.horizontal, 4)
                            .background(viewModel.webSearchForNextSend ? theme.accentColor.opacity(0.15) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: theme.inputCornerRadius))
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
                tokenStatusBadge
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
                            .foregroundStyle(viewModel.canSend ? theme.accentColor : theme.secondaryText.opacity(0.4))
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
        .popover(isPresented: $showTokenStatus, arrowEdge: .bottom) {
            tokenStatusPopover
        }
    }

    // MARK: - 용도 모드 컨트롤 (T-329) — 이미지/코딩/오디오 전용 상태줄

    @ViewBuilder
    private func modeControlBar(sessionID: UUID, mode: ChatMode) -> some View {
        switch mode {
        case .chat: EmptyView()
        case .image: imageModeBar(sessionID: sessionID)
        case .coding: codingModeBar(sessionID: sessionID)
        case .audio: audioModeBar(sessionID: sessionID)
        }
    }

    private func imageModeBar(sessionID: UUID) -> some View {
        HStack(spacing: 8) {
            Text("생성 모델")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
            imageModelBadge(sessionID: sessionID)
                .popover(isPresented: $showImageModelPicker, arrowEdge: .bottom) {
                    modelPickerPopover(
                        title: "이미지 생성 모델",
                        sections: [ModelSection(header: nil, models: ModelCatalog.imageModels)],
                        isSelected: { viewModel.selectedImageModel(for: sessionID) != nil ? $0 == viewModel.selectedImageModel(for: sessionID) : $0 == ModelCatalog.imageModels.first }
                    ) { model in
                        viewModel.setImageModel(model, for: sessionID)
                    }
                }
            Text("프롬프트를 입력하고 전송하면 이미지가 생성됩니다")
                .font(.caption2)
                .foregroundStyle(theme.secondaryText)
            Spacer()
        }
    }

    private func imageModelBadge(sessionID: UUID) -> some View {
        let selected = viewModel.selectedImageModel(for: sessionID) ?? ModelCatalog.imageModels.first
        return Button {
            showImageModelPicker = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "photo.on.rectangle.angled")
                Text(selected?.displayName ?? "이미지 모델")
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
            }
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: theme.inputCornerRadius).fill(theme.inputBackground))
            .overlay(RoundedRectangle(cornerRadius: theme.inputCornerRadius).strokeBorder(theme.inputBorder))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("이미지 생성 모델 선택")
    }

    private func audioModeBar(sessionID: UUID) -> some View {
        HStack(spacing: 8) {
            Text("합성 모델")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
            audioModelBadge(sessionID: sessionID)
                .popover(isPresented: $showAudioModelPicker, arrowEdge: .bottom) {
                    modelPickerPopover(
                        title: "오디오 TTS 모델",
                        sections: [ModelSection(header: nil, models: ModelCatalog.audioModels)],
                        isSelected: { viewModel.selectedAudioModel(for: sessionID) != nil ? $0 == viewModel.selectedAudioModel(for: sessionID) : $0 == ModelCatalog.audioModels.first }
                    ) { model in
                        viewModel.setAudioModel(model, for: sessionID)
                    }
                }
            Text("텍스트를 입력하고 전송하면 음성이 합성됩니다")
                .font(.caption2)
                .foregroundStyle(theme.secondaryText)
            Spacer()
        }
    }

    private func audioModelBadge(sessionID: UUID) -> some View {
        let selected = viewModel.selectedAudioModel(for: sessionID) ?? ModelCatalog.audioModels.first
        return Button {
            showAudioModelPicker = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                Text(selected?.displayName ?? "TTS 모델")
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
            }
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: theme.inputCornerRadius).fill(theme.inputBackground))
            .overlay(RoundedRectangle(cornerRadius: theme.inputCornerRadius).strokeBorder(theme.inputBorder))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("오디오 TTS 모델 선택")
    }

    private func codingModeBar(sessionID: UUID) -> some View {
        HStack(spacing: 10) {
            Text("코딩 모델")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
            codingModelBadge(sessionID: sessionID)
                .popover(isPresented: $showCodingModelPicker, arrowEdge: .bottom) {
                    codingModelPickerContent(sessionID: sessionID)
                }

            Divider().frame(height: 14)

            // 워크스페이스 폴더
            if let path = settings.workspaceFolder {
                Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "folder.fill")
                    .font(.caption)
                    .foregroundStyle(theme.accentColor)
                    .help(path)
                Button("폴더 변경…") { pickWorkspaceFolder() }
                    .controlSize(.small)
                Button(showWorkspaceFiles ? "파일 숨기기" : "파일 목록") {
                    showWorkspaceFiles.toggle()
                    if showWorkspaceFiles { reloadWorkspaceTree() }
                }
                .controlSize(.small)
                Button("해제") {
                    settings.workspaceFolder = nil
                    workspaceRootNodes = []
                    showWorkspaceFiles = false
                }
                .controlSize(.small)
            } else {
                Text("폴더 미지정 — 파일 도구 비활성")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button("폴더 선택…") { pickWorkspaceFolder() }
                    .controlSize(.small)
            }
            Spacer()
            Text("코딩 전용 모델로 파일 작업을 지시하세요")
                .font(.caption2)
                .foregroundStyle(theme.secondaryText)
        }
    }

    private func codingModelBadge(sessionID: UUID) -> some View {
        let selected = viewModel.selectedCodingModel(for: sessionID)
        return Button {
            showCodingModelPicker = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                Text(selected?.displayName ?? "선택 안 됨 (현재 모델 사용)")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
            }
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: theme.inputCornerRadius).fill(theme.inputBackground))
            .overlay(RoundedRectangle(cornerRadius: theme.inputCornerRadius).strokeBorder(theme.inputBorder))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(selected.map { "\($0.displayName) · \($0.provider.rawValue)" } ?? "미선택 시 현재 모델 사용")
    }

    private func codingModelPickerContent(sessionID: UUID) -> some View {
        let choices = codingModelChoices
        var sections: [ModelSection] = []
        if !choices.preferred.isEmpty {
            sections.append(ModelSection(header: "추천", models: choices.preferred))
        }
        sections.append(ModelSection(header: "전체", models: Array(choices.rest.prefix(20))))
        return modelPickerPopover(
            title: "코딩 모델",
            sections: sections,
            isSelected: { viewModel.selectedCodingModel(for: sessionID) == $0 }
        ) { model in
            viewModel.setCodingModel(model, for: sessionID)
        }
    }

    /// 공통 모델 선택 팝오버 — Menu 미사용(IME 입력 교착 원인) · 추천/전체 섹션 목록 (T-329)
    private func modelPickerPopover(
        title: String,
        sections: [ModelSection],
        isSelected: @escaping (AIModel) -> Bool,
        onSelect: @escaping (AIModel) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(theme.secondaryText)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(sections) { section in
                        if let header = section.header {
                            Text(header)
                                .font(.caption2)
                                .foregroundStyle(theme.tertiaryText)
                                .padding(.top, 6)
                                .padding(.bottom, 1)
                        }
                        ForEach(section.models) { model in
                            Button {
                                onSelect(model)
                            } label: {
                                HStack(spacing: 6) {
                                    Text("\(model.displayName) · \(model.provider.rawValue)")
                                        .font(.caption)
                                        .foregroundStyle(theme.primaryText)
                                        .lineLimit(1)
                                    Spacer()
                                    if isSelected(model) {
                                        Image(systemName: "checkmark")
                                            .font(.caption)
                                            .foregroundStyle(theme.accentColor)
                                    }
                                }
                                .contentShape(Rectangle())
                                .padding(.horizontal, 4)
                                .padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: theme.inputCornerRadius).fill(theme.inputBackground.opacity(0.4)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if sections.allSatisfy({ $0.models.isEmpty }) {
                        Text("연결된 활성 모델이 없습니다 — 설정에서 모델을 활성화하세요")
                            .font(.caption)
                            .foregroundStyle(theme.tertiaryText)
                            .padding(.vertical, 8)
                    }
                }
            }
            .frame(width: 280)
            .frame(maxHeight: 300)
        }
        .padding(10)
    }

/// 코딩 추천 세트 — 사전 정의 코딩 특화 모델 ID ∩ 연결된 활성 모델 (T-329, v0.3.3 T-331 갱신)
    /// 검증된 무료 ID는 정식 ID로 기재 (Zen/OpenRouter 2026-09-05 대조). 기존 유료 ID는 키 보유자용으로 유지.
    private var codingPreferredIDs: Set<String> {
        Set(["claude-sonnet-4-5", "claude-3-7-sonnet-20250219", "claude-3-5-sonnet-20241022",
              "gpt-4.1", "gpt-4o", "gpt-4o-mini", "gpt-oss-20b", "o3-mini",
              "gemini-2.5-pro", "gemini-2.5-flash", "deepseek-chat", "deepseek-reasoner",
              "qwen2.5-coder", "codestral", "mistral-nemo", "command-r-plus",
              "opencode/muse-spark-1.3-contributor-free", "muse-spark-1.3-contributor-free",
              "cohere/north-mini-code:free",
              "poolside/laguna-s-2.1:free", "poolside/laguna-xs-2.1:free",
              "nvidia/nemotron-3-ultra-550b-a55b:free", "opencode/nemotron-3-ultra-free",
              "nvidia/nemotron-3-super-120b-a12b:free",
              "nvidia/nemotron-3.5-lightning:free", "opencode/nemotron-3.5-lightning-free",
              "minimax/minimax-m3:free", "minimax/minimax-m2.7:free",
              "z-ai/glm-5.2:free",
              "thinkingmachines/inkling:free", "thinkingmachines/inkling-small:free",
              "dots-studio/dots-3-note-preview:free",
              "inclusionai/ling-3.0-flash-fin:free", "opencode/ling-3.0-flash-fin-free",
              "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free",
              "qwen/qwen3-coder-480b-a35b-instruct"])
    }

    /// 문서 추천 순위 (T-332) — Muse Spark → North Mini Code → Qwen3-Coder → Big Pickle
    private var codingRankedOrder: [(provider: Provider, id: String)] {
        [
            (.opencode, "opencode/muse-spark-1.3-contributor-free"),
            (.openRouter, "cohere/north-mini-code:free"),
            (.nvidia, "qwen/qwen3-coder-480b-a35b-instruct"),
            (.opencode, "opencode/big-pickle"),
        ]
    }

    private var codingModelChoices: (preferred: [AIModel], rest: [AIModel]) {
        let active = ModelCatalog.shared.models.filter { ModelCatalog.shared.isEnabled($0) }
        let preferredUnordered = active.filter { codingPreferredIDs.contains($0.id) || $0.id.localizedCaseInsensitiveContains("coder") }
        // 추천 섹션은 문서 순위 고정, 나머지는 활성 순서 유지
        let rankIndex: [String: Int] = Dictionary(
            uniqueKeysWithValues: codingRankedOrder.enumerated().map { ($1.provider.rawValue + ":" + $1.id, $0) })
        let preferred = preferredUnordered.sorted {
            (rankIndex[$0.provider.rawValue + ":" + $0.id] ?? Int.max,
             $0.provider.rawValue, $0.id)
            <
            (rankIndex[$1.provider.rawValue + ":" + $1.id] ?? Int.max,
             $1.provider.rawValue, $1.id)
        }
        let rest = active.filter { model in
            !preferred.contains { $0.id == model.id && $0.provider == model.provider }
        }
        return (preferred, rest)
    }

    private func pickWorkspaceFolder() {
        let panel = NSOpenPanel()
        panel.title = "코딩 워크스페이스 폴더 선택"
        panel.prompt = "선택"
        panel.message = "모델이 읽고 쓸 수 있는 로컬 프로젝트 폴더를 선택하세요."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.workspaceFolder = url.path
            reloadWorkspaceTree()
            DebugLogger.shared.info("MCP", "[FEATURE] 코딩 워크스페이스 폴더 지정: \(url.path)")
        }
    }

    // MARK: - 코딩 파일 목록 패널 (T-329)

    private var workspaceFilesPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.caption)
                Text(URL(fileURLWithPath: settings.workspaceFolder ?? "").lastPathComponent)
                    .font(.caption.weight(.semibold))
                Spacer()
                Button("새로고침") { reloadWorkspaceTree() }
                    .controlSize(.small)
                Text("상위 3레벨 · 숨김 파일 제외")
                    .font(.caption2)
                    .foregroundStyle(theme.tertiaryText)
            }
            Divider()
            if workspaceRootNodes.isEmpty {
                Text("읽을 수 있는 파일이 없습니다")
                    .font(.caption)
                    .foregroundStyle(theme.tertiaryText)
                    .padding(.vertical, 6)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(workspaceRootNodes) { node in
                            WorkspaceFileRow(
                                node: node,
                                expandedPaths: $expandedWorkspacePaths,
                                onCopyPath: { copyToPasteboard($0) },
                                onInsertPath: { insertPathIntoInput($0) }
                            )
                        }
                    }
                }
            }
        }
        .padding(8)
        .frame(maxHeight: 220)
        .background(RoundedRectangle(cornerRadius: theme.radiusBubble).fill(theme.inputBackground.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: theme.radiusBubble).strokeBorder(theme.inputBorder))
    }

    /// 파일 트리를 한 번만 스캔해 캐시 — 키 입력 body 재평가 시 FileManager I/O 방지 (성능 수정)
    private func reloadWorkspaceTree() {
        workspaceRootNodes = workspaceTree()
    }

    private func workspaceTree(at url: URL? = nil, depth: Int = 0) -> [WorkspaceFileNode] {
        guard depth <= 3 else { return [] }
        let base = url ?? (settings.workspaceFolder.map { URL(fileURLWithPath: $0) })
        guard let base else { return [] }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        let sorted = items.sorted { a, b in
            let ad = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let bd = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if ad != bd { return ad }
            return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
        }
        return sorted.prefix(400).map { item in
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return WorkspaceFileNode(
                path: item.path,
                name: item.lastPathComponent,
                isDirectory: isDir,
                children: isDir ? workspaceTree(at: item, depth: depth + 1) : []
            )
        }
    }

    private func insertPathIntoInput(_ path: String) {
        viewModel.inputText += (viewModel.inputText.isEmpty ? "" : " ") + path
    }

    private func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        DebugLogger.shared.debug("MCP", "J 로컬 파일 경로 복사: \(string)")
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
                .background(RoundedRectangle(cornerRadius: theme.radiusControl).fill(theme.inputBackground))
                .overlay(RoundedRectangle(cornerRadius: theme.radiusControl).strokeBorder(theme.inputBorder))
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
                                .clipShape(RoundedRectangle(cornerRadius: theme.radiusCard))
                                .overlay(RoundedRectangle(cornerRadius: theme.radiusCard).strokeBorder(theme.inputBorder))
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
                        .background(RoundedRectangle(cornerRadius: theme.radiusCard).fill(theme.inputBackground))
                        .overlay(RoundedRectangle(cornerRadius: theme.radiusCard).strokeBorder(theme.inputBorder, style: StrokeStyle(lineWidth: 1, dash: [4])))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
        }
        .background(RoundedRectangle(cornerRadius: theme.radiusBubble).fill(theme.inputBackground.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: theme.radiusBubble).strokeBorder(theme.inputBorder))
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

    // MARK: - 토큰 상태 배지 (v0.3.2) — 선택 모델 실측 사용/남음 + 계정 풀(Anthropic)

    private func snapshot() -> ModelTokenSnapshot {
        TokenQuotaStore.snapshot(
            model: viewModel.selectedModel,
            messages: viewModel.currentSession?.messages ?? [],
            systemPrompt: viewModel.buildSystemPrompt()
        )
    }

    private var tokenStatusBadge: some View {
        // tokenTick 실측 갱신 구독 — 토큰 저장 시 재렌더 (v1.9 T-76 기존 패턴)
        _ = viewModel.tokenTick
        let snapshot = self.snapshot()
        let quota = TokenQuotaStore.shared.accountQuotas[viewModel.selectedModel.provider]
        let hasAccountPool = quota != nil
        let ratio = hasAccountPool ? quota?.ratio ?? 0 : snapshot.ratio
        let remaining = hasAccountPool ? (quota?.remaining ?? 0) : snapshot.remaining
        if !snapshot.hasLimit && !hasAccountPool { return AnyView(EmptyView()) }
        let color: Color = ratio > 0.9 ? .red : ratio > 0.7 ? .orange : theme.secondaryText

        return AnyView(
            Button {
            showTokenStatus = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: hasAccountPool ? "externaldrive" : "tuningfork")
                    .font(.system(size: 10))
                    .foregroundStyle(color)
                Text("남음 \(TokenQuotaStore.thousands(remaining)) 토큰")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(color)
                if !hasAccountPool, snapshot.isOverLimit {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .help("컨텍스트 한도를 초과했습니다. 이전 기록이 잘릴 수 있습니다.")
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: theme.inputCornerRadius).fill(theme.inputBackground))
            .overlay(
                RoundedRectangle(cornerRadius: theme.inputCornerRadius)
                    .strokeBorder(hasAccountPool ? theme.accentColor.opacity(0.55) : theme.inputBorder)
            )
        }
        .buttonStyle(.plain)
        .help(tokenStatusHelp(snapshot: snapshot, quota: quota))
        )
    }

    private func tokenStatusHelp(snapshot: ModelTokenSnapshot, quota: ProviderAccountQuota?) -> String {
        if let quota {
            return "공급자 계정 남은 토큰 \(SessionTokens.compact(quota.remaining)) / \(SessionTokens.compact(quota.limit)) — 클릭해 상세 확인"
        }
        let label = snapshot.source == .measured ? "실측" : "추정"
        return "현재 대화 \(label) \(SessionTokens.compact(snapshot.used)) / 한도 \(SessionTokens.compact(snapshot.limit)) — 클릭해 상세 확인"
    }

    private var tokenStatusPopover: some View {
        let snapshot = self.snapshot()
        let quota = TokenQuotaStore.shared.accountQuotas[viewModel.selectedModel.provider]

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.selectedModel.provider.accentSwiftUIColor)
                    .frame(width: 8, height: 8)
                Text(viewModel.selectedModel.displayName)
                    .font(.callout.bold())
                    .lineLimit(1)
                Text(viewModel.selectedModel.provider.rawValue)
                    .font(.caption)
                    .foregroundStyle(theme.tertiaryText)
                    .lineLimit(1)
            }
            Divider().opacity(0.4)

            // 공급자 계정 풀 (Anthropic 헤더 실측)
            if let quota {
                VStack(alignment: .leading, spacing: 6) {
                    Text("공급자 계정 (분당 할당)")
                        .font(.caption.bold())
                        .foregroundStyle(theme.secondaryText)
                    quotaRow(label: "남음", value: quota.remaining, limit: quota.limit, emphasized: true)
                    quotaRow(label: "사용", value: quota.used, limit: quota.limit, emphasized: false)
                    tokenBar(ratio: quota.ratio, danger: quota.ratio > 0.9)
                    Text("갱신: \(quota.updatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(theme.tertiaryText)
                }
                Divider().opacity(0.4)
            }

            // 모델 컨텍스트 풀
            VStack(alignment: .leading, spacing: 6) {
                Text("모델 컨텍스트")
                    .font(.caption.bold())
                    .foregroundStyle(theme.secondaryText)
                quotaRow(label: "한도", value: snapshot.limit, limit: snapshot.limit, emphasized: false)
                if snapshot.source == .measured {
                    HStack(spacing: 8) {
                        Label("↑ \(SessionTokens.compact(snapshot.measuredPrompt))", systemImage: "arrow.up")
                        Label("↓ \(SessionTokens.compact(snapshot.measuredCompletion))", systemImage: "arrow.down")
                    }
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(theme.secondaryText)
                    quotaRow(label: "사용(실측)", value: snapshot.used, limit: snapshot.limit, emphasized: true)
                } else {
                    quotaRow(label: "사용(추정)", value: snapshot.used, limit: snapshot.limit, emphasized: true)
                }
                tokenBar(ratio: snapshot.ratio, danger: snapshot.isOverLimit)
                if snapshot.remaining > 0 {
                    Text("남음 \(TokenQuotaStore.thousands(snapshot.remaining)) 토큰")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(snapshot.ratio > 0.9 ? .red : theme.secondaryText)
                }
                if snapshot.source == .estimated {
                    Text("이 모델로 받은 응답이 아직 없어 추정치입니다. 대화 후 실측으로 전환됩니다.")
                        .font(.caption2)
                        .foregroundStyle(theme.tertiaryText)
                }
            }
        }
        .padding(12)
        .frame(width: 280, alignment: .leading)
    }

    private func quotaRow(label: String, value: Int, limit: Int, emphasized: Bool) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(theme.secondaryText)
            Spacer()
            Text("\(SessionTokens.compact(value)) / \(SessionTokens.compact(max(value, limit)))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(emphasized ? (Double(value) / Double(max(value, limit)) > 0.9 ? Color.red : theme.accentColor) : theme.secondaryText)
        }
    }

    private func tokenBar(ratio: Double, danger: Bool) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(danger ? Color.red : theme.accentColor)
                    .frame(width: max(2, geo.size.width * CGFloat(min(max(ratio, 0), 1))))
            }
        }
        .frame(height: 5)
    }
}

/// 워크스페이스 파일 트리 노드 (T-329) — 코딩 모드 파일 목록 패널
private struct WorkspaceFileNode: Identifiable {
    let path: String
    let name: String
    let isDirectory: Bool
    let children: [WorkspaceFileNode]

    var id: String { path }
}

/// 파일 트리 행 (T-329) — 디렉터리는 재귀 DisclosureGroup, 파일은 컨텍스트 메뉴 제공
private struct WorkspaceFileRow: View {
    let node: WorkspaceFileNode
    @Binding var expandedPaths: Set<String>
    let onCopyPath: (String) -> Void
    let onInsertPath: (String) -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(isExpanded: Binding(
                get: { expandedPaths.contains(node.path) },
                set: { isExpanded in
                    if isExpanded { expandedPaths.insert(node.path) }
                    else { expandedPaths.remove(node.path) }
                }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(node.children) { child in
                        WorkspaceFileRow(
                            node: child,
                            expandedPaths: $expandedPaths,
                            onCopyPath: onCopyPath,
                            onInsertPath: onInsertPath
                        )
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.caption)
                        .foregroundStyle(theme.accentColor)
                    Text(node.name)
                        .font(.caption)
                        .foregroundStyle(theme.primaryText)
                }
            }
            .font(.caption)
        } else {
            HStack(spacing: 4) {
                Image(systemName: "doc")
                    .font(.caption2)
                    .foregroundStyle(theme.secondaryText)
                Text(node.name)
                    .font(.caption)
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                Spacer()
            }
            .contentShape(Rectangle())
            .contextMenu {
                Button("경로 복사") { onCopyPath(node.path) }
                Button("채팅 입력창에 경로 붙여넣기") { onInsertPath(node.path) }
            }
        }
    }
}

/// 모델 선택 팝오버의 섹션 (T-329) — 추천/전체 그룹 · Menu 대체로 IME 교착 근본 회피
private struct ModelSection: Identifiable {
    let id = UUID()
    let header: String?
    let models: [AIModel]
}
