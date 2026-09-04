import SwiftUI
import AppKit

/// 메인 사이드바 — 통합 대화 내역 + 보관함 + 휴지통, 단일 세션 목록 드래그 재배치 (v0.1.2)
/// R2 리팩토링으로 ContentView에서 추출. 로직 무변경, 상태는 바인딩으로 주입.
struct SidebarView: View {
    @ObservedObject var viewModel: ChatViewModel

    @Binding var showGlobalSearch: Bool
    @Binding var showRenameSheet: Bool
    @Binding var renamingSession: ChatSession?
    @Binding var renameText: String
    @Environment(\.theme) private var theme

    /// 드롭 호버 중인 타깃 행 + 삽입 위치(위/아래) — 인디케이터 렌더링용 (v2.1 T-99)
    @State private var hoverDropTargetID: UUID?
    @State private var insertAbove = true

    /// 보관함/휴지통 섹션 접힘 상태 (v0.1.1) — 기본 펼침으로 명확히 노출
    @State private var archiveExpanded = true
    @State private var trashExpanded = true

    var body: some View {
        List(selection: $viewModel.currentSessionID) {
            // ── 동작 행 (헤더 없음) ──
            Section {
                secondaryRow("새 대화", systemImage: "plus.circle") {
                    viewModel.createNewSession()
                }
                .keyboardShortcut("n", modifiers: .command)

                secondaryRow("메시지 검색", systemImage: "magnifyingglass") {
                    showGlobalSearch = true
                }
                .keyboardShortcut("f", modifiers: .command)
                .help("전역 메시지 검색 (⌘F)")
            }

            // ── 대화 내역: 단일 세션 목록 (프로젝트/페르소나 제거 — v0.1.2) ──
            Section {
                ForEach(orderedVisibleSessions) { session in
                    sessionRow(session)
                }
            } header: {
                Text("대화 내역")
            }

            // ── 보관함: 접이식 섹션 (v0.1.1) ──
            Section {
                if archiveExpanded {
                    ForEach(viewModel.archivedSessions) { session in
                        archivedRow(session)
                    }
                }
            } header: {
                HStack {
                    Image(systemName: "archivebox")
                        .font(.caption)
                    Text("보관함")
                    Spacer()
                    if !viewModel.archivedSessions.isEmpty {
                        Button {
                            archiveExpanded.toggle()
                        } label: {
                            Image(systemName: archiveExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { archiveExpanded.toggle() }
            }

            // ── 휴지통: 접이식 섹션 (v0.1.1) ──
            Section {
                if trashExpanded {
                    ForEach(viewModel.trashSessions) { session in
                        trashRow(session)
                    }
                    if !viewModel.trashSessions.isEmpty {
                        HStack {
                            Spacer()
                            Button("휴지통 비우기", role: .destructive) {
                                viewModel.emptyTrash()
                            }
                            .font(.caption)
                        }
                    }
                }
            } header: {
                HStack {
                    Image(systemName: "trash")
                        .font(.caption)
                    Text("휴지통")
                    Spacer()
                    if !viewModel.trashSessions.isEmpty {
                        Text("\(viewModel.trashSessions.count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { trashExpanded.toggle() }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
    }

    /// 섹션 보조 행 — 목록 데이터가 아닌 동작 트리거.
    /// 세션 행과 동일한 아이콘+텍스트 구조·간격으로 왼쪽 라인을 맞춘다 (v2.1 사이드바 개편 피드백)
    private func secondaryRow(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 대화 내역 목록

    /// 저장된 드래그 순서를 반영한 표시 목록 (v2.1 T-99) — 미등록 세션은 갱신일 순으로 하단 추가
    private var orderedVisibleSessions: [ChatSession] {
        let order = SessionOrderStore.normalizedOrder(SessionOrderStore.readOrder(), sessions: viewModel.visibleSessions)
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return viewModel.visibleSessions.sorted { (rank[$0.id] ?? .max) < (rank[$1.id] ?? .max) }
    }

    // MARK: - 세션 행

    private func sessionRow(_ session: ChatSession) -> some View {
        HStack(spacing: 6) {
            // 분기 세션 인디케이터 (T-73)
            Image(systemName: session.parentSessionID != nil ? "arrow.triangle.branch" : "bubble.left")
                .font(.caption)
                .foregroundStyle(session.parentSessionID != nil ? theme.accentColor : theme.secondaryText)
                .help(session.parentSessionID != nil ? "분기된 대화" : "")
            Text(session.title)
                .lineLimit(1)
        }
        .background(hoverDropTargetID == session.id ? theme.accentColor.opacity(0.08) : Color.clear)
        .tag(session.id)
        // 드래그 프리뷰에 대화명 표시 — UUID만 보이던 문제 수정 (v2.1 피드백)
        // 주의: onTapGesture를 draggable과 병용하면 제스처 충돌로 드래그가 불능 — 클릭은 List 네이티브 선택 사용
        .draggable(session.id.uuidString) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left")
                    .foregroundStyle(.secondary)
                Text(session.title)
                    .lineLimit(1)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: theme.radiusControl))
        }
        // 행 위/아래 절반을 드롭 존으로 — 목록 중간 삽입 지원 (v2.1 T-99).
        // background에 두어 콘텐츠 클릭·우클릭이 그대로 통과한다.
        .background(
            GeometryReader { geo in
                VStack(spacing: 0) {
                    dropZone(for: session, placeBefore: true)
                    dropZone(for: session, placeBefore: false)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        )
        .overlay(alignment: insertAbove ? .top : .bottom) {
            if hoverDropTargetID == session.id {
                Rectangle()
                    .fill(theme.accentColor)
                    .frame(height: 2)
                    .allowsHitTesting(false)
            }
        }
        .contextMenu {
            Button("이름 수정") {
                renamingSession = session
                renameText = session.title
                showRenameSheet = true
            }
            // 대화 분기 — 마지막 메시지 기준 복사 (v2.1 T-73 사이드바 진입점 추가)
            Button("대화 분기") {
                if let lastMessage = session.messages.last {
                    viewModel.forkSession(at: lastMessage.id, from: session.id)
                }
            }
            .disabled(session.messages.isEmpty)
            Divider()
            Button("보관함으로 이동") {
                viewModel.archiveSession(session.id)
            }
            Button("휴지통으로 이동", role: .destructive) {
                viewModel.deleteSession(session.id)
            }
        }
    }

    /// 보관함 세션 행 — 보관 해제 / 휴지통으로 이동
    private func archivedRow(_ session: ChatSession) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "archivebox")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(session.title)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .tag(session.id)
        .contextMenu {
            Button("보관 해제") {
                viewModel.unarchiveSession(session.id)
            }
            Button("이름 수정") {
                renamingSession = session
                renameText = session.title
                showRenameSheet = true
            }
            Divider()
            Button("휴지통으로 이동", role: .destructive) {
                viewModel.deleteSession(session.id)
            }
        }
        .help("보관된 대화 · 우클릭: 보관 해제/이동")
    }

    /// 휴지통 세션 행 — 복원 / 영구 삭제
    private func trashRow(_ session: ChatSession) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "trash")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(session.title)
                .lineLimit(1)
                .strikethrough()
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .tag(session.id)
        .contextMenu {
            Button("복원") {
                viewModel.restoreSession(session.id)
            }
            Divider()
            Button("영구 삭제", role: .destructive) {
                viewModel.purgeSession(session.id)
            }
        }
        .help("휴지통의 대화 · 우클릭: 복원/영구 삭제 · 30일 후 자동 비움")
    }

    // MARK: - 세션 드래그 재배치 (v2.1 T-99)

    /// 행 절반 영역의 투명 드롭 존 — 호버 시 인디케이터 위치를 갱신한다
    private func dropZone(for target: ChatSession, placeBefore: Bool) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { items, _ in
                handleSessionDrop(items, target: target, placeBefore: placeBefore)
            } isTargeted: { hovering in
                if hovering {
                    hoverDropTargetID = target.id
                    insertAbove = placeBefore
                } else if hoverDropTargetID == target.id && insertAbove == placeBefore {
                    hoverDropTargetID = nil
                }
            }
    }

    /// 세션 간 드롭 처리 — 단일 목록에서 순서만 변경 (프로젝트 그룹 개념 제거 — v0.1.2)
    private func handleSessionDrop(_ items: [String], target: ChatSession, placeBefore: Bool) -> Bool {
        defer { hoverDropTargetID = nil }
        guard let raw = items.first, let draggedID = UUID(uuidString: raw),
              draggedID != target.id,
              viewModel.visibleSessions.contains(where: { $0.id == draggedID }) else { return false }

        insertAbove = placeBefore
        var order = SessionOrderStore.normalizedOrder(SessionOrderStore.readOrder(), sessions: viewModel.visibleSessions)
        order = SessionOrderStore.reorderedIDs(order, moving: draggedID, relativeTo: target.id, placeBefore: placeBefore)
        SessionOrderStore.writeOrder(order)

        DebugLogger.shared.info("SIDEBAR", "[FEATURE] 세션 이동 실행됨: \(target.title.prefix(20)) → \(placeBefore ? "앞" : "뒤")")
        return true
    }
}