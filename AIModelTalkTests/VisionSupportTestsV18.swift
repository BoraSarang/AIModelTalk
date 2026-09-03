import XCTest
import AppKit
@testable import AIModelTalk

/// v1.8 T-71 — Vision(멀티모달) 지원 휴리스틱 + 이미지 첨부 로직 테스트
@MainActor
final class VisionSupportTestsV18: XCTestCase {

    // MARK: - 모델별 supportsVision 휴리스틱

    func testGeminiModelsSupportVision() {
        XCTAssertTrue(AIModel(id: "gemini-3.6-flash", provider: .gemini, displayName: "G").supportsVision)
        XCTAssertFalse(AIModel(id: "gemma-3-12b-it", provider: .gemini, displayName: "Gemma").supportsVision)
    }

    func testOpenRouterKeywordHeuristic() {
        XCTAssertTrue(AIModel(id: "meta-llama/llama-4-maverick:free", provider: .openRouter, displayName: "Llama 4").supportsVision)
        XCTAssertTrue(AIModel(id: "google/gemini-2.5-flash-preview:free", provider: .openRouter, displayName: "Gemini").supportsVision)
        XCTAssertFalse(AIModel(id: "deepseek/deepseek-chat-v3-0324:free", provider: .openRouter, displayName: "DeepSeek").supportsVision)
        XCTAssertFalse(AIModel(id: "qwen/qwen3-235b-a22b:free", provider: .openRouter, displayName: "Qwen3").supportsVision)
    }

    func testGroqAndNvidiaAndOllamaHeuristics() {
        XCTAssertFalse(AIModel(id: "llama-3.3-70b-versatile", provider: .groq, displayName: "L33").supportsVision)
        XCTAssertTrue(AIModel(id: "llama-4-scout", provider: .groq, displayName: "Scout").supportsVision)
        XCTAssertFalse(AIModel(id: "llama3.2:latest", provider: .ollama, displayName: "L32").supportsVision)
        XCTAssertTrue(AIModel(id: "llava:13b", provider: .ollama, displayName: "LLaVA").supportsVision)
        XCTAssertTrue(AIModel(id: "moondream:latest", provider: .ollama, displayName: "MoonDream").supportsVision)
        XCTAssertFalse(AIModel(id: "gpt-oss-20b", provider: .nvidia, displayName: "OSS").supportsVision)
    }

    func testAppleIntelligenceNeverSupportsVision() {
        XCTAssertFalse(AIModel(id: "apple-on-device", provider: .appleIntelligence, displayName: "AI").supportsVision)
    }

    // MARK: - 첨부 관리

    private func makeTestPNG(width: Int = 8, height: Int = 8) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.setColor(NSColor.red, atX: 0, y: 0)
        return rep.representation(using: .png, properties: [:])!
    }

    func testAddAndRemoveAttachment() {
        let vm = ChatViewModel.shared
        vm.clearAttachments()

        vm.addImageAttachment(makeTestPNG(), fileName: "test.png")
        XCTAssertEqual(vm.pendingAttachments.count, 1)
        XCTAssertEqual(vm.pendingAttachments.first?.mimeType, "image/png")

        vm.removeAttachment(id: vm.pendingAttachments[0].id)
        XCTAssertTrue(vm.pendingAttachments.isEmpty)
    }

    func testMaxAttachmentLimit() {
        let vm = ChatViewModel.shared
        vm.clearAttachments()

        for _ in 0..<(ChatViewModel.maxAttachments + 1) {
            vm.addImageAttachment(makeTestPNG())
        }
        XCTAssertEqual(vm.pendingAttachments.count, ChatViewModel.maxAttachments, "최대 개수 초과 추가는 무시됨")
        XCTAssertNotNil(vm.attachmentNotice, "초과 시 안내 문구 표시")
        vm.clearAttachments()
    }
}
