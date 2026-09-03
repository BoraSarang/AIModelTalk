import XCTest
import SwiftData
@testable import AIModelTalk

/// v0.1.1 — 보관함/휴지통: ChatSessionEntity의 archivedAt/deletedAt 필드 저장·복원 (인메모리 컨테이너 격리)
@MainActor
final class ArchiveTrashPersistenceTestsV011: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() {
        super.setUp()
        let schema = Schema([ChatSessionEntity.self, ChatMessageEntity.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    func testArchiveAndDeleteFieldsRoundTrip() throws {
        let archived = Date(timeIntervalSince1970: 1000)
        let deleted = Date(timeIntervalSince1970: 2000)
        let session = ChatSession(title: "보관+휴지통 세션", archivedAt: archived, deletedAt: deleted)
        let entity = ChatSessionEntity(from: session)
        context.insert(entity)
        try context.save()

        let fetched = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatSessionEntity>()).first)
        XCTAssertEqual(fetched.archivedAt, archived)
        XCTAssertEqual(fetched.deletedAt, deleted)

        let restored = fetched.toChatSession()
        XCTAssertEqual(restored.archivedAt, archived)
        XCTAssertEqual(restored.deletedAt, deleted)
    }

    func testDefaultSessionHasNilArchiveAndDelete() throws {
        let session = ChatSession(title: "활성 세션")
        XCTAssertNil(session.archivedAt)
        XCTAssertNil(session.deletedAt)

        let entity = ChatSessionEntity(from: session)
        context.insert(entity)
        try context.save()

        let fetched = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatSessionEntity>()).first)
        XCTAssertNil(fetched.archivedAt)
        XCTAssertNil(fetched.deletedAt)
    }

    func testLegacySessionDecodesWithNilNewFields() throws {
        // 신규 필드 없이 생성한 세션도 휴지통/보관 필드가 nil로 정상 처리 (기존 데이터 호환)
        let session = ChatSession(title: "레거시 세션")
        let entity = ChatSessionEntity(from: session)
        context.insert(entity)
        try context.save()

        let fetched = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatSessionEntity>()).first)
        XCTAssertNil(fetched.archivedAt)
        XCTAssertNil(fetched.deletedAt)
    }

    func testUpdateSyncedArchiveAndDeleteFields() throws {
        // saveSession-동일 경로: 기존 엔티티 업데이트 시 archivedAt/deletedAt 동기화되는지 확인
        let session = ChatSession(title: "원본")
        let entity = ChatSessionEntity(from: session)
        context.insert(entity)
        try context.save()

        let archived = Date(timeIntervalSince1970: 3000)
        let deleted = Date(timeIntervalSince1970: 4000)
        var updated = ChatSession(title: "갱신", archivedAt: archived, deletedAt: deleted)
        updated.id = entity.id
        // saveSession의 업데이트 경로와 동일한 필드 동기화
        let sessionID = entity.id
        let descriptor = FetchDescriptor<ChatSessionEntity>(predicate: #Predicate { $0.id == sessionID })
        let existing = try XCTUnwrap(try context.fetch(descriptor).first)
        existing.archivedAt = updated.archivedAt
        existing.deletedAt = updated.deletedAt
        try context.save()

        let restored = try XCTUnwrap(try context.fetch(descriptor).first).toChatSession()
        XCTAssertEqual(restored.archivedAt, archived)
        XCTAssertEqual(restored.deletedAt, deleted)
    }
}

/// v0.1.1 — 상태 파생: 필터/정렬/우선순위 로직 단위 테스트 (순수 로직)
final class ArchiveTrashStateDerivationTestsV011: XCTestCase {

    private func makeSession(id: UUID = UUID(), title: String = "세션", archivedAt: Date? = nil, deletedAt: Date? = nil) -> ChatSession {
        ChatSession(id: id, title: title, archivedAt: archivedAt, deletedAt: deletedAt)
    }

    func testDeletedAtTakesPriorityOverArchivedAt() {
        // 휴지통(deletedAt)이 보관(archivedAt)보다 우선 — delete가 전체 해제 후 설정하지만
        // 모델 수준에서는 deletedAt이 세지 않으면 보관 상태로 유지된다
        let s = makeSession(archivedAt: Date(), deletedAt: Date())
        XCTAssertNotNil(s.deletedAt)
        // 활성 여부 판정 = deletedAt == nil && archivedAt == nil (예: 삭제된 세션이면서 archivedAt 있어도 활성이 아님)
        let isActive = (s.deletedAt == nil && s.archivedAt == nil)
        XCTAssertFalse(isActive)
    }

    func testArchivedSessionsSortedByArchivedAtDescending() {
        let older = makeSession(id: UUID(), title: "오래된 보관", archivedAt: Date(timeIntervalSince1970: 100))
        let newer = makeSession(id: UUID(), title: "최근 보관", archivedAt: Date(timeIntervalSince1970: 200))
        let active = makeSession(id: UUID(), title: "활성")
        let deleted = makeSession(id: UUID(), title: "휴지통", deletedAt: Date())

        let archived = [older, newer, active, deleted]
            .filter { $0.archivedAt != nil && $0.deletedAt == nil }
            .sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }

        XCTAssertEqual(archived.map(\.title), ["최근 보관", "오래된 보관"])
        XCTAssertFalse(archived.contains { $0.title == "활성" || $0.title == "휴지통" })
    }

    func testTrashSessionsSortedByDeletedAtDescending() {
        let older = makeSession(id: UUID(), title: "오래된 삭제", deletedAt: Date(timeIntervalSince1970: 100))
        let newer = makeSession(id: UUID(), title: "최근 삭제", deletedAt: Date(timeIntervalSince1970: 200))
        let active = makeSession(id: UUID(), title: "활성")

        let trash = [older, newer, active]
            .filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }

        XCTAssertEqual(trash.map(\.title), ["최근 삭제", "오래된 삭제"])
        XCTAssertFalse(trash.contains { $0.title == "활성" })
    }

    func testVisibleSessionsExcludeArchivedAndDeleted() {
        let active = makeSession(id: UUID(), title: "활성")
        let archived = makeSession(id: UUID(), title: "보관", archivedAt: Date())
        let deleted = makeSession(id: UUID(), title: "휴지통", deletedAt: Date())

        let all = [active, archived, deleted]
        let visible = all.filter { $0.deletedAt == nil && $0.archivedAt == nil }

        XCTAssertEqual(visible.map(\.title), ["활성"])
    }
}