import XCTest
@testable import AIModelTalk

/// T-342 — wigolo 기본 시드 + 실행 파일 탐색기
final class MCPWigoloSeedTestsV41: XCTestCase {

    @MainActor
    private func makeStore() -> MCPServerStore {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return MCPServerStore(defaults: defaults)
    }

    // MARK: - 시드

    @MainActor
    func testFreshStoreContainsWigoloSeedEnabled() {
        let store = makeStore()
        let seed = store.servers.first { $0.id == MCPServerConfig.wigoloSeedID }
        XCTAssertNotNil(seed, "신규 저장소에 wigolo 시드 1건")
        XCTAssertEqual(seed?.name, "wigolo")
        XCTAssertEqual(seed?.command, "npx")
        XCTAssertEqual(seed?.args, ["-y", "wigolo"])
        XCTAssertEqual(seed?.isEnabled, true, "기본값 켜기")
        XCTAssertEqual(seed?.transport, .stdio)
    }

    @MainActor
    func testSeedMigrationIsIdempotent() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        _ = MCPServerStore(defaults: defaults)
        let second = MCPServerStore(defaults: defaults)
        XCTAssertEqual(
            second.servers.filter { $0.id == MCPServerConfig.wigoloSeedID }.count, 1,
            "재초기화해도 중복 시드 없음"
        )
    }

    @MainActor
    func testSeedPreservesExistingServers() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let first = MCPServerStore(defaults: defaults)
        let custom = MCPServerConfig(name: "custom", command: "/usr/local/bin/node", args: ["s.js"])
        first.upsert(custom)
        let second = MCPServerStore(defaults: defaults)
        XCTAssertEqual(second.servers.count, 2, "시드 1 + 기존 1")
        XCTAssertNotNil(second.servers.first { $0.id == custom.id && $0.name == "custom" })
    }

    // MARK: - 탐색기

    func testResolveAbsolutePassthrough() throws {
        XCTAssertEqual(try MCPExecutableResolver.resolve("/bin/sh"), "/bin/sh")
    }

    func testResolveAbsoluteMissingThrows() {
        XCTAssertThrowsError(try MCPExecutableResolver.resolve("/없음/없는바이너리"))
    }

    func testResolveBareMissingThrows() {
        XCTAssertThrowsError(try MCPExecutableResolver.resolve("definitely-not-a-binary-xyz"))
    }

    func testResolveEmptyThrows() {
        XCTAssertThrowsError(try MCPExecutableResolver.resolve("   "))
    }
}
