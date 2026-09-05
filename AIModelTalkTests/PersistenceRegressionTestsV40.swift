import XCTest
@testable import AIModelTalk

/// v0.3.3 — 영속성 회귀 테스트 (T-341)
/// 공유 default.store 충돌 선례: 앱 전용 URL + 실패 로그 + 필드 영속 보장
@MainActor
final class PersistenceRegressionTestsV40: XCTestCase {

    /// 저장소가 앱 전용 경로 — 공유 default.store 사용 금지
    func testStoreURLIsAppSpecific() {
        let url = PersistenceController.storeURL
        XCTAssertTrue(url.path.contains("AIModelTalk/AIModelTalk.store"), url.path)
        let sharedDefault = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: "default.store", directoryHint: .notDirectory)
        XCTAssertNotEqual(url, sharedDefault, "공유 저장소를 쓰면 타 앱과 충돌해 세션이 증발한다")
    }

    /// 세션 모드 + 모드별 선택 모델 왕복 보존
    func testSessionModeRoundTrip() {
        var session = ChatSession(title: "모드 보존", mode: .coding)
        session.selectedCodingModelID = "OpenCode:opencode/big-pickle"
        session.selectedImageModelID = "OpenAI:gpt-image-1"
        session.selectedAudioModelID = "NVIDIA:nvidia/magpie-tts"
        let entity = ChatSessionEntity(from: session)
        let restored = entity.toChatSession()
        XCTAssertEqual(restored.mode, .coding)
        XCTAssertEqual(restored.selectedCodingModelID, "OpenCode:opencode/big-pickle")
        XCTAssertEqual(restored.selectedImageModelID, "OpenAI:gpt-image-1")
        XCTAssertEqual(restored.selectedAudioModelID, "NVIDIA:nvidia/magpie-tts")
    }

    /// 메시지 followUps 왕복 보존 (생성 후 붙는 필드)
    func testMessageFollowUpsRoundTrip() {
        var message = ChatMessage(role: .assistant, content: "답변")
        message.followUps = ["다음은?", "더 알려줘?"]
        let entity = ChatMessageEntity(from: message, session: nil)
        XCTAssertNotNil(entity.followUpsData, "insert 시점에 followUps 저장")
        XCTAssertEqual(entity.toChatMessage().followUps, ["다음은?", "더 알려줘?"])
    }
}
