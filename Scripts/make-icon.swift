// Draws the SimpleAudio app icon and writes Resources/AppIcon.icns. Usage: swift Scripts/make-icon.swift
import AppKit

func color(_ hex: Int, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

func drawIcon(size: Int) -> Data {
    let s = CGFloat(size) / 1024
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.scaleBy(x: s, y: s)

    // macOS icon grid: 824 pt rounded square centered in 1024
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * s), blur: 28 * s, color: color(0x000000, 0.48))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x14171C))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    let bg = CGGradient(
        colorsSpace: space,
        colors: [color(0x222731), color(0x0E1014)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])

    // Center zero line
    ctx.setFillColor(color(0xFFFFFF, 0.10))
    ctx.fill(CGRect(x: 160, y: 510, width: 704, height: 4))

    // Stylised symmetric waveform bars with S-curve fade-in and fade-out
    let barCount = 29
    let startX: CGFloat = 188
    let endX: CGFloat = 836
    let stepX = (endX - startX) / CGFloat(barCount - 1)
    let barWidth: CGFloat = 13

    for i in 0..<barCount {
        let u = Double(i) / Double(barCount - 1)
        let fadeEnv = sin(.pi * u)
        let mod = 0.52 + 0.48 * abs(sin(Double(i) * 0.72) * cos(Double(i) * 0.37))
        let h = max(24, CGFloat(fadeEnv * mod) * 250)
        let bx = startX + CGFloat(i) * stepX - barWidth / 2
        let barRect = CGRect(x: bx, y: 512 - h, width: barWidth, height: h * 2)
        ctx.addPath(CGPath(roundedRect: barRect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        let isPastPlayhead = bx > 580
        ctx.setFillColor(isPastPlayhead ? color(0x5CE1E6, 0.85) : color(0xFFB454, 0.94))
        ctx.fillPath()
    }

    // Playhead line + head
    let playX: CGFloat = 586
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 32 * s, color: color(0xFF5C57, 0.55))
    ctx.setFillColor(color(0xFF5C57))
    ctx.addPath(CGPath(roundedRect: CGRect(x: playX - 10, y: 230, width: 20, height: 550), cornerWidth: 10, cornerHeight: 10, transform: nil))
    ctx.fillPath()
    let head = CGMutablePath()
    head.move(to: CGPoint(x: playX - 46, y: 810))
    head.addLine(to: CGPoint(x: playX + 46, y: 810))
    head.addLine(to: CGPoint(x: playX, y: 740))
    head.closeSubpath()
    ctx.addPath(head)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.restoreGState()

    // Subtle rim
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 2, dy: 2), cornerWidth: 184, cornerHeight: 184, transform: nil))
    ctx.setStrokeColor(color(0xFFFFFF, 0.11))
    ctx.setLineWidth(4)
    ctx.strokePath()

    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let resDir = root.appendingPathComponent("Resources", isDirectory: true)
try FileManager.default.createDirectory(at: resDir, withIntermediateDirectories: true)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("SimpleAudio-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try drawIcon(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try drawIcon(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try drawIcon(size: 1024).write(to: resDir.appendingPathComponent("AppIcon.png"))
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resDir.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "Resources/AppIcon.icns written" : "iconutil failed")
