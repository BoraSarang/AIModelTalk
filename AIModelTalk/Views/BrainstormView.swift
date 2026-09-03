import SwiftUI

/// 브레인스토밍 도구 — 주제 → 아이디어 카드 누적 (v2.0 T-80)
struct BrainstormView: View {
    @ObservedObject private var service = BrainstormService.shared
    @ObservedObject private var viewModel = ChatViewModel.shared
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if service.ideas.isEmpty && !service.isGenerating {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                        ForEach(service.ideas) { idea in
                            IdeaCardView(idea: idea)
                        }
                        if service.isGenerating {
                            generatingCard
                        }
                    }
                    .padding(DS.windowInset)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 520)
        .appAccentTint(settings.accentColor)
    }

    // MARK: - 상단 바

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.max")
                    .font(.title3)
                    .foregroundStyle(.yellow)

                TextField("브레인스토밍 주제 (예: 대학생을 위한 무료 AI 학습 도구)", text: $service.topic)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await service.generateMore(model: currentModel) } }

                Button("생성") {
                    Task { await service.generateMore(model: currentModel) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(service.isGenerating || service.topic.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            HStack(spacing: 10) {
                modelMenu
                Spacer()
                if !service.ideas.isEmpty {
                    Button("초기화", role: .destructive) {
                        service.reset()
                    }
                }
                Button {
                    Task { await service.generateMore(model: currentModel) }
                } label: {
                    Label("다른 관점으로 더", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(service.isGenerating || service.topic.trimmingCharacters(in: .whitespaces).isEmpty || service.ideas.isEmpty)
                if service.isGenerating {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(DS.windowInset)
    }

    /// 모델 선택 — 현재 대화 모델 기본, 공급자별 메뉴 (T-85 엔트리 재사용)
    @ViewBuilder
    private var modelMenu: some View {
        Menu {
            let entries = ProviderEntry.currentList()
            let fallbackID = entries.compactMap(\.endpoint).first?.id
            ForEach(entries) { entry in
                let models = ModelCatalog.freeFirst(ModelCatalog.shared.models.filter {
                    $0.belongs(to: entry, fallbackFirstEndpointID: fallbackID) && ModelCatalog.shared.isEnabled($0)
                })
                if !models.isEmpty {
                    Menu(entry.title) {
                        ForEach(models) { m in
                            Button(m.displayName) {
                                selectedBrainstormModel = m
                            }
                        }
                    }
                }
            }
        } label: {
            Label(currentModel.displayName, systemImage: "cpu")
        }
    }

    @State private var selectedBrainstormModel: AIModel?

    private var currentModel: AIModel {
        selectedBrainstormModel ?? viewModel.selectedModel
    }

    // MARK: - 빈 화면 / 생성 중

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "lightbulb.max")
                .font(.system(size: 44))
                .foregroundStyle(.quaternary)
            Text("주제를 입력하고 생성을 누르세요")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("아이디어가 카드로 누적되며, '다른 관점으로 더'로 방향을 바꿔 계속 확장할 수 있습니다.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var generatingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("생성 중…", systemImage: "sparkles")
                .font(.headline)
            if !service.streamingText.isEmpty {
                Text(service.streamingText.suffix(400))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(12)
            } else {
                TypingIndicatorView().padding(.vertical, 6)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: DS.radiusCard).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusCard).strokeBorder(Color.accentColor.opacity(0.4)))
    }
}

// MARK: - 아이디어 카드

private struct IdeaCardView: View {
    let idea: BrainstormIdea
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let angle = idea.angle {
                    Text(angle)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(idea.text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help(copied ? "복사됨" : "복사")
            }
            Text(idea.text)
                .font(.callout)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: DS.radiusCard).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusCard).strokeBorder(Color.secondary.opacity(0.15)))
    }
}
