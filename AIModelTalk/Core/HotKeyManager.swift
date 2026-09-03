import Carbon.HIToolbox
import AppKit

final class HotKeyManager {
    static let shared = HotKeyManager()

    static let hotKeyPressed = Notification.Name("AIModelTalk.hotKeyPressed")
    static let showOnboardingAgain = Notification.Name("AIModelTalk.showOnboardingAgain")

    private var hotKeys: [Int: EventHotKeyRef] = [:]
    private var handlerInstalled = false

    // MARK: - 등록 (설정 변경 시 재호출)
    func rebind() {
        unregisterAll()
        installHandlerIfNeeded()

        let mods1 = Self.carbonModifiers(UserDefaults.standard.string(forKey: "hotkeyModifiers") ?? "command")
        let key1 = Self.keyCode(UserDefaults.standard.string(forKey: "hotkeyKey") ?? "i")
        register(keyCode: key1, modifiers: mods1, id: 1)

        let mods2 = Self.carbonModifiers(UserDefaults.standard.string(forKey: "hotkeyModifiers2") ?? "command+shift")
        let key2 = Self.keyCode(UserDefaults.standard.string(forKey: "hotkeyKey2") ?? "i")
        register(keyCode: key2, modifiers: mods2, id: 2)

        // 런처 핫키 — ⌥Space 고정 바인딩, 퀵 패널 토글 (v2.0 T-81)
        register(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), id: 3)
    }

    func unregisterAll() {
        for (_, ref) in hotKeys {
            UnregisterEventHotKey(ref)
        }
        hotKeys.removeAll()
    }

    // MARK: - 이벤트 핸들러
    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var hkID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                // 런처(id:3)는 컨트롤러가 직접 토글 — 메인 창 미개방 상태에서도 동작 (v2.0 T-81)
                if hkID.id == 3 {
                    DispatchQueue.main.async {
                        QuickPanelController.shared.toggle()
                    }
                }
                NotificationCenter.default.post(
                    name: HotKeyManager.hotKeyPressed,
                    object: nil,
                    userInfo: ["id": Int(hkID.id)]
                )
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
        handlerInstalled = true
    }

    private func register(keyCode: UInt32, modifiers: UInt32, id: Int) {
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x41495431), id: UInt32(id)) // "AIT1"
        let status = RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let r = ref {
            hotKeys[id] = r
            DebugLogger.shared.info("APP", "[FEATURE] 핫키 등록 성공: id=\(id)")
        } else {
            DebugLogger.shared.warn("APP", "[FEATURE] 핫키 등록 실패: id=\(id), status=\(status) — 다른 앱이 점유 중일 수 있음")
        }
    }

    // MARK: - 변환 헬퍼
    static func carbonModifiers(_ s: String) -> UInt32 {
        var m: UInt32 = 0
        if s.contains("command") { m |= UInt32(cmdKey) }
        if s.contains("shift") { m |= UInt32(shiftKey) }
        if s.contains("option") { m |= UInt32(optionKey) }
        if s.contains("control") { m |= UInt32(controlKey) }
        return m
    }

    static func keyCode(_ s: String) -> UInt32 {
        switch s {
        case "space": return UInt32(kVK_Space)
        case "s": return UInt32(kVK_ANSI_S)
        case "t": return UInt32(kVK_ANSI_T)
        case "q": return UInt32(kVK_ANSI_Q)
        case "i": return UInt32(kVK_ANSI_I)
        default: return UInt32(kVK_Space)
        }
    }
}