import Foundation
import Combine
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// API 키 저장 전용 고정 UserDefaults 스위트 (v3.6 T-164)
    /// cfprefsd는 앱의 안정적 번들 식별자를 기준으로 `.standard` 도메인을 관리하는데,
    /// ad-hoc 서명은 재빌드/재서명마다 식별자가 달라져 마지막 키 쓰기가 유실됐다.
    /// 명시 스위트(`~/Library/Preferences/com.borasarang.AIModelTalk.prefs.plist`)는
    /// 번들 식별과 무관하게 같은 파일에 기록돼 재빌드에도 키가 유지된다.
    static let apiKeySuiteName = "com.borasarang.AIModelTalk.prefs"
    static let apiKeyDefaults: UserDefaults = {
        guard let suite = UserDefaults(suiteName: apiKeySuiteName) else {
            // 스위트 생성 실패는 치명적 — 즉시 인지 위해 fatalError (개발 중엔 로그만)
            DebugLogger.shared.error("APP", "[E-MAC-STOR-1002] 고정 스위트 생성 실패: \(apiKeySuiteName)")
            return UserDefaults.standard
        }
        return suite
    }()

    @Published var appearance: String {
        didSet {
            UserDefaults.standard.set(appearance, forKey: "appearance")
            applyAppearance()
            // 테마 시스템 브리지 — NSApp 외형과 ThemeManager.currentTheme 동기화 (v0.2.6 축1a)
            let mode: AppearanceMode = appearance == "dark" ? .dark : (appearance == "light" ? .light : .system)
            ThemeManager.shared.syncAppearanceMode(mode)
        }
    }

    // MARK: - API 키 (v3.6 T-164: 고정 스위트 저장)

    @Published var nvidiaAPIKey: String {
        didSet { if !nvidiaAPIKey.isEmpty { AppSettings.apiKeyDefaults.set(nvidiaAPIKey, forKey: "nvidiaAPIKey") } }
    }

    @Published var openRouterAPIKey: String {
        didSet { if !openRouterAPIKey.isEmpty { AppSettings.apiKeyDefaults.set(openRouterAPIKey, forKey: "openRouterAPIKey") } }
    }

    @Published var groqAPIKey: String {
        didSet { if !groqAPIKey.isEmpty { AppSettings.apiKeyDefaults.set(groqAPIKey, forKey: "groqAPIKey") } }
    }

    @Published var geminiAPIKey: String {
        didSet { if !geminiAPIKey.isEmpty { AppSettings.apiKeyDefaults.set(geminiAPIKey, forKey: "geminiAPIKey") } }
    }

    @Published var customAPIKey: String {
        didSet { if !customAPIKey.isEmpty { AppSettings.apiKeyDefaults.set(customAPIKey, forKey: "customAPIKey") } }
    }

    /// v2.1 T-93 — 유료 공급자 4종 (유·무료 통일 취급, PLAN_v2.1 D1)
    @Published var openAIAPIKey: String {
        didSet { if !openAIAPIKey.isEmpty { AppSettings.apiKeyDefaults.set(openAIAPIKey, forKey: "openAIAPIKey") } }
    }

    @Published var anthropicAPIKey: String {
        didSet { if !anthropicAPIKey.isEmpty { AppSettings.apiKeyDefaults.set(anthropicAPIKey, forKey: "anthropicAPIKey") } }
    }

    @Published var vercelGatewayAPIKey: String {
        didSet { if !vercelGatewayAPIKey.isEmpty { AppSettings.apiKeyDefaults.set(vercelGatewayAPIKey, forKey: "vercelGatewayAPIKey") } }
    }

    @Published var tokenRouterAPIKey: String {
        didSet { if !tokenRouterAPIKey.isEmpty { AppSettings.apiKeyDefaults.set(tokenRouterAPIKey, forKey: "tokenRouterAPIKey") } }
    }

    @Published var opencodeAPIKey: String {
        didSet { if !opencodeAPIKey.isEmpty { AppSettings.apiKeyDefaults.set(opencodeAPIKey, forKey: "opencodeAPIKey") } }
    }

    @Published var deepseekAPIKey: String {
        didSet { if !deepseekAPIKey.isEmpty { AppSettings.apiKeyDefaults.set(deepseekAPIKey, forKey: "deepseekAPIKey") } }
    }

    @Published var tavilyAPIKey: String {
        didSet { if !tavilyAPIKey.isEmpty { AppSettings.apiKeyDefaults.set(tavilyAPIKey, forKey: "tavilyAPIKey") } }
    }

    @Published var customBaseURL: String {
        didSet { if !customBaseURL.isEmpty { AppSettings.apiKeyDefaults.set(customBaseURL, forKey: "customBaseURL") } }
    }

    @Published var ollamaBaseURL: String {
        didSet { 
            let cleaned = Self.cleanedOllamaBaseURL(ollamaBaseURL)
            if !cleaned.isEmpty { AppSettings.apiKeyDefaults.set(cleaned, forKey: "ollamaBaseURL") }
        }
    }

    /// 중복 스킴(http://http:, https://https: 등) 또는 끝 슬래시가 붙은 깨진 URL을 정리 (v3.7.2 T-165)
    static func cleanedOllamaBaseURL(_ url: String) -> String {
        var cleaned = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = cleaned.lowercased()
        let badPrefixes = ["http://http", "http://https", "https://http", "https://https"]
        if badPrefixes.contains(where: { lower.hasPrefix($0) }) {
            cleaned = ""
        } else if cleaned.hasSuffix("/") {
            cleaned = String(cleaned.dropLast())
        }
        return cleaned
    }

    /// 웹 검색 사용 (v1.8 T-72)
    @Published var webSearchEnabled: Bool {
        didSet { UserDefaults.standard.set(webSearchEnabled, forKey: "webSearchEnabled") }
    }

    /// 보조 모델 — 기억 추출·제목 생성 등 백그라운드 작업용 경량 모델 (v2.3 T-118)
    /// ""이면 자동 감지(flash→mini 우선). 형식: "providerRaw:modelID"
    @Published var auxiliaryModelSpec: String {
        didSet { UserDefaults.standard.set(auxiliaryModelSpec, forKey: "auxiliaryModelSpec") }
    }

    /// MCP 도구 사용 (v2.4 T-120) — 활성화 시 도구 호출 루프 경로
    @Published var mcpToolsEnabled: Bool {
        didSet { UserDefaults.standard.set(mcpToolsEnabled, forKey: "mcpToolsEnabled") }
    }

    @Published var showJudgeSummary: Bool {
        didSet { UserDefaults.standard.set(showJudgeSummary, forKey: "showJudgeSummary") }
    }

    /// YOLO 모드 (T-204) — 켜면 모든 도구를 자동 승인(사전 확인 없이 실행)
    @Published var yoloMode: Bool {
        didSet { UserDefaults.standard.set(yoloMode, forKey: "yoloMode") }
    }

    /// 에이전트(워크) 모드 (T-204) — 내장 도구(웹검색/페이지읽기/계산기)를 자동 활성화·사용
    @Published var agentMode: Bool {
        didSet { UserDefaults.standard.set(agentMode, forKey: "agentMode") }
    }

    /// 판정 모델 우선 공급자 (T-206) — nil이면 NVIDIA→차순위. provider rawValue 저장.
    @Published var judgeProviderRaw: String? {
        didSet { UserDefaults.standard.set(judgeProviderRaw, forKey: "judgeProviderRaw") }
    }

    /// 합성(synthesis) 활성화 (T-206) — 판정 모델이 여러 후보를 병합한 한 답변 생성
    @Published var showSynthesis: Bool {
        didSet { UserDefaults.standard.set(showSynthesis, forKey: "showSynthesis") }
    }

    @Published var systemPrompt: String {
        didSet { UserDefaults.standard.set(systemPrompt, forKey: "systemPrompt") }
    }

    /// 워크스페이스(로컬 프로젝트) 폴더 경로 (v0.3.0 축3) — nil이면 파일 도구 비활성
    @Published var workspaceFolder: String? {
        didSet { UserDefaults.standard.set(workspaceFolder, forKey: "workspaceFolder") }
    }

    /// 액센트 테마 — 전역 틴트 (v2.0 T-82)
    @Published var accentColor: String {
        didSet {
            UserDefaults.standard.set(accentColor, forKey: "accentColor")
            if accentColor != oldValue {
                DebugLogger.shared.info("APP", "[FEATURE] 액센트 테마 변경됨: \(accentColor)")
            }
        }
    }

    @Published var presentationMode: String {
        didSet { UserDefaults.standard.set(presentationMode, forKey: "presentationMode") }
    }

    @Published var hotkeyModifiers: String {
        didSet {
            UserDefaults.standard.set(hotkeyModifiers, forKey: "hotkeyModifiers")
            HotKeyManager.shared.rebind()
        }
    }

    @Published var hotkeyKey: String {
        didSet {
            UserDefaults.standard.set(hotkeyKey, forKey: "hotkeyKey")
            HotKeyManager.shared.rebind()
        }
    }

    /// Dock 아이콘 표시 여부 (v3.5 T-163) — 기본 false = Dock에 표시하지 않음(.accessory)
    /// 메뉴바 아이콘(MenuBarExtra)으로 모든 기능에 접근 가능하므로 안전하게 숨길 수 있다.
    @Published var showDockIcon: Bool {
        didSet {
            UserDefaults.standard.set(showDockIcon, forKey: "showDockIcon")
            applyDockPolicy()
        }
    }

    init() {
        // 기존 .standard에 남아있던 API 키를 고정 스위트로 1회 이전 (v3.6 T-164)
        Self.migrateLegacyAPIKeysIfNeeded()

        let defaults = UserDefaults.standard
        let apiKeys = AppSettings.apiKeyDefaults
        appearance = defaults.string(forKey: "appearance") ?? "system"
        nvidiaAPIKey = apiKeys.string(forKey: "nvidiaAPIKey") ?? ""
        openRouterAPIKey = apiKeys.string(forKey: "openRouterAPIKey") ?? ""
        groqAPIKey = apiKeys.string(forKey: "groqAPIKey") ?? ""
        geminiAPIKey = apiKeys.string(forKey: "geminiAPIKey") ?? ""
        customAPIKey = apiKeys.string(forKey: "customAPIKey") ?? ""
        openAIAPIKey = apiKeys.string(forKey: "openAIAPIKey") ?? ""
        anthropicAPIKey = apiKeys.string(forKey: "anthropicAPIKey") ?? ""
        vercelGatewayAPIKey = apiKeys.string(forKey: "vercelGatewayAPIKey") ?? ""
        tokenRouterAPIKey = apiKeys.string(forKey: "tokenRouterAPIKey") ?? ""
        opencodeAPIKey = apiKeys.string(forKey: "opencodeAPIKey") ?? ""
        deepseekAPIKey = apiKeys.string(forKey: "deepseekAPIKey") ?? ""
        customBaseURL = apiKeys.string(forKey: "customBaseURL") ?? ""
        ollamaBaseURL = Self.cleanedOllamaBaseURL(apiKeys.string(forKey: "ollamaBaseURL") ?? "")
        webSearchEnabled = defaults.object(forKey: "webSearchEnabled") as? Bool ?? false
        auxiliaryModelSpec = defaults.string(forKey: "auxiliaryModelSpec") ?? ""
        mcpToolsEnabled = defaults.object(forKey: "mcpToolsEnabled") as? Bool ?? false
        tavilyAPIKey = apiKeys.string(forKey: "tavilyAPIKey") ?? ""
        showJudgeSummary = defaults.object(forKey: "showJudgeSummary") as? Bool ?? true
        judgeProviderRaw = defaults.string(forKey: "judgeProviderRaw")
        showSynthesis = defaults.object(forKey: "showSynthesis") as? Bool ?? true
        yoloMode = defaults.object(forKey: "yoloMode") as? Bool ?? false
        agentMode = defaults.object(forKey: "agentMode") as? Bool ?? false
        systemPrompt = defaults.string(forKey: "systemPrompt") ?? "당신은 AI 모델입니다. 한국어로 답변해 주세요."
        workspaceFolder = defaults.string(forKey: "workspaceFolder")
        accentColor = defaults.string(forKey: "accentColor") ?? "system"
        presentationMode = defaults.string(forKey: "presentationMode") ?? "window"
        hotkeyModifiers = defaults.string(forKey: "hotkeyModifiers") ?? "command"
        hotkeyKey = defaults.string(forKey: "hotkeyKey") ?? "i"
        showDockIcon = defaults.object(forKey: "showDockIcon") as? Bool ?? false

        // 자가 치유: 로드된 모든 키를 스위트에 재기록해 빈값/불일치 즉시 정리
        Self.healAPIKeysIfNeeded(apiKeys: self)
    }

    /// 메모리상의 모든 키를 스위트에 재기록해 빈값/불일치 정리 (v3.8.1 T-1008)
    private static func healAPIKeysIfNeeded(apiKeys: AppSettings) {
        let suite = AppSettings.apiKeyDefaults
        var healed = 0
        let keys: [(String, String)] = [
            ("nvidiaAPIKey", apiKeys.nvidiaAPIKey),
            ("openRouterAPIKey", apiKeys.openRouterAPIKey),
            ("groqAPIKey", apiKeys.groqAPIKey),
            ("geminiAPIKey", apiKeys.geminiAPIKey),
            ("customAPIKey", apiKeys.customAPIKey),
            ("openAIAPIKey", apiKeys.openAIAPIKey),
            ("anthropicAPIKey", apiKeys.anthropicAPIKey),
            ("vercelGatewayAPIKey", apiKeys.vercelGatewayAPIKey),
            ("tokenRouterAPIKey", apiKeys.tokenRouterAPIKey),
            ("opencodeAPIKey", apiKeys.opencodeAPIKey),
            ("deepseekAPIKey", apiKeys.deepseekAPIKey),
            ("tavilyAPIKey", apiKeys.tavilyAPIKey),
            ("customBaseURL", apiKeys.customBaseURL),
            ("ollamaBaseURL", apiKeys.ollamaBaseURL),
        ]
        for (key, value) in keys {
            if !value.isEmpty {
                suite.set(value, forKey: key)
                healed += 1
            }
        }
        if healed > 0 {
            suite.synchronize()
            DebugLogger.shared.info("APP", "[FEATURE] API 키 자가 치유: \(healed)개 스위트 재기록")
        }
    }

    /// 기존 `.standard`(번들 도메인)에 남아있는 API 키를 고정 스위트로 이전 (v3.6 T-164)
    /// 매 실행 시 수행. 스위트에 값이 없거나, 빈 문자열, 또는 "test" 접두사 플레이스홀더이면
    /// `.standard`의 실제 값으로 교체.
    private static func migrateLegacyAPIKeysIfNeeded() {
        let legacyKeys = [
            "nvidiaAPIKey", "openRouterAPIKey", "groqAPIKey", "geminiAPIKey",
            "customAPIKey", "customBaseURL", "openAIAPIKey", "anthropicAPIKey",
            "vercelGatewayAPIKey", "tokenRouterAPIKey", "opencodeAPIKey",
            "deepseekAPIKey", "tavilyAPIKey", "ollamaBaseURL",
        ]
        let standard = UserDefaults.standard
        let suite = apiKeyDefaults
        var copied = 0
        for key in legacyKeys {
            if let value = standard.string(forKey: key), !value.isEmpty {
                let suiteValue = suite.string(forKey: key)
                let isPlaceholder = suiteValue == nil
                    || suiteValue!.isEmpty
                    || suiteValue!.hasPrefix("test")
                if isPlaceholder {
                    suite.set(value, forKey: key)
                    copied += 1
                }
            }
        }
        if copied > 0 {
            suite.set(true, forKey: "apiKeysMigratedToSuite")
            standard.set(true, forKey: "apiKeysMigratedToSuite")
            suite.synchronize()
            DebugLogger.shared.info("APP", "[FEATURE] UserDefaults API 키 \(copied)개를 고정 스위트로 이전")
        }
    }

    // API 키는 UserDefaults에만 저장한다 — 키체인 미사용 (v1.9 사용자 결정)
    // 애드혹 서명 앱은 빌드/재설치마다 코드 시그니처가 바뀌어 키체인 접근 시
    // 매번 비밀번호 확인 창이 뜨므로, 로컬 전용 저장으로 되돌렸다.

    static let tavilyStorageKey = "tavilyAPIKey"

    func apiKey(for provider: Provider) -> String {
        switch provider {
        case .nvidia: return nvidiaAPIKey
        case .openRouter: return openRouterAPIKey
        case .groq: return groqAPIKey
        case .gemini: return geminiAPIKey
        case .ollama: return "" // Ollama는 API 키 불필요
        case .appleIntelligence: return "" // Apple Intelligence는 시스템 권한 사용
        case .custom: return customAPIKey
        case .openAI: return openAIAPIKey
        case .anthropic: return anthropicAPIKey
        case .vercelGateway: return vercelGatewayAPIKey
        case .tokenRouter: return tokenRouterAPIKey
        case .opencode: return opencodeAPIKey
        case .deepseek: return deepseekAPIKey
        }
    }

    func setAPIKey(_ key: String, for provider: Provider) {
        // 플레이스홀더/테스트 값 저장 차단 — 실제 API 키만 허용
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.lowercased().hasPrefix("test") else { return }
        switch provider {
        case .nvidia: nvidiaAPIKey = trimmed
        case .openRouter: openRouterAPIKey = trimmed
        case .groq: groqAPIKey = trimmed
        case .gemini: geminiAPIKey = trimmed
        case .ollama: ollamaBaseURL = trimmed // Ollama는 키 대신 BaseURL 저장
        case .appleIntelligence: break // Apple Intelligence는 설정 불필요
        case .custom: customAPIKey = trimmed
        case .openAI: openAIAPIKey = trimmed
        case .anthropic: anthropicAPIKey = trimmed
        case .vercelGateway: vercelGatewayAPIKey = trimmed
        case .tokenRouter: tokenRouterAPIKey = trimmed
        case .opencode: opencodeAPIKey = trimmed
        case .deepseek: deepseekAPIKey = trimmed
        }
        // 강제 동기화 — cfprefsd의 지연 flush에 의존하지 않고 즉시 디스크 기록 (v3.2 T-155)
        // force-quit(강제 종료) 시 미플러시된 UserDefaults 쓰기가 유실되는 문제 방지
        UserDefaults.standard.synchronize()
        // API 키는 고정 스위트에 기록되므로 suite도 즉시 flush (v3.6 T-164)
        AppSettings.apiKeyDefaults.synchronize()
    }

    func applyAppearance() {
        let resolved: NSAppearance?
        switch appearance {
        case "dark":
            resolved = NSAppearance(named: .darkAqua)
        case "light":
            resolved = NSAppearance(named: .aqua)
        default:
            resolved = nil
        }
        NSApp.appearance = resolved
        // 기존에 떠 있는 모든 창에 즉시 반영 — 네이티브 툴바/타이틀바가 라이트로 잔존하는 문제 방지 (v0.3.1)
        // window.appearance를 명시하면 NSApp.appearance 추종 캐시에 의존하지 않고 외형이 강제된다.
        for window in NSApp.windows {
            window.appearance = resolved
        }
        DebugLogger.shared.info("THEME", "[FEATURE] 외형 적용: \(appearance) (창 \(NSApp.windows.count)개 반영)")
    }

    /// Dock 아이콘 표시 정책 적용 (v3.5 T-163) — 런타임 전환
    /// `.regular` = Dock+메뉴바 표시, `.accessory` = Dock 숨김+메뉴바 유지.
    /// 앱 시작 시 저장값 반영과 설정 토글 시 즉시 반영 양쪽에서 호출된다.
    @MainActor
    func applyDockPolicy() {
        let policy: NSApplication.ActivationPolicy = showDockIcon ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // accessory로 전환 시 활성화/포커스가 흔들릴 수 있어 보정 (메뉴바 진입 유지)
        if policy == .accessory {
            NSApp.activate(ignoringOtherApps: true)
        }
        DebugLogger.shared.info("APP", "[FEATURE] Dock 아이콘 표시 정책 변경: \(policy == .regular ? "표시" : "숨김")")
    }

    var colorScheme: ColorScheme? {
        switch appearance {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }
}