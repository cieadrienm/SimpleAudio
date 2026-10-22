import AppKit
import Observation
import QuartzCore
import SimpleAudioCore
import SimpleAudioEngine

/// Tracks elastic rubber-band overscroll & pinch zoom state during trackpad gestures.
struct ElasticScrollState {
    struct Pose: Equatable {
        var secondsPerPoint: Double
        var scrollOffset: Double
        var verticalScroll: CGFloat
    }

    var virtualOffset: Double?
    var virtualVertical: CGFloat?
    var virtualLogSPP: Double?
    var zoomAnchorTime: Double = 0
    var zoomAnchorX: CGFloat = 0
    var ignoreMomentum: Bool = false
    var animation: (from: Pose, to: Pose, start: CFTimeInterval, duration: CFTimeInterval, bounce: Bool)?
}

final class TimelineView: NSView {
    enum Metrics {
        static let headerWidth: CGFloat = 178
        static let pianoKeysWidth: CGFloat = 32
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
        static let rubberPixels: CGFloat = 88
        static let rubberZoomLog: Double = 0.14
    }

    enum Edge: Equatable {
        case start
        case end
    }

    enum HeaderControl: Equatable {
        case mute(UUID)
        case solo(UUID)
        case stereoSplit(UUID)
        case pianoRoll(UUID)
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
        case pressNote(noteID: UUID, trackID: UUID, startPoint: CGPoint, grabTime: Double, originalNote: MIDINote)
        case moveNote(noteID: UUID, trackID: UUID, grabTime: Double, originalNote: MIDINote, lastPreviewPitch: Int)
        case trimNote(noteID: UUID, edge: Edge, grabTime: Double, originalNote: MIDINote)
        case trackGain(trackID: UUID, startY: CGFloat, originalDB: Double)
        case trackPan(trackID: UUID, startX: CGFloat, originalPan: Double)
        case pressTrack(trackID: UUID, startY: CGFloat)
        case moveTrack(trackID: UUID, targetIndex: Int)
        case marker(markerID: UUID, grab: Double, originalTime: Double)
    }

    struct TrackRow {
        var index: Int
        var track: AudioTrack
        var rect: CGRect
        var minPitch: Int = 48
        var maxPitch: Int = 84
        var showPianoKeys: Bool = false
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
    var hoveredNote: UUID?
    var hoverHit: Hit?
    var lastMouse: CGPoint?
    var currentCursor: TimelineCursor = .arrow
    var debugCursorName: String { currentCursor.rawValue }
    var elastic = ElasticScrollState()
    var markerZoomStage: (markerID: UUID, level: Int)?

    struct OverviewCacheKey: Equatable {
        var changeCount: Int
        var width: Int
        var height: Int
        var clipCount: Int
        var noteCount: Int
        var waveReadyCount: Int
    }

    let playheadView = TimelinePlayheadView()
    let overviewPlayheadView = TimelineOverviewPlayheadView()
    let tipView = TimelineTipView()
    var cachedOverviewKey: OverviewCacheKey?
    var cachedOverviewWavePath: CGPath?
    var cachedOverviewNoteBatches: [(colorIndex: Int, rects: [CGRect])] = []
    private var hoverTracking: NSTrackingArea?
    private var didInitialFit = false
    private var fittedURL: URL?
    private var lastChangeCount = -1
    private var animDisplayLink: CADisplayLink?
    private var animTimer: Timer?

    init(model: AppModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        playheadView.wantsLayer = true
        overviewPlayheadView.wantsLayer = true
        addSubview(overviewPlayheadView)
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

    var displayRefreshInterval: TimeInterval {
        let fps = window?.screen?.maximumFramesPerSecond ?? NSScreen.main?.maximumFramesPerSecond ?? 60
        let clamped = min(max(fps, 60), 120)
        return 1.0 / Double(clamped)
    }

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
        if !isElasticActive {
            clampScroll()
        }
        updatePlayhead()
    }

    // MARK: Model Observation

    var project: AudioProject { preview ?? model.store.project }

    private func observeModel() {
        withObservationTracking {
            _ = model.store.changeCount
            _ = model.store.url
            _ = model.selectedClips
            _ = model.selectedNotes
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
                markerZoomStage = nil
                if didInitialFit { fit() }
            }
        }
        if let stage = markerZoomStage, model.selectedMarkerID != stage.markerID {
            markerZoomStage = nil
        }
        if !isElasticActive {
            clampScroll()
        }
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
        let availableHeight = max(laneArea.height - 2, 88)
        let singleTrackExpandedHeight = min(max(availableHeight, 120), 480)
        var y = Metrics.topBarHeight - verticalScroll
        return p.tracks.enumerated().map { index, track in
            let isSingle = p.tracks.count == 1
            let h: CGFloat
            if isSingle {
                h = singleTrackExpandedHeight
            } else if track.isMIDI && track.pianoRollExpanded {
                h = max(CGFloat(track.height), 220)
            } else {
                h = CGFloat(track.height)
            }
            defer { y += h + Metrics.laneGap }
            if track.isMIDI {
                let boundsPitch = track.pitchBounds
                return TrackRow(
                    index: index,
                    track: track,
                    rect: CGRect(x: 0, y: y, width: bounds.width, height: h),
                    minPitch: boundsPitch.minPitch,
                    maxPitch: boundsPitch.maxPitch,
                    showPianoKeys: isSingle || track.pianoRollExpanded || h >= 135
                )
            } else {
                return TrackRow(
                    index: index,
                    track: track,
                    rect: CGRect(x: 0, y: y, width: bounds.width, height: h)
                )
            }
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

    func noteRect(_ note: MIDINote, in row: TrackRow) -> CGRect {
        let x0 = x(for: note.start)
        let x1 = x(for: note.end)
        let pitchCount = CGFloat(max(1, row.maxPitch - row.minPitch + 1))
        let usableTop = row.rect.minY + Metrics.blockInset
        let usableHeight = max(12, row.rect.height - 2 * Metrics.blockInset)
        let noteH = max(4.5, min(usableHeight / pitchCount, 18.0))
        let clampedPitch = min(max(note.pitch, row.minPitch), row.maxPitch)
        let normalizedFromTop = CGFloat(row.maxPitch - clampedPitch) / max(1, pitchCount - 1)
        let y = usableTop + normalizedFromTop * max(0, usableHeight - noteH)
        return CGRect(
            x: x0,
            y: y,
            width: max(x1 - x0, 4),
            height: noteH
        )
    }

    func pitch(forY y: CGFloat, in row: TrackRow) -> Int {
        let usableTop = row.rect.minY + Metrics.blockInset
        let usableHeight = max(12, row.rect.height - 2 * Metrics.blockInset)
        let fracFromTop = min(max((y - usableTop) / usableHeight, 0), 1)
        let span = Double(row.maxPitch - row.minPitch)
        let rawPitch = Double(row.maxPitch) - Double(fracFromTop) * span
        return min(max(Int(rawPitch.rounded()), 0), 127)
    }

    /// Button rects inside a track header (`M`, `S`, `⊶` or `🎹`, `Gain`, `Pan`).
    func headerControlRects(in rowRect: CGRect, isMIDI: Bool = false) -> (mute: CGRect, solo: CGRect, third: CGRect, gain: CGRect, pan: CGRect) {
        let topY = rowRect.minY + 8
        let muteRect = CGRect(x: Metrics.headerWidth - 70, y: topY, width: 20, height: 17)
        let soloRect = CGRect(x: Metrics.headerWidth - 47, y: topY, width: 20, height: 17)
        let thirdRect = CGRect(x: Metrics.headerWidth - 24, y: topY, width: 19, height: 17)
        let bottomY = isMIDI ? min(rowRect.minY + 44, rowRect.maxY - 22) : min(rowRect.minY + 32, rowRect.maxY - 22)
        let gainRect = CGRect(x: 11, y: bottomY, width: 68, height: 18)
        let panRect = CGRect(x: 85, y: bottomY, width: 46, height: 18)
        return (muteRect, soloRect, thirdRect, gainRect, panRect)
    }

    // MARK: Zoom, Hard Bounds & Elastic Rubber-Band Bounce

    var usableLaneWidth: Double {
        Double(max(laneWidth - Metrics.leadIn - Metrics.endMargin, 40))
    }

    var fitSecondsPerPoint: Double {
        let width = usableLaneWidth
        let total = contentDuration
        guard width > 10, total > 0 else { return 0.02 }
        return max(total / width, Metrics.minSecondsPerPoint)
    }

    func scrollOffsetRange(at spp: Double) -> ClosedRange<Double> {
        let visible = usableLaneWidth * spp
        return 0...max(0, contentDuration - visible)
    }

    var scrollOffsetRange: ClosedRange<Double> {
        scrollOffsetRange(at: secondsPerPoint)
    }

    var verticalScrollRange: ClosedRange<CGFloat> {
        let totalTrackHeight = project.tracks.count <= 1
            ? 0
            : project.tracks.reduce(CGFloat(0)) { $0 + CGFloat(($1.isMIDI && $1.pianoRollExpanded) ? max($1.height, 220) : $1.height) + Metrics.laneGap }
        return 0...max(0, totalTrackHeight - laneArea.height + 24)
    }

    var isElasticActive: Bool {
        elastic.virtualOffset != nil || elastic.virtualLogSPP != nil || elastic.animation != nil
    }

    var isFitted: Bool {
        let fitSPP = fitSecondsPerPoint
        return abs(secondsPerPoint - fitSPP) / max(fitSPP, 1e-9) < 0.02
            && abs(scrollOffset) < max(0.05, contentDuration * 0.01)
    }

    static func rubberBand<T: BinaryFloatingPoint>(_ value: T, in range: ClosedRange<T>, limit: T) -> T {
        guard limit > 0 else { return min(max(value, range.lowerBound), range.upperBound) }
        if value < range.lowerBound {
            return range.lowerBound - limit * T(1.0 - exp(-Double((range.lowerBound - value) / limit)))
        }
        if value > range.upperBound {
            return range.upperBound + limit * T(1.0 - exp(-Double((value - range.upperBound) / limit)))
        }
        return value
    }

    private var currentPose: ElasticScrollState.Pose {
        ElasticScrollState.Pose(secondsPerPoint: secondsPerPoint, scrollOffset: scrollOffset, verticalScroll: verticalScroll)
    }

    private var restingPose: ElasticScrollState.Pose {
        let fitSPP = fitSecondsPerPoint
        let clampedSPP = min(max(secondsPerPoint, Metrics.minSecondsPerPoint), fitSPP)
        let xRange = scrollOffsetRange(at: clampedSPP)
        let clampedOffset = min(max(scrollOffset, xRange.lowerBound), xRange.upperBound)
        let yRange = verticalScrollRange
        let clampedV = min(max(verticalScroll, yRange.lowerBound), yRange.upperBound)
        return ElasticScrollState.Pose(secondsPerPoint: clampedSPP, scrollOffset: clampedOffset, verticalScroll: clampedV)
    }

    func fit(animate: Bool = false) {
        markerZoomStage = nil
        let targetSPP = fitSecondsPerPoint
        applyZoomTarget(secondsPerPoint: targetSPP, scrollOffset: 0, animate: animate)
    }

    func zoom(toRange range: ClosedRange<Double>, animate: Bool = false) {
        let span = max(range.upperBound - range.lowerBound, 0.02)
        let width = usableLaneWidth
        let fitSPP = fitSecondsPerPoint
        let targetSPP = min(max(span / (width * 0.85), Metrics.minSecondsPerPoint), fitSPP)
        let targetOffset = max(0, range.lowerBound - span * 0.075)
        applyZoomTarget(secondsPerPoint: targetSPP, scrollOffset: targetOffset, animate: animate)
    }

    /// `Z` shortcut:
    /// - When a marker is selected (`model.selectedMarkerID != nil`), cycles through **3 levels**:
    ///   1. **15s window** centered around the marker (`plage de 15s`),
    ///   2. **Zone defined by the marker** (`marker.time` to next marker or end of piece),
    ///   3. **Whole piece** (`la piste entière`).
    /// - Otherwise toggles between **Whole piece (Fit)** and **15s window around playhead** (or active selection range).
    func toggleZoomToFitOrPlayhead(toggleWindow: Double = 15.0, animate: Bool = true) {
        let fitSPP = fitSecondsPerPoint
        let width = usableLaneWidth

        if let markerID = model.selectedMarkerID,
           let marker = project.markers.first(where: { $0.id == markerID }) {
            let nextLevel: Int
            if let currentStage = markerZoomStage, currentStage.markerID == markerID {
                nextLevel = (currentStage.level % 3) + 1
            } else {
                nextLevel = 1
            }
            markerZoomStage = (markerID: markerID, level: nextLevel)

            switch nextLevel {
            case 1:
                let win = min(15.0, contentDuration)
                let targetSPP = min(max(win / width, Metrics.minSecondsPerPoint), fitSPP)
                let visible = width * targetSPP
                let xRange = scrollOffsetRange(at: targetSPP)
                let targetOffset = min(max(marker.time - visible * 0.5, xRange.lowerBound), xRange.upperBound)
                model.statusMessage = "Zoom marqueur « \(marker.name) » (1/3) : plage de 15s"
                applyZoomTarget(secondsPerPoint: targetSPP, scrollOffset: targetOffset, animate: animate)

            case 2:
                let sorted = project.markers.sorted { $0.time < $1.time }
                let zoneStart: Double
                let zoneEnd: Double
                if let nextMarker = sorted.first(where: { $0.time > marker.time + 0.05 }) {
                    zoneStart = marker.time
                    zoneEnd = nextMarker.time
                } else if marker.time < contentDuration - 0.1 {
                    zoneStart = marker.time
                    zoneEnd = contentDuration
                } else if let prevMarker = sorted.last(where: { $0.time < marker.time - 0.05 }) {
                    zoneStart = prevMarker.time
                    zoneEnd = marker.time
                } else {
                    zoneStart = 0
                    zoneEnd = contentDuration
                }
                let span = max(0.5, zoneEnd - zoneStart)
                let targetSPP = min(max(span / width, Metrics.minSecondsPerPoint), fitSPP)
                let xRange = scrollOffsetRange(at: targetSPP)
                let targetOffset = min(max(zoneStart, xRange.lowerBound), xRange.upperBound)
                model.statusMessage = "Zoom marqueur « \(marker.name) » (2/3) : zone (\(TimeFormat.shortDuration(span)))"
                applyZoomTarget(secondsPerPoint: targetSPP, scrollOffset: targetOffset, animate: animate)

            default:
                model.statusMessage = "Zoom marqueur « \(marker.name) » (3/3) : piste entière"
                applyZoomTarget(secondsPerPoint: fitSPP, scrollOffset: 0, animate: animate)
            }
            return
        }

        markerZoomStage = nil
        let basePose = elastic.animation?.to ?? currentPose
        let currentlyFitted = abs(basePose.secondsPerPoint - fitSPP) / max(fitSPP, 1e-9) < 0.02
            && abs(basePose.scrollOffset) < max(0.05, contentDuration * 0.01)

        if !currentlyFitted {
            applyZoomTarget(secondsPerPoint: fitSPP, scrollOffset: 0, animate: animate)
            return
        }

        if let range = model.selectionRange,
           range.upperBound > range.lowerBound + 0.01,
           (range.upperBound - range.lowerBound) < contentDuration * 0.92 {
            zoom(toRange: range, animate: animate)
            return
        }

        let win = contentDuration > toggleWindow ? toggleWindow : max(contentDuration * 0.25, 0.2)
        let targetSPP = max(min(win / width, fitSPP * 0.25), Metrics.minSecondsPerPoint)
        let visible = width * targetSPP
        let xRange = scrollOffsetRange(at: targetSPP)
        let targetOffset = min(max(model.playhead - visible * 0.5, xRange.lowerBound), xRange.upperBound)
        applyZoomTarget(secondsPerPoint: targetSPP, scrollOffset: targetOffset, animate: animate)
    }

    func applyZoomTarget(secondsPerPoint targetSPP: Double, scrollOffset targetOffset: Double, animate: Bool) {
        cancelElasticAnimation()
        elastic.virtualOffset = nil
        elastic.virtualVertical = nil
        elastic.virtualLogSPP = nil

        let fitSPP = fitSecondsPerPoint
        let clampedSPP = min(max(targetSPP, Metrics.minSecondsPerPoint), fitSPP)
        let xRange = scrollOffsetRange(at: clampedSPP)
        let clampedOffset = min(max(targetOffset, xRange.lowerBound), xRange.upperBound)

        let isAutomated = CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--snapshot")
        guard animate, window != nil, !isAutomated,
              abs(clampedSPP - secondsPerPoint) > 1e-7 || abs(clampedOffset - scrollOffset) > 1e-4 else {
            secondsPerPoint = clampedSPP
            scrollOffset = clampedOffset
            clampScroll()
            refresh()
            return
        }

        let target = ElasticScrollState.Pose(
            secondsPerPoint: clampedSPP,
            scrollOffset: clampedOffset,
            verticalScroll: verticalScroll
        )
        startElasticAnimation(to: target, duration: 0.18, bounce: false)
    }

    func startElasticAnimation(to target: ElasticScrollState.Pose, duration: CFTimeInterval, bounce: Bool) {
        elastic.animation = (
            from: currentPose,
            to: target,
            start: CACurrentMediaTime(),
            duration: duration,
            bounce: bounce
        )
        ensureAnimationTimerRunning()
    }

    func springBack() {
        elastic.virtualOffset = nil
        elastic.virtualVertical = nil
        elastic.virtualLogSPP = nil
        let target = restingPose
        guard abs(target.secondsPerPoint - secondsPerPoint) > 1e-7
            || abs(target.scrollOffset - scrollOffset) > 1e-4
            || abs(target.verticalScroll - verticalScroll) > 0.2 else {
            clampScroll()
            return
        }
        startElasticAnimation(to: target, duration: 0.24, bounce: false)
    }

    func bump(zoomingOut: Bool, around viewX: CGFloat) {
        guard elastic.animation == nil else { return }
        let anchor = time(for: viewX)
        var to = currentPose
        to.secondsPerPoint = secondsPerPoint * (zoomingOut ? 1.045 : 0.955)
        to.scrollOffset = anchor - Double(viewX - Metrics.headerWidth - Metrics.leadIn) * to.secondsPerPoint
        startElasticAnimation(to: to, duration: 0.20, bounce: true)
    }

    func cancelElasticAnimation() {
        animDisplayLink?.invalidate()
        animDisplayLink = nil
        animTimer?.invalidate()
        animTimer = nil
        if let anim = elastic.animation, anim.bounce {
            applyPose(anim.from)
        }
        elastic.animation = nil
    }

    private func ensureAnimationTimerRunning() {
        guard animDisplayLink == nil, animTimer == nil else { return }
        if window != nil {
            let link = displayLink(target: self, selector: #selector(handleDisplayLink(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            animDisplayLink = link
        } else {
            let timer = Timer(timeInterval: displayRefreshInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.stepElasticAnimation() }
            }
            RunLoop.main.add(timer, forMode: .common)
            animTimer = timer
        }
    }

    @objc private func handleDisplayLink(_ link: CADisplayLink) {
        stepElasticAnimation()
    }

    private func stepElasticAnimation() {
        guard let anim = elastic.animation else {
            cancelElasticAnimation()
            return
        }
        let t = min(max((CACurrentMediaTime() - anim.start) / max(anim.duration, 1e-6), 0), 1)
        let f: Double = anim.bounce ? sin(.pi * t) : (1.0 - pow(1.0 - t, 3.0))

        let logFrom = log(max(anim.from.secondsPerPoint, 1e-9))
        let logTo = log(max(anim.to.secondsPerPoint, 1e-9))
        let spp = exp(logFrom + (logTo - logFrom) * f)
        let u = abs(anim.to.secondsPerPoint - anim.from.secondsPerPoint) > 1e-9
            ? (spp - anim.from.secondsPerPoint) / (anim.to.secondsPerPoint - anim.from.secondsPerPoint)
            : f

        let pose = ElasticScrollState.Pose(
            secondsPerPoint: spp,
            scrollOffset: anim.from.scrollOffset + (anim.to.scrollOffset - anim.from.scrollOffset) * u,
            verticalScroll: anim.from.verticalScroll + (anim.to.verticalScroll - anim.from.verticalScroll) * CGFloat(f)
        )
        applyPose(pose)

        if t >= 1.0 {
            let finalPose = anim.bounce ? anim.from : anim.to
            elastic.animation = nil
            animDisplayLink?.invalidate()
            animDisplayLink = nil
            animTimer?.invalidate()
            animTimer = nil
            applyPose(finalPose)
            clampScroll()
        }
    }

    private func applyPose(_ p: ElasticScrollState.Pose) {
        secondsPerPoint = p.secondsPerPoint
        scrollOffset = p.scrollOffset
        verticalScroll = p.verticalScroll
        refresh()
    }

    func zoom(by factor: CGFloat, at viewX: CGFloat) {
        guard factor > 0, factor.isFinite else { return }
        markerZoomStage = nil
        cancelElasticAnimation()
        let anchor = time(for: viewX)
        let widest = max(fitSecondsPerPoint, Metrics.minSecondsPerPoint)
        let wanted = secondsPerPoint / Double(factor)
        let clamped = min(max(wanted, Metrics.minSecondsPerPoint), widest)
        if abs(clamped - secondsPerPoint) < 1e-7, abs(wanted - clamped) > 1e-7 {
            bump(zoomingOut: factor < 1, around: viewX)
            return
        }
        secondsPerPoint = clamped
        scrollOffset = anchor - Double(viewX - Metrics.headerWidth - Metrics.leadIn) * secondsPerPoint
        clampScroll()
        refresh()
    }

    func elasticScroll(dx: CGFloat, dy: CGFloat, phase: NSEvent.Phase, momentum: NSEvent.Phase) {
        if phase.contains(.began) || phase.contains(.mayBegin) {
            cancelElasticAnimation()
            elastic.ignoreMomentum = false
            elastic.virtualOffset = scrollOffset
            elastic.virtualVertical = verticalScroll
        }
        if !momentum.isEmpty, elastic.ignoreMomentum { return }
        if elastic.virtualOffset == nil {
            elastic.virtualOffset = scrollOffset
            elastic.virtualVertical = verticalScroll
        }

        elastic.virtualOffset! -= Double(dx) * secondsPerPoint
        if project.tracks.count > 1 {
            elastic.virtualVertical! -= dy
        }

        let xRange = scrollOffsetRange
        let yRange = verticalScrollRange
        let limitX = Double(Metrics.rubberPixels) * secondsPerPoint
        scrollOffset = Self.rubberBand(elastic.virtualOffset!, in: xRange, limit: limitX)
        verticalScroll = Self.rubberBand(elastic.virtualVertical!, in: yRange, limit: Metrics.rubberPixels)
        refresh()

        let outsideX = scrollOffset < xRange.lowerBound - 1e-5 || scrollOffset > xRange.upperBound + 1e-5
        let outsideY = verticalScroll < yRange.lowerBound - 0.1 || verticalScroll > yRange.upperBound + 0.1
        let outside = outsideX || outsideY

        if phase.contains(.ended) || phase.contains(.cancelled) {
            if outside {
                elastic.ignoreMomentum = true
                springBack()
            } else if momentum.isEmpty {
                elastic.virtualOffset = nil
                elastic.virtualVertical = nil
            }
        } else if !momentum.isEmpty {
            let clampedVirtX = min(max(elastic.virtualOffset!, xRange.lowerBound), xRange.upperBound)
            let clampedVirtY = min(max(elastic.virtualVertical!, yRange.lowerBound), yRange.upperBound)
            let excessX = abs(elastic.virtualOffset! - clampedVirtX) / max(secondsPerPoint, 1e-9)
            let excessY = Double(abs(elastic.virtualVertical! - clampedVirtY))
            if momentum.contains(.ended) || momentum.contains(.cancelled) || max(CGFloat(excessX), CGFloat(excessY)) > Metrics.rubberPixels * 0.55 {
                elastic.ignoreMomentum = !momentum.contains(.ended)
                if outside {
                    springBack()
                } else {
                    elastic.virtualOffset = nil
                    elastic.virtualVertical = nil
                }
            }
        }
    }

    func elasticZoom(by factor: CGFloat, around viewX: CGFloat, phase: NSEvent.Phase, momentum: NSEvent.Phase) {
        markerZoomStage = nil
        if phase.contains(.began) || elastic.virtualLogSPP == nil {
            cancelElasticAnimation()
            elastic.virtualLogSPP = log(max(secondsPerPoint, Metrics.minSecondsPerPoint))
        }
        elastic.zoomAnchorTime = time(for: viewX)
        elastic.zoomAnchorX = viewX
        elastic.virtualLogSPP! -= log(Double(max(factor, 0.01)))

        let fitSPP = fitSecondsPerPoint
        let logBounds = log(Metrics.minSecondsPerPoint)...log(max(fitSPP, Metrics.minSecondsPerPoint * 1.01))
        secondsPerPoint = exp(Self.rubberBand(elastic.virtualLogSPP!, in: logBounds, limit: Metrics.rubberZoomLog))
        scrollOffset = elastic.zoomAnchorTime - Double(viewX - Metrics.headerWidth - Metrics.leadIn) * secondsPerPoint
        let yRange = verticalScrollRange
        verticalScroll = min(max(verticalScroll, yRange.lowerBound), yRange.upperBound)
        refresh()

        let over = phase.contains(.ended) || phase.contains(.cancelled) || momentum.contains(.ended) || momentum.contains(.cancelled)
        if over || (phase.isEmpty && momentum.isEmpty) {
            elastic.virtualLogSPP = nil
            springBack()
        }
    }

    func clampScroll() {
        let fitSPP = fitSecondsPerPoint
        if secondsPerPoint > fitSPP {
            secondsPerPoint = fitSPP
        }
        let xRange = scrollOffsetRange(at: secondsPerPoint)
        let clamped = min(max(scrollOffset, xRange.lowerBound), xRange.upperBound)
        if clamped != scrollOffset { scrollOffset = clamped }

        let yRange = verticalScrollRange
        let clampedV = min(max(verticalScroll, yRange.lowerBound), yRange.upperBound)
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
        if case .none = drag, !isElasticActive, model.transportPlaying {
            let px = x(for: time)
            if px > bounds.maxX - 24 || px < Metrics.headerWidth + Metrics.leadIn - 1 {
                let xRange = scrollOffsetRange
                scrollOffset = min(max(time - Double(60) * secondsPerPoint, xRange.lowerBound), xRange.upperBound)
                needsDisplay = true
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let px = x(for: time)
        let hideMain = px < Metrics.headerWidth - 0.5 || px > bounds.maxX
        if playheadView.isHidden != hideMain {
            playheadView.isHidden = hideMain
        }
        let frame = CGRect(
            x: px - TimelinePlayheadView.halfWidth,
            y: Metrics.overviewHeight,
            width: TimelinePlayheadView.halfWidth * 2 + 1,
            height: max(0, bounds.height - Metrics.overviewHeight)
        )
        if frame != playheadView.frame {
            playheadView.frame = frame
        }

        let area = overviewArea
        let ovX = overviewX(for: time)
        let hideOverview = area.width <= 20 || project.totalDuration <= 0 || ovX < area.minX || ovX > area.maxX
        if overviewPlayheadView.isHidden != hideOverview {
            overviewPlayheadView.isHidden = hideOverview
        }
        let ovFrame = CGRect(
            x: ovX - 0.75,
            y: area.minY,
            width: 1.5,
            height: max(0, area.height)
        )
        if ovFrame != overviewPlayheadView.frame {
            overviewPlayheadView.frame = ovFrame
        }
    }
}

final class TimelineOverviewPlayheadView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        Theme.playhead.setFill()
        bounds.fill()
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
