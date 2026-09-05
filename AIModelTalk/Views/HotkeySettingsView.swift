import SwiftUI

struct HotkeySettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.theme) private var theme

    private let modifierOptions: [(String, String)] = [
        ("Control", "control"),
        ("Command", "command"),
        ("Option", "option"),
        ("Control + Shift", "control+shift"),
        ("Command + Shift", "command+shift")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.space12) {
                ThemedSettingsCard("런처") {
                    VStack(alignment: .leading, spacing: theme.space8) {
                        Label("⌥Space — 퀵 패널 토글", systemImage: "command.square.fill")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(theme.primaryText)
                        ThemedSettingsCaption("어디서든 퀵 패널을 엽니다. 다른 앱과 충돌해 등록되지 않으면 디버그 패널(HOTKEY 태그)에 기록됩니다.")
                    }
                }

                ThemedSettingsCard("글로벌 단축키") {
                    VStack(alignment: .leading, spacing: theme.space10) {
                        ThemedSettingsRow("수정자") {
                            Picker("", selection: $settings.hotkeyModifiers) {
                                ForEach(modifierOptions, id: \.1) { label, value in
                                    Text(label).tag(value)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        ThemedSettingsRow("키") {
                            Picker("", selection: $settings.hotkeyKey) {
                                Text("Space").tag("space")
                                Text("S").tag("s")
                                Text("T").tag("t")
                                Text("Q").tag("q")
                                Text("I").tag("i")
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        ThemedSettingsCaption("현재 설정: \(displayString)")
                    }
                }

                ThemedSettingsCard("두 번째 단축키") {
                    VStack(alignment: .leading, spacing: theme.space10) {
                        ThemedSettingsRow("수정자") {
                            Picker("", selection: $settings.hotkeyModifiers2) {
                                ForEach(modifierOptions, id: \.1) { label, value in
                                    Text(label).tag(value)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        ThemedSettingsRow("키") {
                            Picker("", selection: $settings.hotkeyKey2) {
                                Text("Space").tag("space")
                                Text("S").tag("s")
                                Text("T").tag("t")
                                Text("Q").tag("q")
                                Text("I").tag("i")
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }
                }
            }
            .padding(theme.space16)
        }
    }

    private var displayString: String {
        "\(Self.modifierLabel(settings.hotkeyModifiers))+\(Self.keyLabel(settings.hotkeyKey)) / \(Self.modifierLabel(settings.hotkeyModifiers2))+\(Self.keyLabel(settings.hotkeyKey2))"
    }

    private static func modifierLabel(_ s: String) -> String {
        switch s {
        case "control": return "Ctrl"
        case "command": return "⌘"
        case "option": return "Option"
        case "control+shift": return "Ctrl+Shift"
        case "command+shift": return "⌘+Shift"
        default: return s
        }
    }

    private static func keyLabel(_ s: String) -> String {
        switch s {
        case "space": return "Space"
        case "s": return "S"
        case "t": return "T"
        case "q": return "Q"
        case "i": return "I"
        default: return s
        }
    }
}

extension AppSettings {
    var hotkeyModifiers2: String {
        get { UserDefaults.standard.string(forKey: "hotkeyModifiers2") ?? "command+shift" }
        set {
            UserDefaults.standard.set(newValue, forKey: "hotkeyModifiers2")
            HotKeyManager.shared.rebind()
        }
    }

    var hotkeyKey2: String {
        get { UserDefaults.standard.string(forKey: "hotkeyKey2") ?? "i" }
        set {
            UserDefaults.standard.set(newValue, forKey: "hotkeyKey2")
            HotKeyManager.shared.rebind()
        }
    }
}

#Preview {
    HotkeySettingsView()
}
