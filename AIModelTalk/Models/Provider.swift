import Foundation
import SwiftUI

enum Provider: String, CaseIterable, Identifiable, Codable {
    case appleIntelligence = "Apple Intelligence"
    case ollama = "Ollama"
    case openRouter = "OpenRouter"
    case groq = "Groq"
    case nvidia = "NVIDIA"
    case gemini = "Gemini"
    case openAI = "OpenAI"
    case anthropic = "Anthropic"
    case vercelGateway = "Vercel Gateway"
    case tokenRouter = "TokenRouter"
    case opencode = "OpenCode"
    case deepseek = "DeepSeek"
    case custom = "커스텀"

    var id: String { rawValue }

    var settingsKey: String {
        switch self {
        case .nvidia: return "nvidiaAPIKey"
        case .openRouter: return "openRouterAPIKey"
        case .groq: return "groqAPIKey"
        case .gemini: return "geminiAPIKey"
        case .ollama: return "ollamaBaseURL"
        case .appleIntelligence: return ""
        case .custom: return "customAPIKey"
        case .openAI: return "openAIAPIKey"
        case .anthropic: return "anthropicAPIKey"
        case .vercelGateway: return "vercelGatewayAPIKey"
        case .tokenRouter: return "tokenRouterAPIKey"
        case .opencode: return "opencodeAPIKey"
        case .deepseek: return "deepseekAPIKey"
        }
    }

    var baseURL: String {
        switch self {
        case .nvidia: return "https://integrate.api.nvidia.com/v1"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        case .gemini: return "https://generativelanguage.googleapis.com"
        case .ollama: return "http://localhost:11434"
        case .appleIntelligence: return ""
        case .custom: return ""
        case .openAI: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .vercelGateway: return "https://ai-gateway.vercel.sh/v1"
        case .tokenRouter: return "https://api.tokenrouter.com/v1"
        case .opencode: return "https://opencode.ai/zen/v1"
        case .deepseek: return "https://api.deepseek.com"
        }
    }

    /// OpenAI 호환 클라이언트로 호출 가능 여부 — Anthropic은 전용 Messages API 사용
    var isOpenAICompatible: Bool {
        self != .gemini && self != .appleIntelligence && self != .ollama && self != .anthropic
    }

    var requiresAPIKey: Bool {
        switch self {
        case .openRouter, .groq, .nvidia, .gemini, .custom,
             .openAI, .anthropic, .vercelGateway, .tokenRouter, .opencode, .deepseek:
            return true
        case .ollama, .appleIntelligence:
            return false
        }
    }

    var isAutoDetected: Bool {
        self == .nvidia || self == .ollama
    }

    /// 공급자 설명 (설정 UI 표시용)
    var description: String {
        switch self {
        case .appleIntelligence: return "macOS 26+ 내장"
        case .ollama: return "로컬, 설치 필요"
        case .nvidia: return "무료 티어"
        case .openRouter: return "무료 모델 최다"
        case .groq: return "초고속 추론"
        case .gemini: return "멀티모달"
        case .openAI: return "GPT 공식 API (유료)"
        case .anthropic: return "Claude 공식 API (유료)"
        case .vercelGateway: return "통합 게이트웨이 (유료)"
        case .tokenRouter: return "통합 모델 허브 (유료)"
        case .opencode: return "OpenCode Zen 게이트웨이 (무료/유료 혼합)"
        case .deepseek: return "오픈소스 추론 모델 (유료)"
        case .custom: return "직접 입력"
        }
    }

    /// API 키 발급 페이지 URL (필요한 공급자만)
    var apiKeyURL: String? {
        switch self {
        case .openRouter: return "https://openrouter.ai/keys"
        case .groq: return "https://console.groq.com/keys"
        case .nvidia: return "https://build.nvidia.com/settings/api-keys"
        case .gemini: return "https://aistudio.google.com/apikey"
        case .openAI: return "https://platform.openai.com/api-keys"
        case .anthropic: return "https://console.anthropic.com/settings/keys"
        case .vercelGateway: return "https://vercel.com/docs/ai-gateway"
        case .tokenRouter: return "https://www.tokenrouter.com/console/token"
        case .opencode: return "https://opencode.ai/auth"
        case .deepseek: return "https://platform.deepseek.com"
        default: return nil
        }
    }

    var accentColor: String {
        switch self {
        case .nvidia: return "green"
        case .openRouter: return "blue"
        case .groq: return "orange"
        case .gemini: return "purple"
        case .ollama: return "teal"
        case .appleIntelligence: return "indigo"
        case .custom: return "gray"
        case .openAI: return "openai-green"
        case .anthropic: return "anthropic-clay"
        case .vercelGateway: return "vercel-blue"
        case .tokenRouter: return "tokenrouter-violet"
        case .opencode: return "opencode-cyan"
        case .deepseek: return "deepseek-blue"
        }
    }

    /// SwiftUI 색상 표현 (뷰 계층 공용)
    var accentSwiftUIColor: Color {
        switch accentColor {
        case "green":  return .green
        case "blue":   return .blue
        case "orange": return .orange
        case "purple": return .purple
        case "teal":   return .teal
        case "indigo": return .indigo
        case "openai-green":      return Color(hex: "#10A37F") ?? .green
        case "anthropic-clay":    return Color(hex: "#D97757") ?? .orange
        case "vercel-blue":       return Color(hex: "#0070F3") ?? .blue
        case "tokenrouter-violet": return Color(hex: "#6E56CF") ?? .purple
        case "opencode-cyan":     return Color(hex: "#22D3EE") ?? .cyan
        case "deepseek-blue":     return Color(hex: "#4D6BFE") ?? .blue
        default:       return .gray
        }
    }

    /// API 전송용 모델 ID (v3.2 T-153) — 내부 선택/표시/영속은 프리픽스 포함 ID를 유지하되,
    /// 전송 시점에 공급자가 요구하는 wire 형식으로 변환한다.
    /// OpenCode Zen은 `opencode/big-pickle`이 아니라 `big-pickle`만 허용하므로
    /// OpenAI 호환 요청 body의 model 필드에서 `opencode/` 프리픽스를 제거한다.
    static func wireModelID(_ modelID: String, for provider: Provider) -> String {
        if provider == .opencode, modelID.hasPrefix("opencode/") {
            return String(modelID.dropFirst("opencode/".count))
        }
        return modelID
    }
}
