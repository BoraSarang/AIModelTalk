// 앱 아이콘 생성기 — 보라 그라디언트 스쿼클 + 흰 대화 버블 + AI 스파크 (T-50)
// 사용법: swift Scripts/make_app_icon.swift <출력.png 경로>

import AppKit

let S: CGFloat = 1024

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(S), pixelsHigh: Int(S),
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
)!
rep.size = NSSize(width: S, height: S)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("컨텍스트 생성 실패") }

// MARK: 배경 스쿼클 + 그림자
let inset: CGFloat = 100
let bgRect = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
let radius: CGFloat = bgRect.width * 0.224
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: radius, yRadius: radius)

NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = 42
shadow.shadowOffset = NSSize(width: 0, height: -20)
shadow.set()
bgPath.fill()
NSGraphicsContext.current?.restoreGraphicsState()

// 브랜드 그라디언트 (3-stop — 밴딩 방지)
if let grad = NSGradient(colors: [
    NSColor(calibratedRed: 0.64, green: 0.28, blue: 0.88, alpha: 1), // 하단 딥 퍼플
    NSColor(calibratedRed: 0.58, green: 0.34, blue: 0.95, alpha: 1), // 중간
    NSColor(calibratedRed: 0.50, green: 0.40, blue: 1.00, alpha: 1), // 상단 바이올렛
]) {
    grad.draw(in: bgPath, angle: 65)
}

// 상단 글래스 광택
if let sheen = NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.16),
    NSColor.white.withAlphaComponent(0.0),
]) {
    ctx.saveGState()
    bgPath.addClip()
    sheen.draw(in: CGRect(x: bgRect.minX, y: bgRect.midY, width: bgRect.width, height: bgRect.height * 0.5), angle: 90)
    ctx.restoreGState()
}

// MARK: 대화 버블 — 본체+꼬리 단일 패스 (그림자 이음새 없음, 끝은 베지어로 소프트 마감)
func chatBubble(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, r: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    // 좌상단에서 시계방향
    p.move(to: NSPoint(x: x, y: y + h - r))
    p.appendArc(withCenter: NSPoint(x: x + r, y: y + h - r), radius: r, startAngle: 180, endAngle: 90, clockwise: true)
    p.line(to: NSPoint(x: x + w - r, y: y + h))
    p.appendArc(withCenter: NSPoint(x: x + w - r, y: y + h - r), radius: r, startAngle: 90, endAngle: 0, clockwise: true)
    p.line(to: NSPoint(x: x + w, y: y + r))
    p.appendArc(withCenter: NSPoint(x: x + w - r, y: y + r), radius: r, startAngle: 0, endAngle: 270, clockwise: true)
    // 하단 변 → 꼬리(좌하단 스우시) → 복귀
    p.line(to: NSPoint(x: x + 176, y: y))
    p.curve(to: NSPoint(x: x + 64, y: y - 116),
            controlPoint1: NSPoint(x: x + 144, y: y - 8),
            controlPoint2: NSPoint(x: x + 96, y: y - 54))
    p.curve(to: NSPoint(x: x + 120, y: y),
            controlPoint1: NSPoint(x: x + 46, y: y - 84),
            controlPoint2: NSPoint(x: x + 80, y: y - 20))
    p.line(to: NSPoint(x: x + r, y: y))
    p.appendArc(withCenter: NSPoint(x: x + r, y: y + r), radius: r, startAngle: 270, endAngle: 180, clockwise: true)
    p.close()
    return p
}

let bubblePath = chatBubble(x: 292, y: 392, w: 456, h: 308, r: 100)

NSGraphicsContext.current?.saveGraphicsState()
let bShadow = NSShadow()
bShadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
bShadow.shadowBlurRadius = 28
bShadow.shadowOffset = NSSize(width: 0, height: -10)
bShadow.set()
NSColor.white.setFill()
bubblePath.fill()
NSGraphicsContext.current?.restoreGraphicsState()

// MARK: AI 스파크 (곡선 4포인트 별)
func sparkle(_ cx: CGFloat, _ cy: CGFloat, _ R: CGFloat, _ color: NSColor) {
    let p = NSBezierPath()
    let k = R * 0.15
    func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: y) }
    p.move(to: pt(cx, cy + R))
    p.curve(to: pt(cx + R, cy), controlPoint1: pt(cx + k, cy + k), controlPoint2: pt(cx + k, cy + k))
    p.curve(to: pt(cx, cy - R), controlPoint1: pt(cx + k, cy - k), controlPoint2: pt(cx + k, cy - k))
    p.curve(to: pt(cx - R, cy), controlPoint1: pt(cx - k, cy - k), controlPoint2: pt(cx - k, cy - k))
    p.curve(to: pt(cx, cy + R), controlPoint1: pt(cx - k, cy + k), controlPoint2: pt(cx - k, cy + k))
    p.close()
    color.setFill()
    p.fill()
}

sparkle(494, 554, 122, NSColor(calibratedRed: 0.48, green: 0.36, blue: 1.00, alpha: 1)) // 메인 스파크
sparkle(652, 452, 56,  NSColor(calibratedRed: 0.56, green: 0.46, blue: 0.98, alpha: 1)) // 보조 스파크

// MARK: 내보내기
NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG 인코딩 실패") }
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
try! png.write(to: URL(fileURLWithPath: outPath))
print("아이콘 생성 완료: \(outPath)")
