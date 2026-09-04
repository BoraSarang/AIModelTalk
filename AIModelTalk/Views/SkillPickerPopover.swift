import SwiftUI

// MARK: - 스킬 선택 (커스텀 Popover, 다중)

struct SkillPickerPopover: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.theme) private var theme

    @State private var showSkillPicker = false
    @State private var searchText = ""

    var body: some View {
        Button {
            showSkillPicker.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                if viewModel.selectedSkills.isEmpty {
                    Text("스킬").font(.callout)
                } else if viewModel.selectedSkills.count == 1 {
                    Text(viewModel.selectedSkills[0].name).font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("스킬 (\(viewModel.selectedSkills.count)개)").font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showSkillPicker) {
            pickerContent
        }
        .onChange(of: showSkillPicker) { _, shown in
            if shown { searchText = "" }
        }
        .help("스킬을 시스템 프롬프트에 추가합니다 (다중 선택)")
    }

    private var pickerContent: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            searchField
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredVisibleSkills) { skill in
                        popoverRow(skill)
                    }
                    if viewModel.availableSkills.isEmpty {
                        Text("스킬을 불러오는 중…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 16)
                    } else if filteredVisibleSkills.isEmpty {
                        Text("'\(searchText)'에 일치하는 스킬이 없습니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 16)
                    }
                }
            }
        }
        .frame(width: 300, height: 340)
        .background(theme.cardBackground)
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.clearSkills()
                showSkillPicker = false
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                    Text("스킬 없음")
                        .font(.callout)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            Button {
                Task { await viewModel.refreshSkills() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .help("~/.opencode/skills 디렉토리를 다시 읽습니다")
        }
    }

    /// 이름/설명 부분일치 필터 (v1.7.2 T-64)
    private var filteredVisibleSkills: [SkillInfo] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return viewModel.visibleSkills }
        return viewModel.visibleSkills.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.description.localizedCaseInsensitiveContains(query)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("스킬 검색", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(theme.inputBackground)
        .clipShape(RoundedRectangle(cornerRadius: theme.radiusControl))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func popoverRow(_ skill: SkillInfo) -> some View {
        let isSel = viewModel.selectedSkills.contains(where: { $0.id == skill.id })
        return Button {
            viewModel.toggleSkill(skill)
        } label: {
            HStack(spacing: 8) {
                Text(isSel ? "✓" : "")
                    .font(.callout)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(skill.name)
                            .font(.callout)
                            .foregroundStyle(isSel ? theme.accentColor : theme.primaryText)
                            .fontWeight(isSel ? .semibold : .regular)
                        if skill.source != .opencode {
                            Text(skill.source.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 0.5)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    if !skill.description.isEmpty {
                        Text(skill.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSel ? Color.accentColor.opacity(0.15) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}
