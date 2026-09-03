import SwiftUI

/// 프롬프트 템플릿 팝오버 (T-208) — 저장한 지시문 삽입 · 관리 · 변수 치환
struct PromptTemplatePopoverView: View {
    @ObservedObject var viewModel: ChatViewModel
    var onClose: () -> Void

    @State private var showNewForm = false
    @State private var editingName = ""
    @State private var editingContent = ""
    @State private var pendingTemplate: PromptTemplate?
    @State private var variableValues: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("프롬프트 템플릿").font(.headline)
                Spacer()
                Button {
                    withAnimation { showNewForm.toggle() }
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("새 템플릿")
            }
            .padding(.bottom, 2)

            if showNewForm {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("이름", text: $editingName)
                        .textFieldStyle(.roundedBorder)
                    TextEditor(text: $editingContent)
                        .font(.system(size: 12))
                        .frame(height: 90)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                    Text("{변수} 형태로 자리표시자를 넣으면 삽입 시 입력받아 치환합니다.")
                        .font(.caption2).foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Button("취소") {
                            showNewForm = false
                            editingName = ""
                            editingContent = ""
                        }
                        Button("저장") {
                            saveNew()
                        }
                        .disabled(editingName.trimmingCharacters(in: .whitespaces).isEmpty
                                  || editingContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Divider()
            }

            if pendingTemplate != nil {
                variableForm
                Divider()
            }

            if viewModel.promptTemplates.isEmpty {
                Text("저장된 템플릿이 없습니다. + 를 눌러 자주 쓰는 지시를 저장해 보세요.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(viewModel.promptTemplates) { template in
                            templateRow(template)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(14)
        .frame(width: 340)
        .onDisappear { onClose() }
    }

    private var variableForm: some View {
        guard let template = pendingTemplate else { return AnyView(EmptyView()) }
        let vars = template.variableNames()
        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                Text("변수 입력").font(.subheadline)
                ForEach(vars, id: \.self) { name in
                    HStack {
                        Text(name).font(.caption2).foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .trailing)
                        TextField(name, text: Binding(
                            get: { variableValues[name] ?? "" },
                            set: { variableValues[name] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                }
                HStack {
                    Spacer()
                    Button("취소") { pendingTemplate = nil; variableValues = [:] }
                    Button("삽입") {
                        viewModel.applyTemplate(template, values: variableValues)
                        pendingTemplate = nil
                        variableValues = [:]
                        onClose()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        )
    }

    private func templateRow(_ template: PromptTemplate) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name).font(.caption).fontWeight(.medium)
                Text(template.content.replacingOccurrences(of: "\n", with: " "))
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                let vars = template.variableNames()
                if vars.isEmpty {
                    viewModel.applyTemplate(template, values: [:])
                    onClose()
                } else {
                    variableValues = Dictionary(uniqueKeysWithValues: vars.map { ($0, "") })
                    pendingTemplate = template
                }
            } label: {
                Image(systemName: "arrow.left.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("삽입")
            Button(role: .destructive) {
                viewModel.deleteTemplate(id: template.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("삭제")
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
    }

    private func saveNew() {
        let name = editingName.trimmingCharacters(in: .whitespaces)
        let content = editingContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !content.isEmpty else { return }
        viewModel.saveTemplate(PromptTemplate(name: name, content: content))
        editingName = ""
        editingContent = ""
        showNewForm = false
    }
}