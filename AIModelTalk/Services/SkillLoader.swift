import Foundation

/// 스킬 출처 (v2.5 T-125) — 우선순위: opencode > claude > alma > project
enum SkillSource: String, Codable, CaseIterable {
    case opencode
    case claude
    case alma
    case project

    var label: String {
        switch self {
        case .opencode: return "opencode"
        case .claude: return "claude"
        case .alma: return "alma"
        case .project: return "프로젝트"
        }
    }

    /// 낮을수록 높은 우선순위
    var priority: Int {
        switch self {
        case .opencode: return 0
        case .claude: return 1
        case .alma: return 2
        case .project: return 3
        }
    }
}

struct SkillInfo: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let content: String
    let path: String
    var source: SkillSource = .opencode

    private enum CodingKeys: String, CodingKey {
        case id, name, description, content, path, source
    }

    init(id: String, name: String, description: String, content: String, path: String, source: SkillSource = .opencode) {
        self.id = id
        self.name = name
        self.description = description
        self.content = content
        self.path = path
        self.source = source
    }

    /// 구저장 데이터 호환 — source 키 없으면 opencode (v2.5 T-125)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        content = try c.decode(String.self, forKey: .content)
        path = try c.decode(String.self, forKey: .path)
        source = try c.decodeIfPresent(SkillSource.self, forKey: .source) ?? .opencode
    }
}

enum SkillLoader {

    struct SourceDirectory {
        let url: URL
        let source: SkillSource
    }

    /// 스킬 소스 디렉터리 목록 — 우선순위 순 (v2.5 T-125)
    static func sourceDirectories(home: URL, projectRoot: URL?) -> [SourceDirectory] {
        var dirs: [SourceDirectory] = [
            SourceDirectory(url: home.appendingPathComponent(".opencode/skills"), source: .opencode),
            SourceDirectory(url: home.appendingPathComponent(".claude/skills"), source: .claude),
            SourceDirectory(url: home.appendingPathComponent(".config/alma/skills"), source: .alma)
        ]
        if let projectRoot {
            dirs.append(SourceDirectory(url: projectRoot.appendingPathComponent(".alma/skills"), source: .project))
        }
        return dirs
    }

    /// 전체 스킬 로드 — 모든 소스 스캔 후 동일 ID는 높은 우선순위로 병합
    static func loadSkills() async -> [SkillInfo] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let dirs = sourceDirectories(home: home, projectRoot: cwd)

        let skills = await Task.detached(priority: .userInitiated) { [dirs] in
            load(from: dirs)
        }.value

        if !skills.isEmpty {
            let bySource = Dictionary(grouping: skills, by: \.source)
                .map { "\($0.key.rawValue):\($0.value.count)" }
                .sorted()
                .joined(separator: " ")
            DebugLogger.shared.info("APP", "[FEATURE] 스킬 로드 \(skills.count)개 (\(bySource))")
        }
        return skills
    }

    /// 디렉터리 목록에서 SKILL.md 수집 — 순수 파일 시스템 로직 (주입 가능해 테스트 대상)
    static func load(from dirs: [SourceDirectory], fileManager: FileManager = .default) -> [SkillInfo] {
        var merged: [String: SkillInfo] = [:]

        for dir in dirs.sorted(by: { $0.source.priority < $1.source.priority }) {
            guard let items = try? fileManager.contentsOfDirectory(
                at: dir.url,
                includingPropertiesForKeys: nil
            ) else { continue }

            for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard item.hasDirectoryPath else { continue }
                let skillMD = item.appendingPathComponent("SKILL.md")
                guard fileManager.fileExists(atPath: skillMD.path),
                      let raw = try? String(contentsOf: skillMD, encoding: .utf8) else { continue }

                let (name, desc) = parseFrontmatter(raw)
                let skill = SkillInfo(
                    id: item.lastPathComponent,
                    name: name,
                    description: desc,
                    content: raw,
                    path: item.path,
                    source: dir.source
                )
                // 동일 ID — 먼저 넣은(우선순위 높은) 소스 유지
                if merged[skill.id] == nil {
                    merged[skill.id] = skill
                }
            }
        }

        return merged.values.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }

    static func parseFrontmatter(_ text: String) -> (name: String, desc: String) {
        var name = "Unknown"
        var desc = ""

        let lines = text.components(separatedBy: "\n")
        var inFrontmatter = false
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                inFrontmatter.toggle()
                continue
            }
            guard inFrontmatter else { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("name:") {
                name = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.lowercased().hasPrefix("description:") {
                desc = String(trimmed.dropFirst(12)).trimmingCharacters(in: .whitespaces)
            }
        }
        return (name, desc)
    }
}
