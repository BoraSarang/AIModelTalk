import SwiftUI

/// 전역 메모리 관리 화면 (T-208) — 목록 · 검색 · 핀 · 듀레이션 · 삭제 · 수동 추가
struct MemorySettingsView: View {
    @ObservedObject private var viewModel = ChatViewModel.shared
    @State private var query = ""
    @State private var newMemory = ""

    private var filtered: [MemoryItem] {
        let sorted = viewModel.memoryItems.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.createdAt > $1.createdAt
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return sorted }
        return sorted.filter {
            $0.content.lowercased().contains(q) || $0.tags.contains { $0.lowercased().contains(q) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(spacing: 8) {
                TextField("새 기억 추가", text: $newMemory)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addNew)
                Button("추가", action: addNew)
                    .disabled(newMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("검색", text: $query)
                    .textFieldStyle(.roundedBorder)
                Spacer()
                Text("\(filtered.count) / \(viewModel.memoryItems.count)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Divider()
            if filtered.isEmpty {
                ContentUnavailableView("기억이 없습니다",
                    systemImage: "brain",
                    description: Text("대화 중 중요한 정보를 자동으로 기억하거나, 위에서 직접 추가할 수 있습니다."))
            } else {
                List(filtered) { item in
                    MemoryRowView(item: item, viewModel: viewModel)
                }
                .listStyle(.inset)
            }
        }
        .padding(16)
        .navigationTitle("메모리")
        .onAppear { viewModel.loadMemory() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("전역 메모리").font(.headline)
                Text("모든 대화의 시스템 프롬프트에 주입되어 연속성을 만듭니다. 핀은 퇴출을 보호하고, 임시는 정리 우선 대상입니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func addNew() {
        let text = newMemory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        viewModel.addMemory(text)
        newMemory = ""
    }
}

/// 메모리 단일 행 — 핀/듀레이션 토글 + 삭제
private struct MemoryRowView: View {
    let item: MemoryItem
    let viewModel: ChatViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.content)
                    .font(.body)
                HStack(spacing: 10) {
                    Label(item.createdAt.formatted(date: .abbreviated, time: .shortened),
                          systemImage: "calendar").font(.caption2).foregroundStyle(.secondary)
                    if item.isAuto {
                        Text("자동").font(.caption2).foregroundStyle(.secondary)
                    }
                    if !item.tags.isEmpty {
                        Text(item.tags.joined(separator: ", ")).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Button {
                viewModel.toggleMemoryPin(memoryID: item.id)
            } label: {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(item.isPinned ? .orange : .secondary)
            }
            .help(item.isPinned ? "고정 해제 (퇴출 보호)" : "고정 (퇴출 보호)")
            .buttonStyle(.plain)

            Menu {
                Button(item.durability == .permanent ? "영구 (자동 정리 제외)" : "영구로 전환") {
                    viewModel.setMemoryDurability(memoryID: item.id, to: .permanent)
                }
                Button(item.durability == .temporary ? "임시 (정리 우선)" : "임시로 전환") {
                    viewModel.setMemoryDurability(memoryID: item.id, to: .temporary)
                }
            } label: {
                Image(systemName: item.durability == .permanent ? "infinity" : "clock")
                    .foregroundStyle(item.durability == .permanent ? .teal : .secondary)
            }
            .help(item.durability == .permanent ? "영구 기억" : "임시 기억")
            .buttonStyle(.plain)

            Button(role: .destructive) {
                viewModel.deleteMemory(memoryID: item.id)
            } label: {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
            .help("삭제")
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    MemorySettingsView()
}