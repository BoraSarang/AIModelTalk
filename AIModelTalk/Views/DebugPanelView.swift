import SwiftUI

/// 디버그 패널 — Cmd+Shift+D로 토글
struct DebugPanelView: View {
    @ObservedObject private var logger = DebugLogger.shared
    @State private var selectedIDs: Set<UUID> = []
    @State private var filterLevel: LogLevel? = nil
    @State private var searchText: String = ""

    var filteredEntries: [LogEntry] {
        logger.entries.filter { entry in
            if let filter = filterLevel, entry.level != filter { return false }
            if !searchText.isEmpty, !entry.display.localizedCaseInsensitiveContains(searchText) { return false }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── 툴바 ──────────────────────────────────
            HStack(spacing: 12) {
                Text("Debug Log")
                    .font(.headline)

                Spacer()

                // 레벨 필터
                Picker("레벨", selection: $filterLevel) {
                    Text("All").tag(nil as LogLevel?)
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(level as LogLevel?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)

                // 검색
                TextField("검색...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)

                Spacer()

                // 액션 버튼 그룹 — 오른쪽 끝 고정
                HStack(spacing: 8) {
                    Button(action: copyAll) {
                        Label("전체 복사", systemImage: "doc.on.doc")
                    }
                    .help("전체 로그 클립보드에 복사 (⌘⇧C)")

                    Button(action: copySelected) {
                        Label("선택 복사", systemImage: "doc.on.clipboard")
                    }
                    .help("선택한 로그 복사")
                    .disabled(selectedIDs.isEmpty)

                    Divider()
                        .frame(height: 16)

                    Button(action: { logger.clear(); selectedIDs.removeAll() }) {
                        Label("지우기", systemImage: "trash")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // ── 로그 목록 ──────────────────────────────
            ScrollViewReader { proxy in
                List(selection: $selectedIDs) {
                    ForEach(filteredEntries) { entry in
                        LogEntryRow(entry: entry)
                            .tag(entry.id)
                            .id(entry.id)
                    }
                }
                .onChange(of: logger.entries.count) { _ in
                    guard let lastID = logger.entries.last?.id else { return }
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
            .frame(maxHeight: .infinity)

            Divider()

            // ── 상태 바 ────────────────────────────────
            HStack {
                Text("총 \(logger.entries.count)개 로그")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !selectedIDs.isEmpty {
                    Text("· \(selectedIDs.count)개 선택")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("⌘⇧D: 토글 · 선택: 클릭 · 복수: ⌘클릭/Shift클릭")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 700, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 복사

    private func copyAll() {
        let text = logger.dump()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copySelected() {
        let text = filteredEntries
            .filter { selectedIDs.contains($0.id) }
            .map(\.display)
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - 로그 엔트리 행

private struct LogEntryRow: View {
    let entry: LogEntry

    var levelColor: Color {
        switch entry.level {
        case .debug: return .secondary
        case .info:  return .blue
        case .warn:  return .orange
        case .error: return .red
        case .perf:  return .purple
        case .cache: return .green
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.formattedTime)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 75, alignment: .leading)

            Text(entry.level.rawValue)
                .font(.system(.caption, design: .monospaced).bold())
                .foregroundStyle(levelColor)
                .frame(width: 50, alignment: .leading)

            Text("[\(entry.tag)]")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 100, alignment: .leading)

            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(nil)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}
