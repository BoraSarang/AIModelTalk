import SwiftUI

/// 전역 메시지 검색 — ⌘F / 사이드바 검색 버튼 (v1.9 T-77, 고도화 v2.1 T-97)
struct GlobalSearchView: View {
    @ObservedObject private var viewModel = ChatViewModel.shared
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [SearchIndexService.SearchHit] = []
    @State private var searchDebounce: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            if results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 34))
                        .foregroundStyle(.quaternary)
                    Text(emptyHint)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(results) { hit in
                    resultRow(hit)
                }
                .listStyle(.plain)

                Divider()
                Text("\(results.count)건")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
        .frame(minWidth: 540, minHeight: 480)
        .onChange(of: query) { _, newValue in
            // 입력 즉시 검색(250ms 디바운스) — 엔터 없이도 결과 갱신 (v2.1 피드백)
            searchDebounce?.cancel()
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2 else {
                results = []
                return
            }
            searchDebounce = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                results = SearchIndexService.shared.search(trimmed)
            }
        }
    }

    private var emptyHint: String {
        if query.trimmingCharacters(in: .whitespaces).count < 2 {
            return "두 글자 이상 입력해 주세요"
        }
        return "검색 결과가 없습니다"
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("모든 대화의 메시지 검색…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .onSubmit { runSearch() }
            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .onAppear {
            runSearch()
        }
    }

    private func runSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            return
        }
        results = SearchIndexService.shared.search(trimmed)
        DebugLogger.shared.info("SEARCH", "[FEATURE] 전역 검색 실행됨: '\(trimmed.prefix(40))' → \(results.count)건")
    }

    /// 결과 행 — 클릭 시 해당 세션/메시지로 이동 (v2.1 T-97 점프 연결)
    private func resultRow(_ hit: SearchIndexService.SearchHit) -> some View {
        let sessionTitle = viewModel.sessions.first { $0.id == hit.sessionID }?.title ?? "(삭제된 세션)"
        let isUser = hit.role == "user"
        let isTitleMatch = hit.role == "title"

        return Button {
            viewModel.jumpToSearchHit(hit)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: rowIcon(hit))
                        .font(.caption2)
                        .foregroundStyle(isTitleMatch ? Color.accentColor : (isUser ? Color.orange : Color.blue))
                    Text(sessionTitle)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if isTitleMatch {
                        dsBadge("제목 일치", color: .accentColor, textColor: Color.accentColor, fontSize: 9)
                    }
                    Spacer()
                    if let date = hit.updatedAt {
                        Text(date, style: .date)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(isTitleMatch ? "세션 제목이 검색어와 일치합니다" : hit.snippet)
                    .font(.callout)
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(2)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isTitleMatch ? "이 세션으로 이동" : "해당 메시지로 이동")
    }

    /// 행 아이콘 — 제목 매칭은 폴더, 사용자/어시스턴트 구분
    private func rowIcon(_ hit: SearchIndexService.SearchHit) -> String {
        if hit.role == "title" { return "folder.fill" }
        return isUserRow(hit) ? "person.fill" : "bubble.left.fill"
    }

    private func isUserRow(_ hit: SearchIndexService.SearchHit) -> Bool {
        hit.role == "user"
    }
}
