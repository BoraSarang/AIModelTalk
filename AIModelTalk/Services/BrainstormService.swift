import Foundation

/// 브레인스토밍 아이디어 카드 (v2.0 T-80)
struct BrainstormIdea: Identifiable, Equatable {
    let id: UUID
    let text: String
    let angle: String?   // 생성 관점 라벨 ("확장형" 등) — 첫 배치는 nil

    init(id: UUID = UUID(), text: String, angle: String? = nil) {
        self.id = id
        self.text = text
        self.angle = angle
    }
}

@MainActor
final class BrainstormService: ObservableObject {
    static let shared = BrainstormService()

    @Published var topic: String = ""
    @Published var ideas: [BrainstormIdea] = []
    @Published var isGenerating: Bool = false
    /// 스트리밍 중인 원문 — 하단 실시간 미리보기용
    @Published var streamingText: String = ""

    /// 관점 순환 풀 — "다른 관점으로 더"가 눌릴 때마다 다음 관점 적용
    static let angles = ["확장형", "반전형", "결합형", "단순화형", "대상 교체형", "극단화형"]

    private var angleCursor: Int = 0

    // MARK: - 생성

    func generateMore(model: AIModel) async {
        let topicText = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topicText.isEmpty, !isGenerating else { return }

        let angle = Self.angles[angleCursor % Self.angles.count]
        angleCursor += 1

        isGenerating = true
        streamingText = ""
        defer { isGenerating = false }

        DebugLogger.shared.info("BRAINSTORM", "[FEATURE] 브레인스토밍 생성 시작: 주제 '\(topicText.prefix(40))', 모델 \(model.displayName), 관점 '\(angle)', 기존 \(ideas.count)개")

        do {
            let client = try AIClientFactory.client(provider: model.provider, modelID: model.id)

            var userPrompt = """
            주제: "\(topicText)"

            위 주제로 서로 다른 아이디어 8개를 제시하세요.
            형식 규칙:
            - 각 아이디어는 한 줄, 반드시 "- " 로 시작
            - 설명·서론·맺음말 없이 아이디어 줄만 출력
            """
            if !ideas.isEmpty {
                let existingList = ideas.prefix(40).map { "- \($0.text)" }.joined(separator: "\n")
                userPrompt += "\n\n이미 제안된 아이디어(절대 겹치지 않게):\n\(existingList)"
                userPrompt += "\n\n이번에는 특히 **\(angle)** 관점에서만 새 아이디어를 도출하세요."
            }

            var raw = ""
            let stream = client.stream(messages: [ChatMessage(role: .user, content: userPrompt)],
                                       systemPrompt: "당신은 창의적인 브레인스토밍 퍼실리테이터입니다. 모든 출력은 한국어로 합니다.") { _, _ in }
            for try await chunk in stream {
                raw += chunk
                streamingText = raw
            }

            let parsed = Self.parseIdeas(from: raw)
            let fresh = Self.filterNew(parsed, against: ideas)
            ideas.append(contentsOf: fresh.map { BrainstormIdea(text: $0, angle: ideas.isEmpty ? nil : angle) })

            DebugLogger.shared.info("BRAINSTORM", "[FEATURE] 브레인스토밍 생성 완료: 파싱 \(parsed.count)건 → 신규 \(fresh.count)개 추가 (누적 \(ideas.count)개)")
            if fresh.isEmpty {
                DebugLogger.shared.warn("BRAINSTORM", "새 아이디어 없음 — 원문 보존 카드 1개 추가")
                let trimmedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedRaw.isEmpty {
                    ideas.append(BrainstormIdea(text: trimmedRaw, angle: angle))
                }
            }
        } catch {
            let message = "[\(error.localizedDescription)] 생성 실패"
            DebugLogger.shared.error("BRAINSTORM", "브레인스토밍 실패: \(error)")
            ideas.append(BrainstormIdea(text: "⚠️ \(message)", angle: angle))
        }
    }

    func reset() {
        DebugLogger.shared.info("BRAINSTORM", "[FEATURE] 브레인스토밍 초기화 실행됨: \(ideas.count)개 폐기")
        ideas = []
        streamingText = ""
        angleCursor = 0
    }

    // MARK: - 파싱/필터 (테스트 가능하도록 nonisolated static)

    /// 응답에서 아이디어 줄 추출 — 번호/불릿 접두 허용, 나머지 버림
    nonisolated static func parseIdeas(from raw: String) -> [String] {
        raw.split(separator: "\n").compactMap { line -> String? in
            var text = line.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            // 번호 접두 제거: "1." "2)" "10."
            if let match = text.range(of: #"^\d+[.)]\s*"#, options: .regularExpression) {
                text = String(text[match.upperBound...])
            } else if text.hasPrefix("- ") || text.hasPrefix("* ") || text.hasPrefix("• ") {
                text = String(text.dropFirst(2))
            } else {
                return nil // 규칙에 맞는 줄만 채택 — 서론/맺음말 자동 제거
            }
            text = text.trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
    }

    /// 기존 아이디어와 중복 제거 — 공백 정규화 + 대소문자 무시 포함 일치
    nonisolated static func filterNew(_ candidates: [String], against existing: [BrainstormIdea]) -> [String] {
        func normalized(_ s: String) -> String {
            s.lowercased().replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        }
        let existingSet = Set(existing.map { normalized($0.text) })
        var seen = Set<String>()
        var fresh: [String] = []
        for candidate in candidates {
            let key = normalized(candidate)
            guard !key.isEmpty, !existingSet.contains(key), !seen.contains(key) else { continue }
            seen.insert(key)
            fresh.append(candidate)
        }
        return fresh
    }
}
