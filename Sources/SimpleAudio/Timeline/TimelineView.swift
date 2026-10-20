import AppKit
import Observation
import SimpleAudioCore
import SimpleAudioEngine

final class TimelineView: NSView {
    enum Metrics {
        static let headerWidth: CGFloat = 172
        static let overviewHeight: CGFloat = 28
        static let rulerHeight: CGFloat = 24
        static let topBarHeight: CGFloat = overviewHeight + rulerHeight
        static let laneGap: CGFloat = 1
        static let leadIn: CGFloat = 10
        static let endMargin: CGFloat = 48
        static let blockInset: CGFloat = 3
        static let edgeInside: CGFloat = 8
        static let edgeOutside: CGFloat = 4
        static let fadeHandle: CGFloat = 6.5
        static let fadeHit: CGFloat = 11
        static let rangeHandleHit: CGFloat = 7
        static let dragThreshold: CGFloat = 3
        static let snapPoints: CGFloat = 8
        static let minSecondsPerPoint: Double = 1.0 / 4000.0
    }

    enum Edge: Equatable {
        case start
        case end
    }

    enum HeaderControl: Equatable {
        case mute(UUID)
        case solo(UUID)
        case stereoSplit(UUID)
        case gain(UUID)
        case pan(UUID)
        case title(UUID)
    }

    enum Drag {
        case none
        case scrub
        case overviewPan(grabOffset: Double)
        case rangeSelect(originTime: Double, trackID: UUID?)
        case rangeEdge(edge: Edge, otherBound: Double)
        case press(clipID: UUID, trackID: UUID, start: CGPoint, grab: Double, slip: Bool)
        case move(clipID: UUID, grab: Double, originalOffset: Double, originalTrackID: UUID, current: CGPoint)
        case slip(clipID: UUID, grab: Double, original: AudioClip)
        case trim(clipID: UUID, edge: Edge, grab: Double, original: AudioClip)
        case fade(clipID: UUID, isIn: Bool, grab: Double, original: AudioClip)
        case trackGain(trackID: UUID, startY: CGFloat, originalDB: Double)
        case trackPan(trackID: UUID, startX: CGFloat, originalPan: Double)
        case marker(markerID: UUID, grab: Double, originalTime: Double)
    }

    struct TrackRow {
        var index: Int
        var track: AudioTrack
        var rect: CGRect
    }

    unowned let model: AppModel

    var secondsPerPoint: Double = 0.02 { didSet { needsDisplay = true } }
    var scrollOffset: Double = 0 { didSet { needsDisplay = true } }
    var verticalScroll: CGFloat = 0 { didSet { needsDisplay = true } }

    var drag: Drag = .none
    var preview: AudioProject?
    var pendingEdit: ((inout AudioProject) -> Void)?
    var pendingLabel = ""
    var snapGuide: Double?
    var hoveredClip: UUID?
    var hoverHit: Hit?
    var lastMouse: CGPoint?
    var currentCursor: TimelineCursor = .arrow
    var debugCursorName: String { currentCursor.rawValue }

    let playheadView = TimelinePlayheadView()
    let tipView = TimelineTipView()
    private var hoverTracking: NSTrackingArea?
    private var didInitialFit = false
    private var fittedURL: URL?
    private var lastChangeCount = -1
    private var zoomTimer: Timer?
    private var zoomAnimation: (fromSPP: Double, toSPP: Double, fromOffset: Double, toOffset: Double, start: CFTimeInterval, duration: CFTimeInterval)?

    init(model: AppModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        addSubview(playheadView)
        tipView.isHidden = true
        addSubview(tipView)

        lastChangeCount = model.store.changeCount
        fittedURL = model.store.url
        observeModel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func layout() {
        super.layout()
        if !didInitialFit, laneWidth > 80 {
            didInitialFit = true
            fit()
        }
        clampScroll()
        updatePlayhead()
    }

    // MARK: Model Observation

    var project: AudioProject { preview ?? model.store.project }

    private func observeModel() {
        withObservationTracking {
            _ = model.store.changeCount
            _ = model.store.url
            _ = model.selectedClips
            _ = model.selectedTrackID
            _ = model.selectedMarkerID
            _ = model.selectionRange
            _ = model.snapping
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.modelChanged()
                self?.observeModel()
            }
        }
    }

    func modelChanged() {
        let store = model.store
        if store.changeCount != lastChangeCount {
            lastChangeCount = store.changeCount
            if store.url != fittedURL {
                fittedURL = store.url
                if didInitialFit { fit() }
            }
        }
        clampScroll()
        refresh()
    }

    var contentDuration: Double {
        max(project.totalDuration, 1.0)
    }

    // MARK: Geometry

    var laneWidth: CGFloat { max(bounds.width - Metrics.headerWidth, 0) }

    var overviewArea: CGRect {
        CGRect(x: Metrics.headerWidth, y: 0, width: laneWidth, height: Metrics.overviewHeight - 1)
    }

    var rulerArea: CGRect {
        CGRect(x: Metrics.headerWidth, y: Metrics.overviewHeight, width: laneWidth, height: Metrics.rulerHeight - 1)
    }

    var laneArea: CGRect {
        CGRect(
            x: Metrics.headerWidth,
            y: Metrics.topBarHeight,
            width: laneWidth,
            height: max(bounds.height - Metrics.topBarHeight, 0)
        )
    }

    func x(for time: Double) -> CGFloat {
        Metrics.headerWidth + Metrics.leadIn + CGFloat((time - scrollOffset) / secondsPerPoint)
    }

    func time(for x: CGFloat) -> Double {
        scrollOffset + Double(x - Metrics.headerWidth - Metrics.leadIn) * secondsPerPoint
    }

    func overviewX(for time: Double) -> CGFloat {
        let w = max(laneWidth - 2 * Metrics.leadIn, 1)
        let dur = max(contentDuration, 0.01)
        return Metrics.headerWidth + Metrics.leadIn + CGFloat(time / dur) * w
    }

    func overviewTime(for x: CGFloat) -> Double {
        let w = max(laneWidth - 2 * Metrics.leadIn, 1)
        let frac = Double((x - Metrics.headerWidth - Metrics.leadIn) / w)
        return min(max(0, frac * contentDuration), contentDuration)
    }

    func trackRows(for proj: AudioProject? = nil) -> [TrackRow] {
        let p = proj ?? project
        // When there is a single track, expand its height so its waveform fills the canvas nicely!
        let availableHeight = max(laneArea.height - 2, 88)
        let singleTrackExpandedHeight = min(max(availableHeight, 120), 420)
        var y = Metrics.topBarHeight - verticalScroll
        return p.tracks.enumerated().map { index, track in
            let h = p.tracks.count == 1 ? singleTrackExpandedHeight : CGFloat(track.height)
            defer { y += h + Metrics.laneGap }
            return TrackRow(index: index, track: track, rect: CGRect(x: 0, y: y, width: bounds.width, height: h))
        }
    }

    func trackRow(at point: CGPoint, for proj: AudioProject? = nil) -> TrackRow? {
        guard point.y >= Metrics.topBarHeight else { return nil }
        return trackRows(for: proj).first { $0.rect.minY <= point.y && point.y < $0.rect.maxY }
    }

    func clipRect(_ clip: AudioClip, in rowRect: CGRect) -> CGRect {
        let x0 = x(for: clip.offset)
        let x1 = x(for: clip.end)
        return CGRect(
            x: x0,
            y: rowRect.minY + Metrics.blockInset,
            width: max(x1 - x0, 2),
            height: rowRect.height - 2 * Metrics.blockInset
        )
    }

    func fadeHandleCenters(for clip: AudioClip, in rowRect: CGRect) -> (fadeIn: CGPoint, fadeOut: CGPoint) {
        let rect = clipRect(clip, in: rowRect)
        let inX = min(rect.minX + CGFloat(clip.fadeIn / secondsPerPoint), rect.maxX)
        let outX = max(rect.maxX - CGFloat(clip.fadeOut / secondsPerPoint), rect.minX)
        let y = rect.minY + Metrics.fadeHandle / 2 + 1
        return (
            CGPoint(x: inX + Metrics.fadeHandle / 2, y: y),
            CGPoint(x: outX - Metrics.fadeHandle / 2, y: y)
        )
    }

    /// Button rects inside a track header (`M`, `S`, `L/R`, `Gain`, `Pan`).
    func headerControlRects(in rowRect: CGRect) -> (mute: CGRect, solo: CGRect, stereo: CGRect, gain: CGRect, pan: CGRect) {
        let topY = rowRect.minY + 8
        let muteRect = CGRect(x: Metrics.headerWidth - 68, y: topY, width: 20, height: 17)
        let soloRect = CGRect(x: Metrics.headerWidth - 45, y: topY, width: 20, height: 17)
        let stereoRect = CGRect(x: Metrics.headerWidth - 22, y: topY, width: 17, height: 17)
        let bottomY = min(rowRect.minY + 32, rowRect.maxY - 22)
        let gainRect = CGRect(x: 12, y: bottomY, width: 68, height: 18)
        let panRect = CGRect(x: 86, y: bottomY, width: 46, height: 18)
        return (muteRect, soloRect, stereoRect, gainRect, panRect)
    }

    // MARK: Zoom & Scroll

    var fitSecondsPerPoint: Double {
        let width = Double(laneWidth - Metrics.leadIn - Metrics.endMargin)
        let total = contentDuration
        guard width > 10, total > 0 else { return 0.02 }
        return total / width
    }

    var isFitted: Bool {
        let fitSPP = max(fitSecondsPerPoint, Metrics.minSecondsPerPoint)
        return abs(secondsPerPoint - fitSPP) / max(fitSPP, 1e-9) < 0.02
            && scrollOffset < max(0.05, contentDuration * 0.01)
    }

    func fit(animate: Bool = false) {
        let targetSPP = max(fitSecondsPerPoint, Metrics.minSecondsPerPoint)
        applyZoomTarget(secondsPerPoint: targetSPP, scrollOffset: 0, animate: animate)
    }

    func zoom(toRange range: ClosedRange<Double>, animate: Bool = false) {
        let span = max(range.upperBound - range.lowerBound, 0.02)
        let width = Double(max(laneWidth - Metrics.leadIn - Metrics.endMargin, 40))
        let targetSPP = max(span / (width * 0.85), Metrics.minSecondsPerPoint)
        let targetOffset = max(0, range.lowerBound - span * 0.075)
        applyZoomTarget(secondsPerPoint: targetSPP, scrollOffset: targetOffset, animate: animate)
    }

    /// Frame the whole project smoothly; when already fitted, zoom to the active selection range or a window around the playhead (`z` shortcut, same idiom as OSCScore & ScoreFollower).
    func toggleZoomToFitOrPlayhead(toggleWindow: Double = 15.0, animate: Bool = true) {
        let baseSPP = zoomAnimation?.toSPP ?? secondsPerPoint
        let baseOffset = zoomAnimation?.toOffset ?? scrollOffset
        let fitSPP = max(fitSecondsPerPoint, Metrics.minSecondsPerPoint)
        let currentlyFitted = abs(baseSPP - fitSPP) / max(fitSPP, 1e-9) < 0.02
            && baseOffset < max(0.05, contentDuration * 0.01)

        if !currentlyFitted {
            applyZoomTarget(secondsPerPoint: fitSPP, scrollOffset: 0, animate: animate)
            return
        }

        // Already fitted: zoom into active range selection if narrower than the project, else around playhead
        if let range = model.selectionRange,
           range.upperBound > range.lowerBound + 0.01,
           (range.upperBound - range.lowerBound) < contentDuration * 0.92 {
            zoom(toRange: range, animate: animate)
            return
        }

        let usableWidth = Double(max(laneWidth - Metrics.leadIn - Metrics.endMargin, 40))
        let win = contentDuration > toggleWindow ? toggleWindow : max(contentDuration * 0.25, 0.2)
        let targetSPP = max(min(win / usableWidth, fitSPP * 0.25), Metrics.minSecondsPerPoint)
        let visible = usableWidth * targetSPP
        let upper = max(0, contentDuration - visible * 0.5)
        let targetOffset = min(max(0, model.playhead - visible * 0.5), upper)
        applyZoomTarget(secondsPerPoint: targetSPP, scrollOffset: targetOffset, animate: animate)
    }

    private func applyZoomTarget(secondsPerPoint targetSPP: Double, scrollOffset targetOffset: Double, animate: Bool) {
        cancelZoomAnimation()
        let isAutomated = CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--snapshot")
        guard animate, window != nil, !isAutomated,
              abs(targetSPP - secondsPerPoint) > 1e-7 || abs(targetOffset - scrollOffset) > 1e-4 else {
            secondsPerPoint = targetSPP
            scrollOffset = targetOffset
            clampScroll()
            refresh()
            return
        }
        zoomAnimation = (
            fromSPP: secondsPerPoint,
            toSPP: targetSPP,
            fromOffset: scrollOffset,
            toOffset: targetOffset,
            start: CACurrentMediaTime(),
            duration: 0.18
        )
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.stepZoomAnimation() }
        }
        RunLoop.main.add(timer, forMode: .common)
        zoomTimer = timer
    }

    private func cancelZoomAnimation() {
        zoomTimer?.invalidate()
        zoomTimer = nil
        zoomAnimation = nil
    }

    private func stepZoomAnimation() {
        guard let anim = zoomAnimation else {
            cancelZoomAnimation()
            return
        }
        let t = min(max((CACurrentMediaTime() - anim.start) / max(anim.duration, 1e-6), 0), 1)
        if t >= 1 {
            secondsPerPoint = anim.toSPP
            scrollOffset = anim.toOffset
            cancelZoomAnimation()
            clampScroll()
            refresh()
            return
        }
        let f = 1 - pow(1 - t, 3) // cubic ease-out
        let logFrom = log(max(anim.fromSPP, 1e-9))
        let logTo = log(max(anim.toSPP, 1e-9))
        let spp = exp(logFrom + (logTo - logFrom) * f)
        let u = abs(anim.toSPP - anim.fromSPP) > 1e-9 ? (spp - anim.fromSPP) / (anim.toSPP - anim.fromSPP) : f
        secondsPerPoint = spp
        scrollOffset = anim.fromOffset + (anim.toOffset - anim.fromOffset) * u
        clampScroll()
        refresh()
    }

    func zoom(by factor: CGFloat, at viewX: CGFloat) {
        guard factor > 0, factor.isFinite else { return }
        cancelZoomAnimation()
        let anchor = time(for: viewX)
        let widest = max(fitSecondsPerPoint * 1.25, secondsPerPoint, Metrics.minSecondsPerPoint)
        secondsPerPoint = min(max(secondsPerPoint / Double(factor), Metrics.minSecondsPerPoint), widest)
        scrollOffset = anchor - Double(viewX - Metrics.headerWidth - Metrics.leadIn) * secondsPerPoint
        clampScroll()
        refresh()
    }

    func clampScroll() {
        let visible = Double(max(laneWidth - Metrics.leadIn - Metrics.endMargin, 10)) * secondsPerPoint
        let upper = max(0, contentDuration - visible * 0.5)
        let clamped = min(max(scrollOffset, 0), upper)
        if clamped != scrollOffset { scrollOffset = clamped }

        let totalTrackHeight = project.tracks.count <= 1
            ? 0
            : project.tracks.reduce(CGFloat(0)) { $0 + CGFloat($1.height) + Metrics.laneGap }
        let maxV = max(0, totalTrackHeight - laneArea.height + 24)
        let clampedV = min(max(verticalScroll, 0), maxV)
        if clampedV != verticalScroll { verticalScroll = clampedV }
    }

    func refresh() {
        needsDisplay = true
        updatePlayhead()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTracking = area
    }

    // MARK: Playhead

    func updatePlayhead(_ t: Double? = nil) {
        let time = t ?? model.playhead
        if case .none = drag, model.transportPlaying {
            let px = x(for: time)
            if px > bounds.maxX - 24 || px < Metrics.headerWidth + Metrics.leadIn - 1 {
                scrollOffset = max(0, time - Double(60) * secondsPerPoint)
                clampScroll()
                needsDisplay = true
            }
        }
        let px = x(for: time).rounded()
        playheadView.isHidden = px < Metrics.headerWidth - 0.5 || px > bounds.maxX
        let frame = CGRect(
            x: px - TimelinePlayheadView.halfWidth,
            y: Metrics.overviewHeight,
            width: TimelinePlayheadView.halfWidth * 2 + 1,
            height: max(0, bounds.height - Metrics.overviewHeight)
        )
        if frame != playheadView.frame { playheadView.frame = frame }
    }
}

final class TimelinePlayheadView: NSView {
    static let halfWidth: CGFloat = 5

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let mid = bounds.midX
        Theme.playhead.setFill()
        CGRect(x: mid - 0.5, y: 10, width: 1, height: max(0, bounds.height - 10)).fill()
        let head = NSBezierPath()
        head.move(to: CGPoint(x: mid - 4.5, y: 9))
        head.line(to: CGPoint(x: mid + 4.5, y: 9))
        head.line(to: CGPoint(x: mid + 4.5, y: 14))
        head.line(to: CGPoint(x: mid, y: 19))
        head.line(to: CGPoint(x: mid - 4.5, y: 14))
        head.close()
        head.fill()
    }
}

final class TimelineTipView: NSView {
    private(set) var text = ""
    private let attributes: [NSAttributedString.Key: Any] = [
        .font: Theme.mono(10.5, .medium),
        .foregroundColor: Theme.text,
    ]
    static let padding = CGSize(width: 6, height: 3)

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ text: String) -> CGSize {
        if text != self.text {
            self.text = text
            needsDisplay = true
        }
        let size = (text as NSString).size(withAttributes: attributes)
        return CGSize(
            width: ceil(size.width) + 2 * Self.padding.width,
            height: ceil(size.height) + 2 * Self.padding.height
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        Theme.panel.withAlphaComponent(0.96).setFill()
        shape.fill()
        Theme.text.withAlphaComponent(0.22).setStroke()
        shape.lineWidth = 1
        shape.stroke()
        (text as NSString).draw(
            at: CGPoint(x: Self.padding.width, y: Self.padding.height),
            withAttributes: attributes
        )
    }
}
