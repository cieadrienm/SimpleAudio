import AppKit

enum TimelineCursor: String, CaseIterable {
    case arrow
    case ibeam
    case trimLeft
    case trimRight
    case fade
    case slip
    case openHand
    case closedHand
    case resizeLeftRight
    case pointingHand

    static let resizeHorizontal: TimelineCursor = .resizeLeftRight
    static let pointing: TimelineCursor = .pointingHand

    @MainActor var nsCursor: NSCursor { cursor }

    @MainActor var cursor: NSCursor {
        switch self {
        case .arrow: return .arrow
        case .ibeam: return .iBeam
        case .openHand: return .openHand
        case .closedHand: return .closedHand
        case .resizeLeftRight: return .resizeLeftRight
        case .pointingHand: return .pointingHand
        case .trimLeft: return CursorArt.trimLeft
        case .trimRight: return CursorArt.trimRight
        case .fade: return CursorArt.fade
        case .slip: return CursorArt.slip
        }
    }
}

@MainActor
enum CursorArt {
    static let size: CGFloat = 24
    static let hotSpot = NSPoint(x: 12, y: 12)

    static let trimLeft = make(bracket(at: 12.5, facing: .right) + [arrow(from: 10, to: 2.5)], tint: Theme.accent)
    static let trimRight = make(mirrored(bracket(at: 12.5, facing: .right) + [arrow(from: 10, to: 2.5)]), tint: Theme.accent)
    static let fade = make(ramp(), tint: .white)
    static let slip = make(waveformBox() + [arrow(from: 7.5, to: 1.5), arrow(from: 16.5, to: 22.5)], tint: .white)

    struct Stroke {
        var points: [CGPoint]
        var filled = false
    }

    enum Facing { case left, right }

    static func bracket(at x: CGFloat, facing: Facing) -> [Stroke] {
        let s: CGFloat = facing == .right ? 4 : -4
        return [Stroke(points: [
            CGPoint(x: x + s, y: 4.5),
            CGPoint(x: x, y: 4.5),
            CGPoint(x: x, y: 19.5),
            CGPoint(x: x + s, y: 19.5),
        ])]
    }

    static func arrow(from: CGFloat, to tip: CGFloat) -> Stroke {
        let d: CGFloat = tip < from ? 1 : -1
        return Stroke(points: [
            CGPoint(x: from, y: 12),
            CGPoint(x: tip + 4 * d, y: 12),
            CGPoint(x: tip + 4 * d, y: 8.5),
            CGPoint(x: tip, y: 12),
            CGPoint(x: tip + 4 * d, y: 15.5),
            CGPoint(x: tip + 4 * d, y: 12),
        ], filled: true)
    }

    static func waveformBox() -> [Stroke] {
        [
            Stroke(points: [CGPoint(x: 8.5, y: 6.5), CGPoint(x: 15.5, y: 6.5), CGPoint(x: 15.5, y: 17.5), CGPoint(x: 8.5, y: 17.5), CGPoint(x: 8.5, y: 6.5)]),
            Stroke(points: [CGPoint(x: 10.5, y: 9.0), CGPoint(x: 10.5, y: 15.0)]),
            Stroke(points: [CGPoint(x: 12.0, y: 7.5), CGPoint(x: 12.0, y: 16.5)]),
            Stroke(points: [CGPoint(x: 13.5, y: 9.5), CGPoint(x: 13.5, y: 14.5)]),
        ]
    }

    static func ramp() -> [Stroke] {
        [
            Stroke(points: [CGPoint(x: 3.5, y: 19.5), CGPoint(x: 20.5, y: 4.5)]),
            Stroke(points: [CGPoint(x: 3.5, y: 19.5), CGPoint(x: 20.5, y: 19.5)]),
            Stroke(points: [
                CGPoint(x: 9.5, y: 9.5),
                CGPoint(x: 14.5, y: 9.5),
                CGPoint(x: 14.5, y: 14.5),
                CGPoint(x: 9.5, y: 14.5),
            ], filled: true),
        ]
    }

    static func mirrored(_ strokes: [Stroke]) -> [Stroke] {
        strokes.map { Stroke(points: $0.points.map { CGPoint(x: size - $0.x, y: $0.y) }, filled: $0.filled) }
    }

    static func make(_ strokes: [Stroke], tint: NSColor) -> NSCursor {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            for pass in 0..<2 {
                let color = pass == 0 ? NSColor.black : tint
                color.setStroke()
                color.setFill()
                for stroke in strokes {
                    let path = NSBezierPath()
                    path.move(to: stroke.points[0])
                    for p in stroke.points.dropFirst() { path.line(to: p) }
                    if stroke.filled { path.close() }
                    path.lineWidth = pass == 0 ? 3 : 1
                    path.lineCapStyle = .square
                    path.lineJoinStyle = .miter
                    if stroke.filled { path.fill() }
                    path.stroke()
                }
            }
            return true
        }
        return NSCursor(image: image, hotSpot: hotSpot)
    }
}
