import SwiftUI

// MARK: - AvatarView (아바타 - 이니셜/이미지/캐릭터)

/// 공급자/에이전트 아바타 표시
/// 크기별 대응, 상태 링 옵션, 캐릭터 이미지 폴백 지원
struct AvatarView: View {
    @Environment(\.theme) private var theme
    let provider: MCPProviderConfiguration?
    let size: CGFloat
    var showStatusRing: Bool = false
    var status: StatusBadge.ConnectionStatus = .unknown
    var customImage: NSImage?
    var characterName: String?

    private var providerColor: Color {
        theme.accentColor
    }

    private var initials: String {
        if let characterName {
            return String(characterName.prefix(1)).uppercased()
        }
        guard let provider = provider else { return "?" }
        let name = provider.displayName
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1)).uppercased() + String(words[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var body: some View {
        ZStack {
            // 배경
            Circle()
                .fill(backgroundFill)

            // 커스텀 이미지 또는 캐릭터
            if let customImage = customImage {
                Image(nsImage: customImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if let characterName = characterName {
                CharacterImageView(name: characterName, size: size)
            } else {
                // 이니셜 텍스트
                Text(initials)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(providerColor)
            }
        }
        .frame(width: size, height: size)
        .overlay(statusRing)
    }

    private var backgroundFill: some ShapeStyle {
        if let provider = provider {
            return providerColor.opacity(0.18)
        }
        return theme.secondaryBackground
    }

    private var fontSize: CGFloat {
        size * 0.45
    }

    @ViewBuilder
    private var statusRing: some View {
        if showStatusRing {
            Circle()
                .stroke(statusColor, lineWidth: 2)
                .frame(width: size + 4, height: size + 4)
        }
    }

    private var statusColor: Color {
        switch status {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .gray
        case .error: return .red
        case .unknown: return .secondary
        }
    }
}

// MARK: - CharacterImageView (캐릭터 이미지 뷰)

/// Assets.xcassets에서 캐릭터 이미지 로드
struct CharacterImageView: View {
    let name: String
    let size: CGFloat

    var body: some View {
        if let nsImage = NSImage(named: "character-\(name.lowercased())") {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            // 폴백: 이니셜
            Circle()
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundStyle(.white)
                )
        }
    }
}

// MARK: - Convenience Initializers

extension AvatarView {
    /// 공급자 아바타
    init(provider: MCPProviderConfiguration?, size: CGFloat = 28, showStatusRing: Bool = false, status: StatusBadge.ConnectionStatus = .unknown) {
        self.provider = provider
        self.size = size
        self.showStatusRing = showStatusRing
        self.status = status
        self.customImage = nil
        self.characterName = nil
    }

    /// 캐릭터 아바타 (마스코트 등)
    init(characterName: String, size: CGFloat = 28) {
        self.provider = nil
        self.size = size
        self.showStatusRing = false
        self.status = .unknown
        self.customImage = nil
        self.characterName = characterName
    }

    /// 커스텀 이미지 아바타
    init(customImage: NSImage, size: CGFloat = 28) {
        self.provider = nil
        self.size = size
        self.showStatusRing = false
        self.status = .unknown
        self.customImage = customImage
        self.characterName = nil
    }
}

// MARK: - Preview

#Preview("AvatarView") {
    HStack(spacing: 16) {
        AvatarView(provider: nil, size: 40, characterName: "mascot")
        AvatarView(provider: nil, size: 40, characterName: "mascot")
        AvatarView(provider: nil, size: 40, showStatusRing: true, status: .connected)
        AvatarView(provider: nil, size: 40, showStatusRing: true, status: .error)
    }
    .padding()
    .environment(\.theme, ThemeBox(LightTheme()))
}