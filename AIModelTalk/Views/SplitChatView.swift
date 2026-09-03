import SwiftUI

/// Split Chat — 다중 모델 병렬 대화 (v3.0 T-126~127)
/// HSplitView 분기 패널 + 공유/개별 입력 + 정식 세션 저장
struct SplitChatView: View {
    @ObservedObject private var manager = SplitChatManager.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            topControlBar
            Divider()
            if manager.slots.isEmpty {
                emptyState
            } else {
                slotSplitView
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .appAccentTint(settings.accentColor)
        .onAppear {
            if manager.slots.isEmpty {
                manager.addSlot()
            }
        }
    }

    // MARK: - 상단 제어 바

    private var topControlBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label("스플릿 채팅", systemImage: "rectangle.split.2x1")
                    .font(.headline)

                Spacer()

                // 공유/개별 입력 모드 토글
                Toggle(isOn: $manager.isSharedInput) {
                    Text("공유 모드")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("켜면 모든 분기에 같은 질문 전송")

                Button {
                    manager.addSlot()
                } label: {
                    Label("분기 추가", systemImage: "plus")
                }
                .help("새 모델 분기 추가")
            }

            // 입력 영역
            HStack(spacing: 10) {
                TextField(
                    manager.isSharedInput ? "모든 분기에 같은 질문을 보냅니다" : "분기별로 질문을 입력하세요",
                    text: inputBinding
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit { submitShared() }

                Button(submitLabel) {
                    submitShared()
                }
                .disabled(submitDisabled)

                if manager.slots.contains(where: { $0.isLoading }) {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(12)
    }

    private var inputBinding: Binding<String> {
        Binding(
            get: { manager.isSharedInput ? manager.sharedInput : "" },
            set: { if manager.isSharedInput { manager.sharedInput = $0 } }
        )
    }

    private var submitLabel: String {
        manager.isSharedInput ? "모든 분기에 전송" : "전송"
    }

    private var submitDisabled: Bool {
        let text = manager.isSharedInput ? manager.sharedInput : ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitShared() {
        if manager.isSharedInput {
            manager.sendToAll(text: manager.sharedInput)
            manager.sharedInput = ""
        }
    }

    // MARK: - 분기 패널

    private var slotSplitView: some View {
        HSplitView {
            ForEach(manager.slots.indices, id: \.self) { index in
                SplitSlotPanelView(manager: manager, slotIndex: index)
                    .frame(minWidth: 300, minHeight: 400)
            }
        }
    }

    // MARK: - 빈 상태

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
            Text("여러 모델에 같은 질문을 보내 답변을 비교하세요")
                .foregroundStyle(.secondary)
            Button("첫 분기 추가") {
                manager.addSlot()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 개별 분기 패널

private struct SplitSlotPanelView: View {
    @ObservedObject var manager: SplitChatManager
    let slotIndex: Int

    private var slot: SplitSlot { manager.slots[slotIndex] }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messageArea
            Divider()
            if !manager.isSharedInput {
                perSlotInput
            }
        }
        .background(Color.primary.opacity(0.03))
    }

    // MARK: 분기 헤더

    private var header: some View {
        HStack(spacing: 8) {
            dsDot(Color(slot.model.provider.accentColor))

            modelPicker

            Spacer()

            if slot.promptTokens + slot.completionTokens > 0 {
                Text("\(SessionTokens.compact(slot.promptTokens))/\(SessionTokens.compact(slot.completionTokens))")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .help("실측 토큰 프롬프트/완료")
            }

            if slot.isLoading {
                Button {
                    manager.stopSlot(at: slotIndex)
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.borderless)
                .help("이 분기 응답 중지")
            }

            Button {
                manager.removeSlot(at: slotIndex)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .disabled(slot.isLoading)
            .help("분기 제거")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var modelPicker: some View {
        let entries = ProviderEntry.currentList()
        let fallbackID = entries.compactMap(\.endpoint).first?.id

        return Menu {
            ForEach(entries) { entry in
                let models = ModelCatalog.freeFirst(ModelCatalog.shared.visibleModels(in: entry, fallbackFirstEndpointID: fallbackID))
                if !models.isEmpty {
                    Menu(entry.title) {
                        ForEach(models) { model in
                            Button {
                                manager.setModel(model, at: slotIndex)
                            } label: {
                                if slot.model == model {
                                    Label(model.displayName, systemImage: "checkmark")
                                } else {
                                    Text(model.displayName)
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            Text(slot.model.displayName)
                .font(.callout.weight(.medium))
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: 메시지 영역

    private var messageArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    if slot.messages.isEmpty {
                        Text("이 분기에 질문을 보내세요")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 32)
                    } else {
                        ForEach(slot.messages) { message in
                            MessageBubbleView(
                                message: message,
                                isStreaming: slot.streamingMessageID == message.id,
                                sidePadding: 8
                            )
                        }
                        Spacer().frame(height: 1).id("slotBottom")
                    }
                }
                .padding(.vertical, 8)
            }
            .onAppear {
                proxy.scrollTo("slotBottom", anchor: .bottom)
            }
            .onChange(of: slot.messages.last?.content.count) { _ in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo("slotBottom", anchor: .bottom)
                }
            }
            .onChange(of: slot.messages.count) { _ in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo("slotBottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: 개별 입력

    private var perSlotInput: some View {
        HStack(spacing: 8) {
            TextField("이 분기에 질문", text: perSlotInputBinding)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submitPerSlot() }
            Button("전송") {
                submitPerSlot()
            }
            .disabled(slot.isLoading)
        }
        .padding(8)
    }

    private var perSlotInputBinding: Binding<String> {
        Binding(
            get: { perSlotInputText },
            set: { perSlotInputText = $0 }
        )
    }

    @State private var perSlotInputText: String = ""

    private func submitPerSlot() {
        let text = perSlotInputText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        manager.sendToSlot(text, at: slotIndex)
        perSlotInputText = ""
    }
}
