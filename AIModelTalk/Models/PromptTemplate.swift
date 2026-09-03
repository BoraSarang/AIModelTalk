import Foundation

/// 프롬프트 템플릿 (T-208) — 자주 쓰는 지시를 저장해 입력창에 주입
/// `{{변수}}` 형태의 placeholder는 삽입 시 변수 입력으로 치환한다.
struct PromptTemplate: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var content: String
    var createdAt = Date()

    /// {변수명} placeholder 목록 — 삽입 시 사용자에게 묻고 치환
    func variableNames() -> [String] {
        let pattern = #"\{([^{}]+)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let text = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: text.length))
        var names: [String] = []
        for m in matches where m.numberOfRanges > 1 {
            let name = text.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    /// 변수 값 매핑을 본문에 치환 (placeholders={} → 값)
    func applying(values: [String: String]) -> String {
        var result = content
        for (name, value) in values {
            result = result.replacingOccurrences(of: "{\(name)}", with: value)
        }
        return result
    }
}

/// 전역 프롬프트 템플릿 저장소 — UserDefaults 주입형 (MemoryStore 패턴)
struct PromptTemplateStore {
    let defaults: UserDefaults
    private let key = "prompt_templates"

    var templates: [PromptTemplate] {
        get {
            guard let data = defaults.data(forKey: key) else { return [] }
            return (try? JSONDecoder().decode([PromptTemplate].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: key)
            }
        }
    }

    @discardableResult
    mutating func upsert(_ template: PromptTemplate) -> Bool {
        var list = templates
        if let index = list.firstIndex(where: { $0.id == template.id }) {
            list[index] = template
        } else {
            list.append(template)
        }
        templates = list
        return true
    }

    mutating func remove(id: UUID) {
        templates.removeAll { $0.id == id }
    }
}