import XCTest
import SwiftData
@testable import AIModelTalk
import Carbon.HIToolbox

@MainActor
final class ModelLabelTests: XCTestCase {

    func testAIModelLabelFormat() {
        let model = AIModel(id: "openai/gpt-oss-20b", provider: .nvidia, displayName: "GPT-OSS-20B")
        XCTAssertEqual(model.label, "NVIDIA GPT-OSS-20B (gpt-oss-20b)")
    }

    func testModelCatalogLabelLookup() {
        let label = ModelCatalog.label(for: .nvidia, modelID: "openai/gpt-oss-20b")
        XCTAssertTrue(label.hasPrefix("NVIDIA "))
        XCTAssertTrue(label.contains("GPT-OSS-20B"))
        XCTAssertTrue(label.hasSuffix("(gpt-oss-20b)"))
    }

    func testUnknownModelLabelFallback() {
        let label = ModelCatalog.label(for: .groq, modelID: "unknown/model-x")
        XCTAssertEqual(label, "Groq model-x")
    }
}

/// v2.1 R3 — 싱글턴(.shared) 대신 인메모리 컨텍스트+격리 UserDefaults 주입으로 전환.
/// 실앱 데이터(페르소나 오버라이드·스킬 플래그)와 완전히 분리되어 간헐 실패가 없다.
@MainActor
final class MultiSkillAndPromptTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var container: ModelContainer!
    private var vm: ChatViewModel!

    override func setUp() {
        super.setUp()
        let schema = Schema([ChatSessionEntity.self, ChatMessageEntity.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: [config])
        suiteName = "MultiSkillTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        vm = ChatViewModel(context: ModelContext(container), defaults: defaults)
    }

    override func tearDown() {
        if let suiteName {
            UserDefaults().removePersistentDomain(forName: suiteName)
        }
        suiteName = nil
        vm = nil
        container = nil
        defaults = nil
        super.tearDown()
    }

    func testToggleSkillAddsAndRemoves() {
        let before = vm.selectedSkills.count
        let skill = SkillInfo(id: "s1", name: "스킬A", description: "설명", content: "내용A", path: "")
        vm.toggleSkill(skill)
        XCTAssertEqual(vm.selectedSkills.count, before + 1)
        vm.toggleSkill(skill)
        XCTAssertEqual(vm.selectedSkills.count, before)
    }

    func testBuildSystemPromptCombinesSkills() {
        AppSettings.shared.systemPrompt = "기본 프롬프트"
        vm.clearSkills()
        let skill = SkillInfo(id: "s2", name: "스킬B", description: "d", content: "추가내용", path: "")
        vm.toggleSkill(skill)

        let prompt = vm.buildSystemPrompt()
        XCTAssertTrue(prompt.contains("기본 프롬프트"))
        XCTAssertTrue(prompt.contains("## 스킬: 스킬B"))
        XCTAssertTrue(prompt.contains("추가내용"))

        // 정리
        vm.clearSkills()
        AppSettings.shared.systemPrompt = ""
    }

    /// v1.9 변경: 세션 systemPrompt는 오버라이드 전용(빈 값=전역 따름)이므로
    /// 모델 변경 시 스냅샷을 굽지 않는다. 대신 currentModel만 갱신된다.
    func testSelectModelUpdatesSessionSystemPrompt() {
        AppSettings.shared.systemPrompt = "전역 프롬프트"
        vm.clearSkills()
        let sessionID = vm.currentSessionID!
        let other = ModelCatalog.shared.models.first { $0.id != vm.selectedModel.id && $0.provider != .custom } ?? vm.selectedModel
        vm.selectModel(other)

        let updated = vm.sessions.first { $0.id == sessionID }
        XCTAssertEqual(updated?.currentModel?.id, other.id)
        XCTAssertTrue(updated?.systemPrompt.isEmpty ?? false, "v1.9부터 스냅샷을 저장하지 않는다")
        AppSettings.shared.systemPrompt = ""
    }
}

final class HotKeyManagerTests: XCTestCase {

    func testCommandIMapsToItalicKey() {
        XCTAssertEqual(HotKeyManager.keyCode("i"), UInt32(kVK_ANSI_I))
        XCTAssertNotEqual(HotKeyManager.keyCode("i"), UInt32(kVK_Space))
    }

    func testCarbonModifiersParsing() {
        let cmd = HotKeyManager.carbonModifiers("command")
        XCTAssertTrue((cmd & UInt32(cmdKey)) != 0)

        let cmdShift = HotKeyManager.carbonModifiers("command+shift")
        XCTAssertTrue((cmdShift & UInt32(cmdKey)) != 0)
        XCTAssertTrue((cmdShift & UInt32(shiftKey)) != 0)
    }

    func testDefaultGlobalHotkeyIsCommandI() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "hotkeyModifiers")
        defaults.removeObject(forKey: "hotkeyKey")
        let mods = HotKeyManager.carbonModifiers(defaults.string(forKey: "hotkeyModifiers") ?? "command")
        let key = HotKeyManager.keyCode(defaults.string(forKey: "hotkeyKey") ?? "i")
        XCTAssertTrue((mods & UInt32(cmdKey)) != 0)
        XCTAssertEqual(key, UInt32(kVK_ANSI_I))
    }
}

final class SkillLoaderTests: XCTestCase {
    func testLoadsSkillsWithNames() async {
        let skills = await SkillLoader.loadSkills()
        XCTAssertFalse(skills.isEmpty, "스킬 디렉토리에서 최소 1개 로드되어야 함")
        XCTAssertTrue(skills.contains { !$0.name.isEmpty }, "스킬명이 비어 있으면 안 됨")
    }
}
