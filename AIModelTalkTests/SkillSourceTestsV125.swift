import XCTest
@testable import AIModelTalk

// MARK: - v2.5 T-125: 스킬 소스 확장 — 다중 소스·우선순위 병합·구데이터 호환

@MainActor
final class SkillSourceTestsV125: XCTestCase {

    private var rootURL: URL!

    override func setUp() async throws {
        rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("skilltest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: rootURL)
    }

    /// 소스별 실제 상대 경로 — 점 접두사 포함
    private static func relativePath(for source: SkillSource) -> String {
        switch source {
        case .opencode: return ".opencode/skills"
        case .claude: return ".claude/skills"
        case .alma: return ".config/alma/skills"
        case .project: return ".alma/skills"
        }
    }

    /// 임시 스킬 디렉터리 생성 — 이름/SKILL.md 반환
    @discardableResult
    private func makeSkill(_ source: SkillSource, name: String, skillName: String = "스킬",
                           description: String = "설명") throws -> URL {
        let dir = rootURL
            .appendingPathComponent(Self.relativePath(for: source), isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let md = """
        ---
        name: \(skillName)
        description: \(description)
        ---

        본문 내용
        """
        try md.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return dir
    }

    private func dirs() -> [SkillLoader.SourceDirectory] {
        SkillLoader.sourceDirectories(home: rootURL, projectRoot: rootURL)
    }

    // MARK: - 소스 디렉터리 구성

    func testSourceDirectoriesInPriorityOrder() {
        let all = dirs()
        XCTAssertEqual(all.map(\.source), [.opencode, .claude, .alma, .project])
    }

    func testNilProjectRootOmitsProjectSource() {
        let all = SkillLoader.sourceDirectories(home: rootURL, projectRoot: nil)
        XCTAssertEqual(all.map(\.source), [.opencode, .claude, .alma])
    }

    // MARK: - 다중 소스 로드

    func testLoadsSkillsFromAllSources() throws {
        try makeSkill(.opencode, name: "alpha", skillName: "알파")
        try makeSkill(.claude, name: "beta", skillName: "베타")
        try makeSkill(.alma, name: "gamma", skillName: "감마")
        try makeSkill(.project, name: "delta", skillName: "델타")

        let skills = SkillLoader.load(from: dirs())
        XCTAssertEqual(skills.map(\.id).sorted(), ["alpha", "beta", "delta", "gamma"])
        let byID = Dictionary(uniqueKeysWithValues: skills.map { ($0.id, $0) })
        XCTAssertEqual(byID["alpha"]?.source, .opencode)
        XCTAssertEqual(byID["beta"]?.source, .claude)
        XCTAssertEqual(byID["gamma"]?.source, .alma)
        XCTAssertEqual(byID["delta"]?.source, .project)
        XCTAssertEqual(byID["delta"]?.name, "델타")
    }

    func testDuplicateIDDropsLowerPriority() throws {
        try makeSkill(.opencode, name: "shared", skillName: "오픈코드판")
        try makeSkill(.claude, name: "shared", skillName: "클라우드판")
        try makeSkill(.project, name: "shared", skillName: "프로젝트판")

        let skills = SkillLoader.load(from: dirs())
        let shared = skills.first { $0.id == "shared" }
        XCTAssertEqual(shared?.name, "오픈코드판")
        XCTAssertEqual(skills.filter { $0.id == "shared" }.count, 1)
    }

    func testClaudeWinsWhenOpenCodeMissing() throws {
        try makeSkill(.alma, name: "solo", skillName: "알매판")
        try makeSkill(.claude, name: "solo", skillName: "클라우드판")

        let solo = SkillLoader.load(from: dirs()).first { $0.id == "solo" }
        XCTAssertEqual(solo?.source, .claude)
        XCTAssertEqual(solo?.name, "클라우드판")
    }

    func testMissingDirectoriesAndLooseFilesIgnored() throws {
        try makeSkill(.opencode, name: "valid")
        // 디렉터리가 아닌 파일 — 무시
        let loose = rootURL.appendingPathComponent(".opencode/skills/loose.txt")
        try "text".write(to: loose, atomically: true, encoding: .utf8)

        let skills = SkillLoader.load(from: dirs())
        XCTAssertEqual(skills.count, 1)
        XCTAssertEqual(skills[0].id, "valid")
    }

    // MARK: - 구데이터 호환

    func testLegacyJSONWithoutSourceDecodesAsOpenCode() throws {
        let legacy = """
        [{"id":"old","name":"옛 스킬","description":"d","content":"c","path":"/p"}]
        """
        let decoded = try JSONDecoder().decode([SkillInfo].self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded[0].source, .opencode)
    }

    func testSourceRoundTrip() throws {
        let skill = SkillInfo(id: "x", name: "x", description: "", content: "", path: "/x", source: .project)
        let data = try JSONEncoder().encode([skill])
        let restored = try JSONDecoder().decode([SkillInfo].self, from: data)
        XCTAssertEqual(restored[0].source, .project)
    }
}
