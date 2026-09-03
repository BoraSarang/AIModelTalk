import XCTest
import SwiftData
@testable import AIModelTalk

/// v0.1.2 — 페르소나/프로젝트 제거 후 앱 전역 단일 메모리 계약 테스트
final class GlobalMemoryTestsV011: XCTestCase {

    func testMemoryStoreUpsertRemoveRoundTrip() {
        let suite = "GlobalMemoryTestsV011-store-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        var store = MemoryStore(defaults: defaults)

        XCTAssertTrue(store.items.isEmpty, "초기 전역 메모리 없음")
        store.upsert(MemoryItem(content: "첫 기억"))
        XCTAssertEqual(store.items.count, 1)

        let added = MemoryItem(content: "둘째 기억")
        store.upsert(added)
        XCTAssertEqual(store.items.count, 2)

        store.remove(id: added.id)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.content, "첫 기억")
    }

    @MainActor
    func testVMGlobalMemoryCRUD() throws {
        let suite = "GlobalMemoryTestsV011-crud-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let schema = Schema([ChatSessionEntity.self, ChatMessageEntity.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let vm = ChatViewModel(context: ModelContext(container), defaults: defaults)

        vm.addMemory("전역에 남길 기억")
        XCTAssertEqual(vm.memoryItems.count, 1)
        XCTAssertTrue(vm.memoryItems[0].content.contains("전역에 남길 기억"))
        XCTAssertFalse(vm.memoryItems[0].isAuto, "수동 추가는 isAuto=false")

        let added = vm.memoryItems[0]
        vm.toggleMemoryPin(memoryID: added.id)
        XCTAssertEqual(vm.memoryItems.first { $0.id == added.id }?.isPinned, true, "핀 토글")

        vm.deleteMemory(memoryID: added.id)
        XCTAssertTrue(vm.memoryItems.isEmpty, "삭제 후 비어 있음")
    }

    @MainActor
    func testVMAddMemoryIgnoresBlank() throws {
        let suite = "GlobalMemoryTestsV011-blank-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let schema = Schema([ChatSessionEntity.self, ChatMessageEntity.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let vm = ChatViewModel(context: ModelContext(container), defaults: defaults)

        vm.addMemory("   ")
        XCTAssertTrue(vm.memoryItems.isEmpty, "공백 메모리는 추가하지 않는다")
    }

    func testAssemblePromptInjectsGlobalMemoryPinnedFirst() {
        let older = MemoryItem(content: "오래된 기억", createdAt: Date(timeIntervalSinceNow: -100_000))
        let recent = MemoryItem(content: "최근 기억", createdAt: Date())
        let pinned = MemoryItem(content: "핀 기억", isPinned: true)

        let prompt = ChatViewModel.assemblePrompt(base: "베이스", memories: [older, pinned, recent], includeMemory: true)

        XCTAssertTrue(prompt.hasPrefix("베이스"))
        XCTAssertTrue(prompt.contains("## 장기 기억"))
        let pinIndex = prompt.range(of: "핀 기억")!.lowerBound
        let recentIndex = prompt.range(of: "최근 기억")!.lowerBound
        XCTAssertLessThan(pinIndex, recentIndex, "핀 기억이 메모리 블록 선두")
    }

    func testAssemblePromptMemoryBudgetTruncation() {
        let long = MemoryItem(content: String(repeating: "가", count: 2000))
        let prompt = ChatViewModel.assemblePrompt(
            base: "베이스", memories: [long, long, long], memoryBudget: 3000, includeMemory: true)

        XCTAssertTrue(prompt.contains("## 장기 기억"))
    }
}