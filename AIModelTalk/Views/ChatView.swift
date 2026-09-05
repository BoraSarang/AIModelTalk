import SwiftUI

// MARK: - 대화 화면 (메시지 리스트·입력바는 개별 뷰로 분리)

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel

    @ObservedObject private var updateService = UpdateCheckService.shared
    @State private var isAlwaysOnTop = false
    @State private var showRenameSheet = false
    @State private var renameText = ""
    @State private var showQuestionOutline = false
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            if updateService.hasUpdate, let release = updateService.latestRelease {
                updateBanner(release)
            }
            // 병렬 모델 비교 오버레이 (T-201) — 비교 실행 중 메시지 리스트 위에 그리드 표시
            if viewModel.isComparing {
                CompareOverlayView(viewModel: viewModel)
            }
            MessageListView(viewModel: viewModel)
            Divider()
            ChatInputBarView(viewModel: viewModel)
        }
        .background(theme.primaryBackground)
        .navigationTitle(viewModel.currentSession?.title ?? "대화")
        // MCP 도구 권한 확인 (v2.4 T-120)
        .confirmationDialog(
            "도구 실행 허용",
            isPresented: Binding(
                get: { viewModel.pendingToolPermission != nil },
                set: { if !$0, viewModel.pendingToolPermission != nil { viewModel.respondToToolPermission(.denyOnce) } }
            ),
            titleVisibility: .visible
        ) {
            Button("이번만 허용") { viewModel.respondToToolPermission(.allowOnce) }
            Button("항상 허용") { viewModel.respondToToolPermission(.alwaysAllow) }
            Button("항상 거부", role: .destructive) { viewModel.respondToToolPermission(.alwaysDeny) }
            Button("취소", role: .cancel) { viewModel.respondToToolPermission(.denyOnce) }
        } message: {
            if let pending = viewModel.pendingToolPermission {
                Text("모델이 '\(pending.toolName)' 도구 실행을 요청했습니다.\n\n\(pending.argumentsPreview)")
                    .font(.system(size: 11, design: .monospaced))
            }
        }
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    // 인코그니토 — 전역 기억 미회수·미생성
                    Button {
                        viewModel.toggleIncognito()
                    } label: {
                        Image(systemName: (viewModel.currentSession?.isIncognito ?? false) ? "eye.slash.fill" : "eye.slash")
                            .foregroundStyle((viewModel.currentSession?.isIncognito ?? false) ? theme.warningColor : theme.secondaryText)
                    }
                    .help("인코그니토 — 이 대화는 전역 기억을 사용/저장하지 않음")
                    Button {
                        renameText = viewModel.currentSession?.title ?? ""
                        showRenameSheet = true
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(.secondary)
                    }
                    .help("대화 이름 수정")

                Button {
                    toggleAlwaysOnTop()
                } label: {
                    Image(systemName: isAlwaysOnTop ? "pin.fill" : "pin")
                        .foregroundStyle(isAlwaysOnTop ? theme.accentColor : theme.secondaryText)
                }
                .help(isAlwaysOnTop ? "항상 위 해제" : "항상 위에 고정")
                Button {
                    showQuestionOutline = true
                } label: {
                    Image(systemName: "list.bullet")
                        .foregroundStyle(theme.secondaryText)
                }
                .help("질문 목차 — 내 질문으로 바로 이동")
                .popover(isPresented: $showQuestionOutline, arrowEdge: .bottom) {
                    QuestionOutlinePopover(viewModel: viewModel) {
                        showQuestionOutline = false
                    }
                }
            }
        }
        .sheet(isPresented: $showRenameSheet) {
            renameSheet
        }
    }

    private var renameSheet: some View {
        VStack(spacing: 16) {
            Text("대화 이름 수정")
                .font(.headline)
            TextField("이름", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
            HStack {
                Spacer()
                Button("취소") { showRenameSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("저장") {
                    if let sessionID = viewModel.currentSession?.id {
                        viewModel.renameSession(sessionID, to: renameText)
                    }
                    showRenameSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }

        private func toggleAlwaysOnTop() {
        isAlwaysOnTop.toggle()
        if let window = NSApp.keyWindow {
            window.level = isAlwaysOnTop ? .floating : .normal
        }
        DebugLogger.shared.info("UI", "항상 위: \(isAlwaysOnTop ? "활성화" : "비활성화")")
    }

    // MARK: - 업데이트 알림 배너

    private func updateBanner(_ release: ReleaseInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(theme.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("새 버전 \(release.version) 사용 가능")
                    .font(.caption.bold())
                Text("현재 \(updateService.currentVersion) · GitHub에서 다운로드")
                    .font(.caption2)
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer()
            Button("업데이트") {
                updateService.openReleasePage()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(theme.accentColor.opacity(0.1))
    }
}

#Preview {
    ChatView(viewModel: ChatViewModel())
        .frame(width: 700, height: 500)
}

// MARK: - 질문 목차 팝오버 (T-338)

/// 세션 내 내 질문 목록 — 탭하면 해당 말풍선으로 점프 (검색 점프와 동일 경로)
struct QuestionOutlinePopover: View {
    @ObservedObject var viewModel: ChatViewModel
    var onDismiss: () -> Void
    @Environment(\.theme) private var theme

    private var questions: [(id: UUID, preview: String)] {
        guard let messages = viewModel.currentSession?.messages else { return [] }
        return messages.filter { $0.role == .user }.map { msg in
            let oneLine = msg.content
                .components(separatedBy: .newlines).first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let preview = oneLine.isEmpty ? "(이미지 첨부)" : String(oneLine.prefix(40))
            return (msg.id, preview)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("질문 목차")
                .font(.caption.bold())
                .foregroundStyle(theme.secondaryText)
            Divider()
            if questions.isEmpty {
                Text("아직 질문이 없습니다")
                    .font(.caption)
                    .foregroundStyle(theme.tertiaryText)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(questions, id: \.id) { item in
                            Button {
                                if let sessionID = viewModel.currentSessionID {
                                    viewModel.jumpToMessage(item.id, in: sessionID)
                                }
                                onDismiss()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "bubble.right")
                                        .font(.caption2)
                                        .foregroundStyle(theme.tertiaryText)
                                    Text(item.preview)
                                        .font(.caption)
                                        .foregroundStyle(theme.primaryText)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .padding(.horizontal, 4)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(width: 280)
                .frame(maxHeight: 300)
            }
        }
        .padding(10)
    }
}
