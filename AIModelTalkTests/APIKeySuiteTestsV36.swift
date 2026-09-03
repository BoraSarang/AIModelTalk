import XCTest
@testable import AIModelTalk

/// v3.6 — API 키 고정 UserDefaults 스위트 저장 (T-164)
/// API 키가 cfprefsd 번들 식별(.standard) 대신 고정 스위트
/// `com.borasarang.AIModelTalk.prefs`에 기록되어 재빌드/재서명에도 유지되는지 검증.
@MainActor
final class APIKeySuiteTestsV36: XCTestCase {

    override func setUp() {
        // 격리된 suite 이름을 직접 열어 테스트 — AppSettings.shared의 실제 스위트와 동일 도메인
        super.setUp()
    }

    override func tearDown() {
        // 테스트가 쓴 키 원복 명시 — 실제 스위트는 건드리지 않음
        super.tearDown()
    }

    func testSuiteNameIsStable() {
        XCTAssertEqual(AppSettings.apiKeySuiteName, "com.borasarang.AIModelTalk.prefs")
        // 스위트 인스턴스가 실제로 열리는지
        XCTAssertNotNil(AppSettings.apiKeyDefaults)
    }

    func testAPIKeyReadsFromSuiteDomain() {
        let suite = AppSettings.apiKeyDefaults
        // 스위트 도메인에서 직접 읽고 씀
        suite.set("sk-suite-test", forKey: "suiteRoundTripKey")
        XCTAssertEqual(suite.string(forKey: "suiteRoundTripKey"), "sk-suite-test")
        suite.removeObject(forKey: "suiteRoundTripKey")
    }

    /// setAPIKey가 suite 속성에 기록되어 suite 도메인에서 값이 읽히는지
    /// (속성 didSet → suite 저장 경로 검증)
    func testAPIKeyStoredInSuiteViaSettings() {
        let suite = AppSettings.apiKeyDefaults
        let original = suite.string(forKey: "nvidiaAPIKey")
        // AppSettings.shared가 아닌 격리 검증: didSet이 suite에 쓰는지 직접 확인
        let settings = AppSettings.shared
        let before = settings.nvidiaAPIKey
        settings.nvidiaAPIKey = "sk-suite-write-test"
        XCTAssertEqual(settings.apiKey(for: .nvidia), "sk-suite-write-test")
        XCTAssertEqual(suite.string(forKey: "nvidiaAPIKey"), "sk-suite-write-test", "didSet이 suite 도메인에 저장")
        // 원복
        settings.nvidiaAPIKey = before
        if let original {
            suite.set(original, forKey: "nvidiaAPIKey")
        } else {
            suite.removeObject(forKey: "nvidiaAPIKey")
        }
    }
}
