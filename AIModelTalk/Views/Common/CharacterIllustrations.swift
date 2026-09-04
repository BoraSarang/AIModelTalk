import SwiftUI

// MARK: - CharacterIllustrations (마스코트 캐릭터 에셋 관리)

/// Osaurus 스타일 마스코트 캐릭터 에셋 상수 관리
/// Assets.xcassets에 PDF 벡터로 추가된 캐릭터 이미지들 참조
enum CharacterIllustrations {

    // MARK: - Character Enum

    enum Character: String, CaseIterable {
        // 메인 마스코트
        case mascot = "character-mascot"           // 메인 마스코트 (온보딩 환영)
        case wave = "character-wave"               // 손 흔들기 (환영)

        // 상태별
        case empty = "character-empty"             // 빈 상태
        case thinking = "character-thinking"       // 생각 중/로딩
        case success = "character-success"         // 성공
        case error = "character-error"             // 에러
        case warning = "character-warning"         // 경고
        case info = "character-info"               // 정보

        // 소형
        case small = "character-small"             // 사이드바 장식 (64×64)

        // 자산 이름 (Assets.xcassets에서 실제 이름)
        var assetName: String { rawValue }

        // 표시용 이름
        var displayName: String {
            switch self {
            case .mascot: return "마스코트"
            case .wave: return "환영"
            case .empty: return "빈 상태"
            case .thinking: return "생각 중"
            case .success: return "성공"
            case .error: return "에러"
            case .warning: return "경고"
            case .info: return "정보"
            case .small: return "소형"
            }
        }
    }

    // MARK: - Asset Guidelines

    /// Assets.xcassets 추가 가이드:
    ///
    /// 1. 모든 이미지를 **PDF 벡터**로 준비 (크기 무관하게 선명)
    /// 2. Assets.xcassets에서 각 이미지 선택 후 **"Preserve Vector Data" 체크**
    /// 3. 색상 프로파일: sRGB
    /// 4. 배경 투명 (알파 채널 포함)
    ///
    /// 권장 크기 (벡터이므로 렌더링 시 크기 무관):
    /// - mascot, wave, empty, thinking, success, error, warning, info: 400×400pt (아트보드)
    /// - small: 64×64pt
    ///
    /// 색상 팔레트 (테마 accentColor 기반):
    /// - Primary: accentColor (라이트: #1a1a18, 다크: #f5f5f0)
    /// - Secondary: accentColorLight
    /// - Accent: 성공(#15803d/#4ade80), 경고(#a16207/#fbbf24), 에러(#dc2626/#f87171)
    ///
    /// 캐릭터 디자인 프롬프트 예시 (AI 이미지 생성용):
    ///
    /// 메인 마스코트 (character-mascot):
    /// "친근한 공룡 캐릭터, 따뜻한 보라/핑크 그라데이션 배경, 벡터 아트 스타일, 플랫 디자인, 큰 눈, 미소, 양손을 살짝 벌린 자세, 부드러운 라운드 실루엣"
    ///
    /// 환영 (character-wave):
    /// "같은 공룡 캐릭터, 오른손을 흔들며 인사, 따뜻한 보라/핑크 그라데이션, 동적인 포즈, 움직임 느낌"
    ///
    /// 빈 상태 (character-empty):
    /// "같은 공룡 캐릭터, 앉아서 턱을 괴고 생각 중, 연한 회색 배경, 미니멀, 차분한 분위기"
    ///
    /// 생각 중 (character-thinking):
    /// "공룡이 머리를 긁적이며 고민, 작은 생각 구름(물음표/전구), 애니메이션 루프용 3프레임 제안"
    ///
    /// 성공 (character-success):
    /// "공룡이 엄지 척, 녹색 체크마크, 연한 녹색 액센트, 밝은 표정"
    ///
    /// 에러 (character-error):
    /// "공룡이 당황한 표정(땀/당황), 붉은 액센트, 부드러운 표현(무섭지 않게)"
    ///
    /// 경고 (character-warning):
    /// "공룡이 주의 표지판 들고 있음, 주황/노란 액센트"
    ///
    /// 정보 (character-info):
    /// "공룡이 정보 아이콘(i) 가리키며 설명, 파란 액센트"
    ///
    /// 소형 (character-small):
    /// "작은 실루엣, 64×64, 섹션 헤더 옆 장식용, 단순화된 형태"

    // MARK: - View Helpers

    /// 캐릭터 이미지 뷰 (Assets에서 로드, SF Symbol 폴백)
    struct CharacterImage: View {
        @Environment(\.theme) private var theme
        let character: Character
        let size: CGFloat

        var body: some View {
            if let nsImage = NSImage(named: character.assetName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                // 폴백: SF Symbol + 테마 배경
                Image(systemName: sfSymbolName)
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(theme.accentColor)
                    .frame(width: size, height: size)
                    .background(theme.accentColor.opacity(0.1))
                    .clipShape(Circle())
            }
        }

        private var sfSymbolName: String {
            switch character {
            case .mascot, .wave: return "face.smiling"
            case .empty: return "bubble.left.and.bubble.right"
            case .thinking: return "brain"
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.triangle.fill"
            case .warning: return "exclamationmark.circle.fill"
            case .info: return "info.circle.fill"
            case .small: return "bubble.left"
            }
        }
    }

    /// 캐릭터 + 텍스트 조합 뷰
    struct CharacterWithText: View {
        @Environment(\.theme) private var theme
        let character: Character
        let title: String
        let message: String
        let size: CGFloat

        var body: some View {
            VStack(spacing: 12) {
                CharacterImage(character: character, size: size)
                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondaryText)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("CharacterIllustrations") {
    ScrollView {
        VStack(spacing: 20) {
            ForEach(CharacterIllustrations.Character.allCases, id: \.self) { char in
                VStack(spacing: 8) {
                    CharacterIllustrations.CharacterImage(character: char, size: 80)
                    Text(char.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .environment(\.theme, ThemeBox(LightTheme()))
    }
}