import Foundation

/// 앱 전역 단일 메모리 저장소 — UserDefaults 주입형 (테스트 격리 가능, PersonaStore와 동일 패턴)
/// 과거 캐릭터(persona) 단위 메모리를 앱 전역으로 전환하며 신규 도입 (v0.1.2).
struct MemoryStore {
    let defaults: UserDefaults
    private let key = "memories"

    var items: [MemoryItem] {
        get {
            guard let data = defaults.data(forKey: key) else { return [] }
            return (try? JSONDecoder().decode([MemoryItem].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: key)
            }
        }
    }

    /// 새 항목 추가 — 이미 동일 내용이 있으면 중복으로 추가하지 않고 false 반환
    @discardableResult
    mutating func upsert(_ item: MemoryItem) -> Bool {
        var list = items
        if let index = list.firstIndex(where: { $0.id == item.id }) {
            list[index] = item
        } else {
            list.append(item)
        }
        items = list
        return true
    }

    mutating func upsert(_ newItems: [MemoryItem]) {
        var list = items
        for item in newItems {
            if let index = list.firstIndex(where: { $0.id == item.id }) {
                list[index] = item
            } else {
                list.append(item)
            }
        }
        items = list
    }

    mutating func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }
}