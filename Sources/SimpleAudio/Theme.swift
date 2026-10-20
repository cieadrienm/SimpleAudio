import AppKit
import SwiftUI

/// Dark palette shared by the AppKit timeline and the SwiftUI chrome. Same visual family as Montage and OSCScore.
enum Theme {
    static let background = NSColor(hex: 0x111317)
    static let panel = NSColor(hex: 0x16191E)
    static let lane = NSColor(hex: 0x181B21)
    static let laneAlt = NSColor(hex: 0x1B1F26)
    static let laneSelected = NSColor(hex: 0x1F2530)
    static let header = NSColor(hex: 0x14171C)
    static let ruler = NSColor(hex: 0x14171C)
    static let overview = NSColor(hex: 0x12151A)
    static let separator = NSColor(hex: 0x0B0C0F)
    static let gridMinor = NSColor(white: 1, alpha: 0.035)
    static let gridMajor = NSColor(white: 1, alpha: 0.085)
    static let zeroLine = NSColor(white: 1, alpha: 0.09)
    static let text = NSColor(hex: 0xE6E8EC)
    static let textDim = NSColor(hex: 0x8A919E)
    static let textFaint = NSColor(hex: 0x565D6A)
    static let accent = NSColor(hex: 0xFFB454)
    static let playhead = NSColor(hex: 0xFF5C57)
    static let snapGuide = NSColor(hex: 0x5CE1E6)
    static let rangeSelection = NSColor(hex: 0x5CE1E6)
    static let selection = NSColor.white
    static let muteColor = NSColor(hex: 0x7AA2F7)
    static let soloColor = NSColor(hex: 0xFFB454)
    static let meterLow = NSColor(hex: 0x9ECE6A)
    static let meterMid = NSColor(hex: 0xFFB454)
    static let meterHigh = NSColor(hex: 0xFF5C57)
    static let meterSafe = meterLow
    static let meterWarm = meterMid
    static let meterHot = meterHigh
    static let fade = NSColor(white: 0, alpha: 0.38)

    static let trackColors: [NSColor] = [
        0xFFB454, 0x5CE1E6, 0x9ECE6A, 0x7AA2F7,
        0xC792EA, 0xFF7A90, 0xF2D96B, 0x6EE7B7,
    ].map { NSColor(hex: $0) }

    static var palette: [NSColor] { trackColors }

    static func trackColor(_ index: Int) -> NSColor {
        trackColors[((index % trackColors.count) + trackColors.count) % trackColors.count]
    }

    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    static func code(_ size: CGFloat) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

extension NSColor {
    convenience init(hex: Int, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat(hex >> 16 & 0xff) / 255,
            green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }

    var swiftUI: Color { Color(nsColor: self) }
}

enum TimeFormat {
    /// `m:ss.mmm` (milliseconds for precise audio editing), or `h:mm:ss.mmm` past the hour.
    static func timecode(_ seconds: Double) -> String {
        let total = max(0, seconds.isFinite ? seconds : 0)
        let millis = Int((total * 1000).rounded())
        let h = millis / 3_600_000
        let m = (millis / 60_000) % 60
        let s = (millis / 1000) % 60
        let ms = millis % 1000
        return h > 0
            ? String(format: "%d:%02d:%02d.%03d", h, m, s, ms)
            : String(format: "%d:%02d.%03d", m, s, ms)
    }

    /// Short timecode `m:ss.cc` for compact badges and pills.
    static func shortTimecode(_ seconds: Double) -> String {
        let total = max(0, seconds.isFinite ? seconds : 0)
        let centis = Int((total * 100).rounded(.down))
        let m = centis / 6000
        let s = (centis / 100) % 60
        let c = centis % 100
        return String(format: "%d:%02d.%02d", m, s, c)
    }

    /// Ruler label: as short as the step allows.
    static func rulerLabel(_ seconds: Double, step: Double) -> String {
        let total = max(0, seconds)
        let m = Int(total) / 60
        let s = total - Double(m * 60)
        if step >= 1 { return String(format: "%d:%02d", m, Int(s.rounded())) }
        return String(format: step >= 0.1 ? "%d:%04.1f" : "%d:%05.2f", m, s)
    }

    static func seconds(_ v: Double) -> String {
        String(format: abs(v) >= 10 ? "%.2f" : "%.3f", v)
    }

    static func shortDuration(_ seconds: Double) -> String {
        let s = max(0, seconds)
        if s < 10 { return String(format: "%.2f s", s) }
        if s < 60 { return String(format: "%.1f s", s) }
        return shortTimecode(s)
    }

    static func decibels(_ db: Double) -> String {
        if db <= -60 { return "−∞ dB" }
        let sign = db > 0.05 ? "+" : ""
        return String(format: "%@%.1f dB", sign, db)
    }

    static func pan(_ p: Double) -> String {
        let pct = Int((p * 100).rounded())
        if abs(pct) <= 1 { return "C" }
        return pct < 0 ? "\(-pct)L" : "\(pct)R"
    }
}
