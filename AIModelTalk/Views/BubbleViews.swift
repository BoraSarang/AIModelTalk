import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

// MARK: - 말풍선 뷰 (카카오톡 스타일 + macOS 소재)

struct MessageBubbleView: View {
    let message: ChatMessage
    var isStreaming: Bool = false
    /// 좌우 여백 — 기본 16(메인), 패널은 축소값 사용 (T-46)
    var sidePadding: CGFloat = 16
    /// 이 지점부터 분기 액션 — 웹뷰가 우클릭을 막으므로 푸터 버튼으로 제공 (v2.1 T-73 보강)
    var onFork: (() -> Void)? = nil
    /// 후속질문 클릭 즉시 전송 (T-337)
    var onSendFollowUp: ((String) -> Void)? = nil

    var body: some View {
        if message.role == .user {
            UserBubbleView(message: message, sidePadding: sidePadding, onFork: onFork)
        } else {
            AssistantBubbleView(message: message, isStreaming: isStreaming, sidePadding: sidePadding, onFork: onFork, onSendFollowUp: onSendFollowUp)
        }
    }
}

// MARK: - 사용자 말풍선 (오른쪽, 퍼플 그라디언트)

struct UserBubbleView: View {
    let message: ChatMessage
    var sidePadding: CGFloat = 16
    var onFork: (() -> Void)? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            Spacer(minLength: 60)

            VStack(alignment: .trailing, spacing: 6) {
                // 첨부 이미지 썸네일 (T-71)
                if let attachments = message.attachments, !attachments.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(attachments) { attachment in
                            if let image = NSImage(data: attachment.imageData) {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(maxWidth: 180, maxHeight: 140)
                                    .clipShape(RoundedRectangle(cornerRadius: theme.radiusCard))
                                    .overlay(RoundedRectangle(cornerRadius: theme.radiusCard).strokeBorder(Color.white.opacity(0.35)))
                                    .help(attachment.fileName ?? "첨부 이미지")
                            }
                        }
                    }
                }

                Text(message.content)
                    .textSelection(.enabled)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: theme.radiusBubble)
                            .fill(theme.userBubbleGradient)
                    )
            }

            VStack(alignment: .trailing, spacing: 2) {
                if let onFork {
                    Button(action: onFork) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 11))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("이 지점부터 분기")
                }
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, sidePadding)
    }
}

// MARK: - AI 말풍선 (왼쪽, 소재 + 아바타/배지)

struct AssistantBubbleView: View {
    let message: ChatMessage
    var isStreaming: Bool = false
    var sidePadding: CGFloat = 16
    var onFork: (() -> Void)? = nil
    var onSendFollowUp: ((String) -> Void)? = nil
    @State private var toastMsg = ""
    @State private var showToast = false
    @Environment(\.theme) private var theme

    private var providerColor: Color {
        message.provider?.accentSwiftUIColor ?? theme.secondaryText
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 아바타
            ZStack {
                Circle()
                    .fill(providerColor.opacity(0.18))
                Text(String((message.provider?.rawValue.prefix(1) ?? "A")))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(providerColor)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 4) {
                // 배지: 공급자 · 모델명 (친화명 + raw id)
                HStack(spacing: 4) {
                    if let provider = message.provider, let modelID = message.modelID {
                        Text(ModelCatalog.label(for: provider, modelID: modelID))
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(providerColor)
                    } else {
                        Text(message.provider?.rawValue ?? "AI")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(providerColor)
                    }
                }

                // MCP 실행 카드 (v2.4 T-120) — 본문 위에 표시
                if let runs = message.toolRuns, !runs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(runs) { run in
                            ToolRunCardView(record: run)
                        }
                    }
                }

                // 생성 이미지 표시 (v0.3.x 축4) — 본문 위에 표시, 저장 버튼 제공
                // 합성 오디오 표시 (v0.3.3 T-332) — 오디오 첨부는 재생 행으로 표시
                if let attachments = message.attachments, !attachments.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(attachments) { attachment in
                            if attachment.mimeType.hasPrefix("audio/") {
                                AudioAttachmentRow(attachment: attachment)
                            } else if let image = NSImage(data: attachment.imageData) {
                                HStack(alignment: .top, spacing: 6) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: 320, maxHeight: 320)
                                        .clipShape(RoundedRectangle(cornerRadius: theme.radiusCard))
                                        .overlay(RoundedRectangle(cornerRadius: theme.radiusCard).strokeBorder(theme.cardBorder.opacity(0.4)))
                                    Button {
                                        saveGeneratedImage(attachment)
                                    } label: {
                                        Image(systemName: "square.and.arrow.down")
                                            .font(.system(size: 12))
                                    }
                                    .buttonStyle(.plain)
                                    .help("이미지 저장")
                                }
                            }
                        }
                    }
                }

                // 본문
                if message.isStreaming && message.content.isEmpty {
                    TypingIndicatorView()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: theme.radiusBubble).fill(theme.cardBackground))
                } else {
                    Group {
                        MarkdownRenderer(text: message.content, isStreaming: message.isStreaming)
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: theme.radiusBubble).fill(theme.cardBackground))
                    .overlay(alignment: .topLeading) {
                        if message.isError {
                            RoundedRectangle(cornerRadius: theme.radiusBubble)
                                .strokeBorder(theme.errorColor.opacity(0.5), lineWidth: 1)
                        }
                    }
                }

                HStack(spacing: 6) {
                    if isStreaming && !message.content.isEmpty {
                        Text("응답 중…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    // 토큰 실측 배지 — API가 보고한 usage (v1.9 T-76)
                    if (message.promptTokens ?? 0) + (message.completionTokens ?? 0) > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up")
                            Text(SessionTokens.compact(message.promptTokens ?? 0))
                            Image(systemName: "arrow.down")
                            Text(SessionTokens.compact(message.completionTokens ?? 0))
                        }
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .help("API 실측 토큰 (프롬프트/완료)")
                    }

                    if !isStreaming && !message.content.isEmpty {
                        HStack(spacing: 6) {
                            if let onFork {
                                Button(action: onFork) {
                                    Image(systemName: "arrow.triangle.branch")
                                        .font(.system(size: 11))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("이 지점부터 분기")
                            }

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(message.content, forType: .string)
                                toastMsg = "클립보드로 복사되었습니다"
                                withAnimation { showToast = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    withAnimation { showToast = false }
                                }
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("마크다운 복사")

                            Button {
                                let panel = NSSavePanel()
                                panel.title = "마크다운 파일 저장"
                                panel.canCreateDirectories = true
                                panel.nameFieldStringValue = ""
                                panel.allowedContentTypes = [.data]
                                if panel.runModal() == .OK, let url = panel.url {
                                    let saveURL = url.pathExtension == "md" ? url : url.deletingPathExtension().appendingPathExtension("md")
                                    try? message.content.write(to: saveURL, atomically: true, encoding: .utf8)
                                }
                            } label: {
                                Image(systemName: "arrow.down.doc")
                                    .font(.system(size: 11))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("마크다운 다운로드")
                        }
                        .padding(.horizontal, 2)
                        .padding(.vertical, 4)
                        .foregroundStyle(.secondary)
                        .opacity(0.8)
                    }

                    followUpSection
                }
            }

            Spacer(minLength: 60)
        }
        .padding(.horizontal, sidePadding)
        .overlay(alignment: .bottom) {
            if showToast {
                Text(toastMsg)
                    .font(.caption)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: theme.shadowColor.opacity(0.1), radius: 4, y: 2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 4)
            }
        }
    }

    /// 후속질문 섹션 (T-337) — 행 클릭 즉시 전송
    /// 응답 하단 우측 블록 (T-337b) — 좌측 Spacer로 인덴트, 화살표는 블록 우변에 소속
    @ViewBuilder
    private var followUpSection: some View {
        if !isStreaming, !message.content.isEmpty,
           let items = message.followUps, !items.isEmpty,
           let onSend = onSendFollowUp {
            HStack(spacing: 0) {
                Spacer(minLength: 140)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 5) {
                        Image(systemName: "text.line.first.and.arrowtriangle.forward")
                            .font(.system(size: 11))
                        Text("Follow up")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(theme.secondaryText)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                    ForEach(items, id: \.self) { item in
                        Button {
                            onSend(item)
                        } label: {
                            HStack(spacing: 6) {
                                Text(item)
                                    .font(.system(size: 13))
                                    .foregroundStyle(theme.primaryText)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.tertiaryText)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                        .help("이 질문으로 바로 전송")
                        Divider()
                            .foregroundStyle(theme.secondaryBorder.opacity(0.5))
                    }
                }
            }
        }
    }

    /// 생성 이미지 NSSavePanel 저장 (v0.3.x 축4)
    private func saveGeneratedImage(_ attachment: MessageAttachment) {
        let panel = NSSavePanel()
        panel.title = "이미지 저장"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = attachment.fileName ?? "generated-image.png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? attachment.imageData.write(to: url)
        DebugLogger.shared.info("IMAGE", "[FEATURE] 생성 이미지 저장: \(url.path)")
    }
}

// MARK: - 타이핑 인디케이터 (점 3개)

/// TimelineView 기반 — Task/타이머 없이 SwiftUI가 주기를 관리하므로 뷰 소멸 시 자동 정지
struct TypingIndicatorView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.45)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate / 0.45) % 3
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 6, height: 6)
                        .opacity(phase == i ? 1 : 0.35)
                }
            }
        }
    }
}

#Preview("사용자") {
    MessageBubbleView(message: ChatMessage(role: .user, content: "안녕하세요, 테스트 메시지입니다."))
        .frame(width: 500)
        .padding()
}

#Preview("AI") {
    MessageBubbleView(message: ChatMessage(role: .assistant, content: "안녕하세요! **무엇을** 도와드릴까요?", provider: .nvidia, modelID: "openai/gpt-oss-20b"))
        .frame(width: 500)
        .padding()
}
/// MCP 도구 실행 카드 (v2.4 T-120) — 도구명·상태·결과 미리보기·소요시간
struct ToolRunCardView: View {
    let record: ToolLoopService.ExecutionRecord
    @State private var expanded = false
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: record.isError ? "exclamationmark.triangle.fill" : "wrench.and.screwdriver.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(record.isError ? .orange : .secondary)
                Text(record.toolName)
                    .font(.caption)
                    .fontWeight(.medium)
                if record.permissionDecision == "denied" {
                    Text("거부됨")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Spacer()
                if let ms = record.durationMS {
                    Text("\(Int(ms))ms")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Button {
                    expanded.toggle()
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            if expanded {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    Text("인자:\n\(ChatViewModel.prettyArguments(record.argumentsJSON))\n\n결과:\n\(record.resultPreview ?? "(없음)")")
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 160)
            } else if let preview = record.resultPreview {
                Text(preview.replacingOccurrences(of: "\n", with: " "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: theme.radiusCard).fill(theme.cardBackground.opacity(0.6)))
    }
}

// MARK: - 합성 오디오 재생 행 (v0.3.3 T-332)

/// TTS 합성 오디오 첨부 재생 — 메모리 내 Data를 AVAudioPlayer로 재생/정지
struct AudioAttachmentRow: View {
    let attachment: MessageAttachment
    @StateObject private var player = AudioAttachmentPlayer()
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Button {
                player.toggle(data: attachment.imageData)
            } label: {
                Image(systemName: player.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(theme.accentColor)
            }
            .buttonStyle(.plain)
            .help(player.isPlaying ? "정지" : "재생")
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.fileName ?? "합성 음성")
                    .font(.caption)
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                Text("\(attachment.imageData.count / 1024) KB · mp3")
                    .font(.caption2)
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer()
            Image(systemName: "waveform")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 320)
        .background(RoundedRectangle(cornerRadius: theme.radiusCard).fill(theme.cardBackground.opacity(0.6)))
        .onDisappear { player.stop() }
    }
}

/// 오디오 재생 홀더 — delegate를 self로 유지해 약참조 해제 방지 (T-332)
@MainActor
final class AudioAttachmentPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    private var player: AVAudioPlayer?

    func toggle(data: Data) {
        if isPlaying { stop(); return }
        do {
            let p = try AVAudioPlayer(data: data)
            p.delegate = self
            player = p
            p.play()
            isPlaying = true
            DebugLogger.shared.info("AUDIO", "[FEATURE] 합성 음성 재생 시작 — \(data.count) bytes")
        } catch {
            DebugLogger.shared.error("AUDIO", "합성 음성 재생 실패: \(error.localizedDescription)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isPlaying = false }
    }
}
