import Foundation

/// 사이드바 세션 표시 순서 저장소 — 드래그 재배치 결과를 UserDefaults에 영구 저장 (v2.1 T-99)
/// 순서는 사이드바 표시 전용이며 세션 데이터 자체는 변경하지 않는다.
enum SessionOrderStore {
    static let orderKey = "sidebarSessionOrder"

    static func readOrder() -> [UUID] {
        guard let data = UserDefaults.standard.data(forKey: orderKey) else { return [] }
        return (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
    }

    static func writeOrder(_ ids: [UUID]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(ids), forKey: orderKey)
    }

    /// 현재 보이는 세션 기준으로 순서 배열 정규화:
    /// - 삭제된 세션 ID 프루닝 + 중복 제거
    /// - 미등록 세션은 updatedAt 내림차순으로 뒤에 추가 (신규 대화가 자연스럽게 하단 배치)
    static func normalizedOrder(_ current: [UUID], sessions: [ChatSession]) -> [UUID] {
        let knownIDs = Set(sessions.map(\.id))
        var seen = Set<UUID>()
        var result = current.filter { knownIDs.contains($0) && seen.insert($0).inserted }
        let missing = sessions
            .filter { !result.contains($0.id) }
            .sorted { $0.updatedAt > $1.updatedAt }
        result.append(contentsOf: missing.map(\.id))
        return result
    }

    /// dragged를 target 앞/뒤로 이동시킨 새 순서 반환 — 순수 함수(테스트 대상).
    /// dragged == target, 대상 부재 시 원본을 그대로 반환한다.
    static func reorderedIDs(_ order: [UUID], moving dragged: UUID, relativeTo target: UUID, placeBefore: Bool) -> [UUID] {
        guard dragged != target, order.contains(target), order.contains(dragged) else { return order }
        var working = order
        working.removeAll { $0 == dragged }
        guard let targetIndex = working.firstIndex(of: target) else { return order }
        working.insert(dragged, at: placeBefore ? targetIndex : working.index(after: targetIndex))
        return working
    }
}
