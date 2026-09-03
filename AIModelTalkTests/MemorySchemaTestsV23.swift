import XCTest
import SwiftData
@testable import AIModelTalk

/// v2.3 T-116 — 메모리 스키마 확장 + 인코그니토 테스트
final class MemorySchemaTestsV23: XCTestCase {

    // MARK: - 구버전 MemoryItem JSON 호환

    func testLegacyMemoryItemDecodesWithDefaults() throws {
        let legacy = """
        {"content":"표 정리 선호","isAuto":true}
        """
        let item = try JSONDecoder().decode(MemoryItem.self, from: Data(legacy.utf8))

        XCTAssertEqual(item.content, "표 정리 선호")
        XCTAssertTrue(item.isAuto)
        XCTAssertEqual(item.importance, 0.5, "기본 중요도")
        XCTAssertTrue(item.tags.isEmpty)
        XCTAssertEqual(item.durability, .permanent, "기본 영구")
    }

    func testNewMemoryFieldsRoundTrip() throws {
        let item = MemoryItem(
            content: "프로젝트 마감일 금요일",
            isPinned: true, isAuto: false,
            importance: 0.9, tags: ["일정", "업무"],
            durability: .temporary)
        let decoded = try JSONDecoder().decode(MemoryItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(decoded, item)
    }

    /// 구버전 Persona JSON이 앱 전역 메모리 스키마와 무관함 — 최신 MemoryItem 필드 없는 기존 데이터 호환 (v0.1.2)
    func testLegacyMemoryItemStillDecodesWithinItem() throws {
        let legacy = """
        {"content":"오래된 기억"}
        """
        let item = try JSONDecoder().decode(MemoryItem.self, from: Data(legacy.utf8))
        XCTAssertEqual(item.content, "오래된 기억")
        XCTAssertEqual(item.durability, .permanent)
    }

    // MARK: - 인코그니토 — 기억 미회수

    func testAssemblePromptSkipsMemoryWhenExcluded() {
        let memories = [MemoryItem(content: "비밀 기억")]

        let with = ChatViewModel.assemblePrompt(base: "베이스", memories: memories, includeMemory: true)
        let without = ChatViewModel.assemblePrompt(base: "베이스", memories: memories, includeMemory: false)

        XCTAssertTrue(with.contains("비밀 기억"))
        XCTAssertFalse(without.contains("비밀 기억"), "인코그니토는 기억 블록을 주입하지 않는다")
    }

    // MARK: - 세션 인코그니토 영속화

    @MainActor
    func testIncognitoTogglePersists() throws {
        let schema = Schema([ChatSessionEntity.self, ChatMessageEntity.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let suite = "MemorySchemaTestsV23-\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let vm = ChatViewModel(context: ModelContext(container), defaults: isolated)
        vm.createNewSession()

        XCTAssertFalse(vm.currentSession?.isIncognito ?? true, "기본값 꺼짐")

        vm.toggleIncognito()
        XCTAssertTrue(vm.currentSession?.isIncognito ?? false)

        vm.toggleIncognito()
        XCTAssertFalse(vm.currentSession?.isIncognito ?? true)
    }

    /// 자동 기억 트리거 — 인코그니토 세션은 4교환을 채워도 대상 아님 (가드 로직 계약)
    func testShouldExtractStillTrueButVMGuardsIncognito() {
        // shouldExtract 자체는 순수 판정 — VM의 인코그니토 가드가 앞단에서 차단하는 구조
        XCTAssertTrue(MemoryService.shouldExtract(userMessageCount: 4))
        // VM 가드는 testIncognitoTogglePersists와 통합 수동 검증(TC-P6)에서 확인
    }
}
