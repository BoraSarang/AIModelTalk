import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general = "일반"
    case providers = "공급자"
    case models = "모델"
    case mcp = "MCP"
    case skills = "스킬"
    case memory = "메모리"
    case hotkey = "단축키"

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .providers: return "key.fill"
        case .models: return "cpu"
        case .mcp: return "externaldrive"
        case .skills: return "sparkles"
        case .memory: return "brain"
        case .hotkey: return "keyboard"
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            tab(.general) { GeneralSettingsView() }
            tab(.providers) { ProvidersSettingsView() }
            tab(.models) { ModelsSettingsView() }
            tab(.mcp) { MCPSettingsView() }
            tab(.skills) { SkillSettingsView() }
            tab(.memory) { MemorySettingsView() }
            tab(.hotkey) { HotkeySettingsView() }
        }
        .frame(minWidth: 700, minHeight: 480)
        .padding(0)
    }

    private func tab<Content: View>(_ tab: SettingsTab, @ViewBuilder content: @escaping () -> Content) -> some View {
        content()
            .tabItem {
                Label(tab.rawValue, systemImage: tab.icon)
            }
            .tag(tab)
    }
}

#Preview {
    SettingsView()
}
