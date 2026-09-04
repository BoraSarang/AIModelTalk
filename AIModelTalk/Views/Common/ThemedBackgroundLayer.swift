import SwiftUI

// MARK: - ThemedBackgroundLayer (Osaurus 스타일 테마 배경 레이어)

/// 채팅창/설정창/사이드바 등에서 사용하는 공통 배경 레이어
/// 솔리드/그라디언트/이미지 + 오버레이 지원
/// Osaurus의 Common.ThemedBackgroundLayer 참고
struct ThemedBackgroundLayer: View {
    let cachedBackgroundImage: NSImage?
    let showSidebar: Bool
    var isFullScreen: Bool = false

    @Environment(\.theme) private var theme

    var body: some View {
        backgroundLayer
            .clipShape(backgroundShape)
    }

    private var backgroundShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: (showSidebar || isFullScreen) ? 0 : theme.cardCornerRadius + 6,
            bottomLeadingRadius: (showSidebar || isFullScreen) ? 0 : theme.cardCornerRadius + 6,
            bottomTrailingRadius: isFullScreen ? 0 : theme.cardCornerRadius + 6,
            topTrailingRadius: isFullScreen ? 0 : theme.cardCornerRadius + 6,
            style: .continuous
        )
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if let customTheme = theme.customThemeConfig {
            switch customTheme.background.type {
            case .solid:
                Color(hex: customTheme.background.solidColor ?? theme.primaryBackground.hexString ?? "#ffffff")

            case .gradient:
                let colors = (customTheme.background.gradientColors ?? ["#000000", "#333333"])
                    .map { Color(hex: $0) }
                LinearGradient(
                    colors: colors,
                    startPoint: .top,
                    endPoint: .bottom
                )

            case .image:
                if let image = cachedBackgroundImage {
                    let imgConfig = customTheme.background.imageConfig
                    ZStack {
                        backgroundImageView(
                            image: image,
                            fit: imgConfig?.imageFit ?? .fill,
                            opacity: imgConfig?.imageOpacity ?? 1.0
                        )

                        if let overlayHex = imgConfig?.overlayColor {
                            Color(hex: overlayHex)
                                .opacity(imgConfig?.overlayOpacity ?? 0.5)
                        }
                    }
                } else {
                    Color(hex: customTheme.primaryBackgroundHex ?? "#ffffff")
                }
            }
        } else {
            theme.primaryBackground
        }
    }

    private func backgroundImageView(image: NSImage, fit: ThemeBackgroundImage.ImageFit, opacity: Double) -> some View {
        GeometryReader { geo in
            switch fit {
            case .fill:
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(opacity)
            case .fit:
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(opacity)
            case .stretch:
                Image(nsImage: image)
                    .resizable()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(opacity)
            case .tile:
                TiledImageView(image: image)
                    .opacity(opacity)
            }
        }
    }

    private struct TiledImageView: NSViewRepresentable {
        let image: NSImage

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            view.wantsLayer = true
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            nsView.layer?.backgroundColor = NSColor(patternImage: image).cgColor
        }
    }
}

// MARK: - Color Extension for hexString

extension Color {
    var hexString: String? {
        // NSColor로 변환 후 hex 추출
        let nsColor = NSColor(self)
        guard let rgbColor = nsColor.usingColorSpace(.sRGB) else { return nil }
        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}