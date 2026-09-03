import AppKit
import ApplicationServices

enum SelectedTextCapture {
    // MARK: - 접근성 권한 상태
    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 선택 텍스트 캡처 (AX 우선, ⌘C 폴백)
    static func captureSelectedText() async -> String? {
        if let text = axSelectedText() {
            return text
        }
        return await cmdCFallback()
    }

    // MARK: - AX 방식 (클립보드 무손상)
    private static func axSelectedText() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success, let focused = focusedRef else { return nil }

        var selectedRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            focused as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            &selectedRef
        )
        guard result == .success, let text = selectedRef as? String, !text.isEmpty else { return nil }
        return text
    }

    // MARK: - ⌘C 폴백 (클립보드 임시 사용 후 복원)
    private static func cmdCFallback() async -> String? {
        let pasteboard = NSPasteboard.general
        let oldCount = pasteboard.changeCount
        let previousContents = pasteboard.string(forType: .string)
        let previousTypes = pasteboard.types

        // ⌘C 시뮬레이션 (kVK_ANSI_C = 0x08)
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        keyDown?.flags = [.maskCommand]
        keyDown?.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 80_000_000)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        keyUp?.flags = [.maskCommand]
        keyUp?.post(tap: .cghidEventTap)

        // 클립보드 갱신 대기 (최대 600ms)
        for _ in 0..<20 {
            if pasteboard.changeCount != oldCount { break }
            try? await Task.sleep(nanoseconds: 30_000_000)
        }

        guard pasteboard.changeCount != oldCount,
              let text = pasteboard.string(forType: .string), !text.isEmpty else {
            restorePasteboard(pasteboard, types: previousTypes, contents: previousContents)
            return nil
        }

        // 원래 클립보드 복원 (약간 지연 후)
        try? await Task.sleep(nanoseconds: 150_000_000)
        restorePasteboard(pasteboard, types: previousTypes, contents: previousContents)
        return text
    }

    private static func restorePasteboard(_ pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]?, contents: String?) {
        pasteboard.clearContents()
        if let contents {
            pasteboard.setString(contents, forType: .string)
        } else if let types {
            pasteboard.declareTypes(types, owner: nil)
        }
    }
}