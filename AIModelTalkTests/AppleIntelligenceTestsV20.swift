import XCTest
@testable import AIModelTalk

/// v2.0 T-79 — Apple Intelligence 클라이언트 (프롬프트 조합·가용성 헬퍼)
/// 스트리밍 본체는 시스템 모델 의존이라 실기기 확인 필요 — 순수 로직만 자동 검증
final class AppleIntelligenceTestsV20: XCTestCase {

    func testBuildPromptIncludesHistoryWithSpeakers() {
        let messages: [AIModelTalk.ChatMessage] = [
            AIModelTalk.ChatMessage(role: .user, content: "첫 질문"),
            AIModelTalk.ChatMessage(role: .assistant, content: "첫 답변"),
            AIModelTalk.ChatMessage(role: .user, content: "후속 질문")
        ]
        let prompt = AppleIntelligenceClient.buildPrompt(from: messages)
        XCTAssertTrue(prompt.contains("[사용자] 첫 질문"))
        XCTAssertTrue(prompt.contains("[어시스턴트] 첫 답변"))
        XCTAssertTrue(prompt.contains("[사용자] 후속 질문"))
        // 순서 보존
        let rangeA = prompt.range(of: "첫 질문")!
        let rangeB = prompt.range(of: "후속 질문")!
        XCTAssertLessThan(rangeA.lowerBound, rangeB.lowerBound)
    }

    func testBuildPromptSkipsSystemAndEmpty() {
        let messages: [AIModelTalk.ChatMessage] = [
            AIModelTalk.ChatMessage(role: .system, content: "시스템 지시는 제외"),
            AIModelTalk.ChatMessage(role: .user, content: "본문")
        ]
        let prompt = AppleIntelligenceClient.buildPrompt(from: messages)
        XCTAssertFalse(prompt.contains("시스템 지시는 제외"), "system 역할은 instructions 경로로만")
        XCTAssertTrue(prompt.hasPrefix("[사용자] 본문"))
    }

    func testOSSupportFlagConsistentWithCompileSDK() {
        // 컴파일 타깃 SDK와 런타임 플래그 일치성 — 최소 검증
        XCTAssertEqual(AppleIntelligenceSupport.osSupported, ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        ))
    }

    // MARK: 컨텍스트 예산 절단 (v2.1 T-104)

    func testBuildTrimmedPromptKeepsRecentWithinBudget() {
        let base = String(repeating: "가", count: 7_000)
        let messages: [AIModelTalk.ChatMessage] = [
            AIModelTalk.ChatMessage(role: .user, content: base + "-OLDEST"),      // 예산 초과로 제외 대상
            AIModelTalk.ChatMessage(role: .assistant, content: base + "-MIDDLE"), // 유지 대상
            AIModelTalk.ChatMessage(role: .user, content: "최근 질문")
        ]
        let (prompt, dropped) = AppleIntelligenceClient.buildTrimmedPrompt(from: messages)
        XCTAssertLessThanOrEqual(prompt.count, AppleIntelligenceClient.contextCharBudget + 100, "예산 내 절단")
        XCTAssertGreaterThanOrEqual(dropped, 1, "초과분은 오래된 메시지부터 제외")
        XCTAssertTrue(prompt.contains("최근 질문"), "최근 메시지는 반드시 유지")
        XCTAssertTrue(prompt.contains("-MIDDLE"), "예산 내 중간 메시지 유지")
        XCTAssertFalse(prompt.contains("-OLDEST"), "제외된 가장 오래된 본문은 미포함")
    }

    func testBuildTrimmedPromptNoDropWithinBudget() {
        let messages: [AIModelTalk.ChatMessage] = [
            AIModelTalk.ChatMessage(role: .user, content: "짧은 질문"),
            AIModelTalk.ChatMessage(role: .assistant, content: "짧은 답변")
        ]
        let (prompt, dropped) = AppleIntelligenceClient.buildTrimmedPrompt(from: messages)
        XCTAssertEqual(dropped, 0, "예산 내선 아무것도 제외하지 않음")
        XCTAssertTrue(prompt.contains("짧은 질문") && prompt.contains("짧은 답변"))
    }
}
