import SwiftUI

// MARK: - 사전 프롬프트 (전역 시스템 프롬프트 편집)

struct SystemPromptPopover: View {
    @ObservedObject private var settings = AppSettings.shared

    @State private var showPromptEditor = false

    var body: some View {
        Button {
            showPromptEditor.toggle()
        } label: {
            Image(systemName: "text.badge.plus")
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPromptEditor) {
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
        .help("사전 프롬프트(시스템 프롬프트) 편집")
    }
}
