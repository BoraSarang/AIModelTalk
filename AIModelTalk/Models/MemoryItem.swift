import Foundation

/// 메모리 내구성 — 영구는 자동 정리 대상에서 제외
enum MemoryDurability: String, Codable {
    case permanent
    case temporary
}

/// 앱 전역 단일 장기 기억 항목 — 모든 대화의 시스템 프롬프트에 주입되어 연속성을 만든다.
/// 과거 캐릭터(persona) 단위 메모리를 전역으로 전환하면서 Persona.swift에서 분리했다 (v0.1.2).
struct MemoryItem: Codable, Equatable, Identifiable {
    var id = UUID()
    var content: String
    var createdAt = Date()
    var isPinned = false
    /// 자동 추출(true) / 사용자 수동(false)
    var isAuto = false
    /// 중요도 0~1 — 검색 순위·정리 우선순위
    var importance: Double = 0.5
    /// 자유 태그 — 필터링·주제 구분
    var tags: [String] = []
    /// 영구는 eviction·임시 정리 대상에서 제외
    var durability: MemoryDurability = .permanent

    /// 과거 형태(신규 필드 부재) JSON 호환
    private enum CodingKeys: String, CodingKey {
        case id, content, createdAt, isPinned, isAuto, importance, tags, durability
    }

    init(content: String, createdAt: Date = Date(), isPinned: Bool = false, isAuto: Bool = false,
         importance: Double = 0.5, tags: [String] = [], durability: MemoryDurability = .permanent) {
        self.content = content
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.isAuto = isAuto
        self.importance = importance
        self.tags = tags
        self.durability = durability
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        content = try c.decode(String.self, forKey: .content)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isAuto = try c.decodeIfPresent(Bool.self, forKey: .isAuto) ?? false
        importance = try c.decodeIfPresent(Double.self, forKey: .importance) ?? 0.5
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        durability = try c.decodeIfPresent(MemoryDurability.self, forKey: .durability) ?? .permanent
    }
}