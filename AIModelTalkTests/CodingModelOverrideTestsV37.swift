import XCTest
import SwiftData
@testable import AIModelTalk

/// v0.3.3 — 코딩 모드 전송 모델 결정 테스트 (T-334)
/// 코딩 모드 + 선택 모델이 있을 때만 오버라이드, 아니면 nil(현재 모델)
@MainActor
final class CodingModelOverrideTestsV37: XCTestCase {

    private var vm: ChatViewModel!
    private var container: ModelContainer!

    override func setUp() {
        super.setUp()
        let schema = Schema([ChatSessionEntity.self, ChatMessageEntity.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: [config])
        vm = ChatViewModel(context: ModelContext(container))
    }

    override func tearDown() {
        vm = nil
        container = nil
        super.tearDown()
    }

    private func makeSession(mode: ChatMode) -> UUID {
        var session = ChatSession(title: "테스트", mode: mode)
        session.id = UUID()
        vm.sessions.append(session)
        vm.currentSessionID = session.id
        return session.id
    }

    private var codingModel: AIModel {
        AIModel(id: "opencode/muse-spark-1.3-contributor-free", provider: .opencode, displayName: "Muse Spark")
    }

    /// 코딩 모드 + 선택 모델 → 오버라이드 반환
    func testCodingModeWithSelectionReturnsOverride() {
        let id = makeSession(mode: .coding)
        vm.setCodingModel(codingModel, for: id)
        let override = vm.codingModelOverride(for: id)
        XCTAssertEqual(override?.id, codingModel.id)
        XCTAssertEqual(override?.provider, .opencode)
    }

    /// 코딩 모드 + 미선택 → nil
    func testCodingModeWithoutSelectionReturnsNil() {
        let id = makeSession(mode: .coding)
        XCTAssertNil(vm.codingModelOverride(for: id))
    }

    /// 채팅 모드 + 선택 있어도 → nil
    func testChatModeIgnoresSelection() {
        let id = makeSession(mode: .chat)
        vm.setCodingModel(codingModel, for: id)
        XCTAssertNil(vm.codingModelOverride(for: id))
    }

    /// 선택이 현재 모델과 같으면 → nil (불필요한 오버라이드 방지)
    func testSameAsCurrentModelReturnsNil() {
        let id = makeSession(mode: .coding)
        vm.setCodingModel(vm.selectedModel, for: id)
        XCTAssertNil(vm.codingModelOverride(for: id))
    }

    /// 존재하지 않는 세션 → nil
    func testUnknownSessionReturnsNil() {
        XCTAssertNil(vm.codingModelOverride(for: UUID()))
    }
}
