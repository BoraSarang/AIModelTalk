import Foundation

/// 전역 메모리 자동 추출·관리 (v0.1.2 전역화)
/// 대화 중 중요한 정보를 뽑아 앱 전역의 장기 기억으로 저장 — 모든 대화에 주입된다.
/// 추출 실패는 사용자 노출 없이 로그만 남긴다 (E-MAC-AI-1005).
enum MemoryService {
    /// 메모리 상한 — 초과 시 미핀 최오래된 항목부터 퇴출
    static let maxMemories = 20

    // MARK: - 트리거 판정

    /// 사용자 메시지 N건마다 1회 추출 실행 (v2.2 T-112)
    nonisolated static func shouldExtract(userMessageCount: Int, every: Int = 4) -> Bool {
        userMessageCount > 0 && userMessageCount % every == 0
    }

    // MARK: - 추출 프롬프트

    nonisolated static func extractionPrompt(existing: [String], recentTranscript: String) -> String {
        let existingBlock = existing.isEmpty ? "(없음)" : existing.map { "- \($0)" }.joined(separator: "\n")
        return """
        당신은 APP의 장기 기억 관리자입니다. 아래 최근 대화에서 앞으로도 기억할 가치가 있는 정보만 추출하세요.

        규칙:
        - 사용자의 선호·결정·중요 사실·약속 등 지속성 있는 정보만
        - 일상적 인사·단발성 질문·사소한 잡담은 제외
        - 각 항목은 한 문장의 사실형으로
        - 기억할 새로운 것이 없으면 빈 배열

        기존 기억:
        \(existingBlock)

        최근 대화:
        \(recentTranscript)

        출력은 아래 JSON 형식만 (다른 설명 금지):
        {"memories": ["기억1", "기억2"]}
        """
    }

    // MARK: - 응답 파싱 (방어적 디코딩 — T-88 선례)

    /// 모델 응답에서 기억 후보 문자열 배열 추출 — 코드펜스·배열 단독 출력도 허용
    nonisolated static func parseCandidates(_ text: String) -> [String] {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 코드펜스 제거
        if t.hasPrefix("```") {
            t = t
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 1) 정식 JSON 객체
        if let data = t.data(using: .utf8),
           let obj = try? JSONDecoder().decode(MemoriesPayload.self, from: data) {
            return obj.memories
        }

        // 2) JSON 객체가 앞뒤 잡음 속에 있으면 { ... } 부분만 재시도
        if let start = t.firstIndex(of: "{"), let end = t.lastIndex(of: "}"), start < end {
            let slice = String(t[start...end])
            if let data = slice.data(using: .utf8),
               let obj = try? JSONDecoder().decode(MemoriesPayload.self, from: data) {
                return obj.memories
            }
        }

        // 3) 배열 단독 출력 폴백
        if let data = t.data(using: .utf8),
           let array = try? JSONDecoder().decode([String].self, from: data) {
            return array
        }

        return []
    }

    private struct MemoriesPayload: Decodable {
        /// 문자열 배열 또는 {content} 객체 배열 모두 허용
        let memories: [String]

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let strings = try? c.decode([String].self, forKey: .memories) {
                memories = strings
            } else if let objects = try? c.decode([ContentObject].self, forKey: .memories) {
                memories = objects.map { $0.content }
            } else {
                memories = []
            }
        }

        enum CodingKeys: String, CodingKey { case memories }

        struct ContentObject: Decodable {
            let content: String
        }
    }

    // MARK: - 중복 제거

    /// 기존·후보 간 부분 문자열 포함 관계로 중복 판정 (순수)
    nonisolated static func deduplicate(_ candidates: [String], existing: [String]) -> [String] {
        var seen = existing.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var result: [String] = []
        for candidate in candidates {
            let t = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            if seen.contains(where: { $0.contains(t) || t.contains($0) }) { continue }
            seen.append(t)
            result.append(t)
        }
        return result
    }

    // MARK: - 저장 적용 (캡 + eviction)

    /// 후보를 전역 메모리에 추가 — 상한 초과 시 '기존' 미핀 항목 퇴출 (순수)
    /// 임시 내구성이 영구보다 먼저, 같으면 최오래된 순. 핀과 신규는 보호.
    /// 기존 미핀이 부족하면 상한 초과를 허용한다.
    nonisolated static func applying(_ candidates: [String], to items: [MemoryItem], now: Date = Date()) -> [MemoryItem] {
        var current = items
        let existingIDs = Set(current.map { $0.id })
        let newItems = candidates.map {
            MemoryItem(content: $0, createdAt: now, isPinned: false, isAuto: true)
        }
        current.append(contentsOf: newItems)

        if current.count > maxMemories {
            let overflow = current.count - maxMemories
            let evictable = current
                .filter { existingIDs.contains($0.id) && !$0.isPinned }
                .sorted {
                    if ($0.durability == .temporary) != ($1.durability == .temporary) {
                        return $0.durability == .temporary // 임시 우선 퇴출
                    }
                    return $0.createdAt < $1.createdAt
                }
                .prefix(overflow)
            let evictIDs = Set(evictable.map { $0.id })
            current.removeAll { evictIDs.contains($0.id) }
        }
        return current
    }
}
