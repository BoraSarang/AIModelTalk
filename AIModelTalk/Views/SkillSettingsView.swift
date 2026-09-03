import SwiftUI

/// 스킬 관리 — 표시 여부 + 기본 스킬 설정 (v1.7 T-55~56)
struct SkillSettingsView: View {
    @ObservedObject private var viewModel = ChatViewModel.shared
    @State private var isRefreshing = false
    @State private var searchText = ""

    var body: some View {

                VStack(spacing: DS.space4) {
                    // ── 상단 카드 (고정) ──
                    VStack(spacing: DS.space4) {
                        // 검색 필드
                        HStack {
                            SettingsSearchField(placeholder: "스킬 이름 또는 설명 검색", text: $searchText)
                        }
                        
                        // 설명 + 카운트/버튼
                        if viewModel.availableSkills.isEmpty {
                            Text("사용 가능한 스킬이 없습니다")
                            Text("~/.opencode/skills 디렉토리에 SKILL.md를 추가하거나 새로고침하세요.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("표시된 스킬만 피커에 나타나며, 기본 스킬은 새 대화에 자동 적용됩니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            HStack {
                                Group {
                                    if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                                        Text("총 \(viewModel.availableSkills.count)개 · 표시 \(viewModel.visibleSkills.count)개")
                                    } else {
                                        Text("\(searchedSkills.count)개 검색됨")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                Spacer()
                                Button("모두 표시") {
                                    viewModel.setAllSkillsHidden(false)
                                }
                                .disabled(viewModel.availableSkills.isEmpty || viewModel.hiddenSkillIDs.isEmpty)
                                Button("모두 숨김") {
                                    viewModel.setAllSkillsHidden(true)
                                }
                                .disabled(viewModel.availableSkills.isEmpty || viewModel.visibleSkills.isEmpty)
                                Button {
                                    Task {
                                        isRefreshing = true
                                        await viewModel.refreshSkills()
                                        isRefreshing = false
                                    }
                                } label: {
                                    if isRefreshing {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Label("새로고침", systemImage: "arrow.clockwise")
                                    }
                                }
                                .disabled(isRefreshing)
                            }
                        }
                    }
                    .padding(DS.cardInset)
                    .dsCard()
                    
                    Spacer(minLength: DS.cardInset)
                    
                    // ── 하단 카드 (스크롤) ──
                    ScrollView {
                        VStack(spacing: 0) {
                            if viewModel.availableSkills.isEmpty {
                                EmptyStateView()
                            } else if searchedSkills.isEmpty {
                                Text("'\(searchText)'에 일치하는 스킬이 없습니다")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                            } else {
                                ForEach(searchedSkills) { skill in
                                    SkillSettingRow(skill: skill)
                                }
                            }
                        }
                        .padding(DS.cardInset)
                    }
                    .frame(maxHeight: .infinity)
                    .dsCard()
                    
                    Spacer(minLength: DS.cardInset)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 100)
        
        

        
    }

    /// 스킬 이름/설명 검색 필터 — 대소문자 무시 (v1.7.2 T-64)
    private var searchedSkills: [SkillInfo] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return viewModel.availableSkills }
        return viewModel.availableSkills.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.description.localizedCaseInsensitiveContains(query)
        }
    }
}

// MARK: - 빈 상태

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("사용 가능한 스킬이 없습니다")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("~/.opencode/skills 디렉토리에 SKILL.md를 추가하거나 새로고침하세요.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - 스킬 행

private struct SkillSettingRow: View {
    let skill: SkillInfo
    @ObservedObject private var viewModel = ChatViewModel.shared

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.isDefaultSkill(skill) ? "star.fill" : "star")
                        .font(.caption)
                        .foregroundStyle(viewModel.isDefaultSkill(skill) ? Color.yellow : Color.secondary)
                    Text(skill.name)
                    if skill.source != .opencode {
                        Text(skill.source.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    if viewModel.isSkillHidden(skill) {
                        Text("숨김")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
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
            Toggle("기본", isOn: Binding(
                get: { viewModel.isDefaultSkill(skill) },
                set: { viewModel.setDefaultSkill(skill, $0) }
            ))
            .toggleStyle(.checkbox)
            .disabled(viewModel.isSkillHidden(skill))
            .help(viewModel.isSkillHidden(skill)
                  ? "사용 해제된 스킬은 기본으로 설정할 수 없습니다"
                  : "새 대화에 이 스킬을 자동으로 적용합니다")
            Toggle("", isOn: Binding(
                get: { !viewModel.isSkillHidden(skill) },
                set: { viewModel.setSkillHidden(skill, !$0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .help("스킬 피커에 표시할지 설정합니다")
        }
        .padding(.vertical, 2)
    }
}
