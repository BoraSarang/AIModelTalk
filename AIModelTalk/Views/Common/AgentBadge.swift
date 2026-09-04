import SwiftUI

// MARK: - AgentBadge (공급자·모델 배지)

/// 채팅 말풍선 상단에 표시되는 공급자/모델 배지
/// 테마 컬러 적용, 크기 조절 가능
struct AgentBadge: View {
    @Environment(\.theme) private var theme
    let provider: Provider?
    let modelID: String?
    var size: CGFloat = 13
    var color: Color?
    var showIcon: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            if showIcon, let provider = provider {
                Image(systemName: provider.systemImage)
                    .font(.system(size: size * 0.8, weight: .medium))
                    .foregroundStyle(badgeColor)
            }

            Text(displayText)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(badgeColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(badgeColor.opacity(0.15))
        .clipShape(Capsule())
    }

    private var badgeColor: Color {
        color ?? providerColor ?? theme.accentColor
    }

    private var providerColor: Color? {
        provider?.accentSwiftUIColor
    }

    private var displayText: String {
        if let provider = provider, let modelID = modelID {
            return ModelCatalog.label(for: provider, modelID: modelID)
        } else if let provider = provider {
            return provider.displayName
        } else {
            return "AI"
        }
    }
}

// MARK: - Provider Extension (시스템 이미지/색상)

extension Provider {
    var systemImage: String {
        switch self {
        case .openAI: return "brain.head.profile"
        case .anthropic: return "sparkles"
        case .gemini: return "globe"
        case .appleIntelligence: return "apple.logo"
        case .ollama: return "server.rack"
        case .custom: return "gearshape"
        case .openRouter: return "link"
        case .nvidia: return "bolt.fill"
        case .groq: return "bolt.fill"
        case .vercelGateway: return "triangle.fill"
        case .tokenRouter: return "arrow.triangle.2.circlepath"
        case .opencode: return "chevron.left.forwardslash.chevron.right"
        case .deepseek: return "waveform"
        }
    }

    var displayName: String {
        rawValue
    }
}

// MARK: - InlineModelBadge (채팅 메시지 내 인라인 모델 배지)

/// 스트리밍 중인 메시지에 표시되는 작은 모델 표시
struct InlineModelBadge: View {
    @Environment(\.theme) private var theme
    let provider: Provider
    let modelName: String
    var isStreaming: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: provider.systemImage)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(provider.accentSwiftUIColor)

            Text(modelName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)

            if isStreaming {
                StreamingDots()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(provider.accentSwiftUIColor.opacity(0.12))
                .overlay(
                    Capsule()
                        .stroke(provider.accentSwiftUIColor.opacity(0.3), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - StreamingDots (스트리밍 인디케이터)

struct StreamingDots: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 4, height: 4)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

// MARK: - Preview

#Preview("AgentBadge") {
    HStack(spacing: 12) {
        AgentBadge(provider: .openAI, modelID: "gpt-4o")
        AgentBadge(provider: .anthropic, modelID: "claude-3-5-sonnet")
        AgentBadge(provider: .appleIntelligence, modelID: "foundation")
        AgentBadge(provider: .ollama, modelID: "llama3")
    }
    .padding()
    .environment(\.theme, ThemeBox(LightTheme()))
}

#Preview("InlineModelBadge") {
    HStack(spacing: 12) {
        InlineModelBadge(provider: .openAI, modelName: "GPT-4o", isStreaming: true)
        InlineModelBadge(provider: .anthropic, modelName: "Claude 3.5 Sonnet")
    }
    .padding()
    .environment(\.theme, ThemeBox(LightTheme()))
}