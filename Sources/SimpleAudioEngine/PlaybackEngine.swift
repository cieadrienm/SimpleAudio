import Accelerate
import AVFoundation
import Foundation
import Observation
import SimpleAudioCore

/// Pre-resolved clip ready for the real-time audio thread and the offline renderer.
public struct PreparedClip: @unchecked Sendable {
    public let clip: AudioClip
    public let pcm: AudioPCMData
    public let linearGain: Float

    public init(clip: AudioClip, pcm: AudioPCMData) {
        self.clip = clip
        self.pcm = pcm
        self.linearGain = Float(clip.linearGain)
    }
}

/// Pre-resolved track ready for the real-time audio thread and the offline renderer.
public struct PreparedTrack: @unchecked Sendable {
    public let id: UUID
    public let leftGain: Float
    public let rightGain: Float
    public let clips: [PreparedClip]

    public init(id: UUID, leftGain: Float, rightGain: Float, clips: [PreparedClip]) {
        self.id = id
        self.leftGain = leftGain
        self.rightGain = rightGain
        self.clips = clips
    }
}

/// Immutable snapshot shared between the main thread and the Core Audio render thread.
public struct RenderPlan: @unchecked Sendable {
    public let tracks: [PreparedTrack]
    public let masterGain: Float
    public let totalDuration: Double
    public let loopRange: ClosedRange<Double>?

    public init(project: AudioProject, projectURL: URL?, pcmStore: PCMStore = .shared, preloadMissing: Bool = false) {
        self.masterGain = Float(project.masterLinearGain)
        self.totalDuration = project.totalDuration
        self.loopRange = project.loopRange

        var preparedTracks: [PreparedTrack] = []
        for track in project.tracks where project.isTrackAudible(track) && !track.clips.isEmpty {
            let tg = track.linearGain
            let pan = track.panGains
            let lGain = Float(tg * pan.left)
            let rGain = Float(tg * pan.right)
            guard lGain > 1e-6 || rGain > 1e-6 else { continue }

            var preparedClips: [PreparedClip] = []
            for clip in track.clips where !clip.mute && clip.linearGain > 1e-6 {
                let url = AudioProject.resolve(clip.path, relativeTo: projectURL)
                let pcm: AudioPCMData?
                if let cached = pcmStore.get(url) {
                    pcm = cached
                } else if preloadMissing {
                    pcm = try? pcmStore.loadSync(url)
                } else {
                    pcm = nil
                }
                if let pcm {
                    preparedClips.append(PreparedClip(clip: clip, pcm: pcm))
                }
            }
            if !preparedClips.isEmpty {
                preparedTracks.append(PreparedTrack(id: track.id, leftGain: lGain, rightGain: rGain, clips: preparedClips))
            }
        }
        self.tracks = preparedTracks
    }

    /// Mixes `frameCount` stereo frames starting at timeline `startTime` at `sampleRate` into `outLeft` and `outRight`.
    /// Allocates nothing: safe on the real-time audio render thread.
    @inline(__always)
    public func render(
        startTime: Double,
        frameCount: Int,
        sampleRate: Double,
        outLeft: UnsafeMutablePointer<Float>,
        outRight: UnsafeMutablePointer<Float>
    ) -> (peakL: Float, peakR: Float) {
        let count = vDSP_Length(frameCount)
        vDSP_vclr(outLeft, 1, count)
        vDSP_vclr(outRight, 1, count)
        guard !tracks.isEmpty, masterGain > 1e-6, sampleRate > 0, frameCount > 0 else { return (0, 0) }

        let dt = 1.0 / sampleRate
        let endTime = startTime + Double(frameCount) * dt

        for track in tracks {
            let tL = track.leftGain * masterGain
            let tR = track.rightGain * masterGain
            for item in track.clips {
                let c = item.clip
                guard c.end > startTime, c.offset < endTime else { continue }
                let firstFrame = max(0, Int(((c.offset - startTime) * sampleRate).rounded(.down)))
                let lastFrame = min(frameCount, Int(((c.end - startTime) * sampleRate).rounded(.up)))
                guard firstFrame < lastFrame else { continue }

                let cGain = item.linearGain
                let pcm = item.pcm
                let hasFade = c.fadeIn > 1e-6 || c.fadeOut > 1e-6

                for i in firstFrame..<lastFrame {
                    let t = startTime + Double(i) * dt
                    guard t >= c.offset, t <= c.end else { continue }
                    let local = t - c.offset
                    var env = cGain
                    if hasFade {
                        env *= Float(c.fadeGain(atLocalTime: local))
                    }
                    let srcTime = c.reversed ? (c.sourceStart + c.duration - local) : (c.sourceStart + local)
                    let (sL, sR) = pcm.sample(at: srcTime)
                    outLeft[i] += sL * env * tL
                    outRight[i] += sR * env * tR
                }
            }
        }

        var peakL: Float = 0
        var peakR: Float = 0
        vDSP_maxmgv(outLeft, 1, &peakL, count)
        vDSP_maxmgv(outRight, 1, &peakR, count)
        return (peakL, peakR)
    }
}

/// Shared state accessed by both the main thread and the Core Audio render callback.
private final class PlaybackRenderState: @unchecked Sendable {
    private let lock = NSLock()
    var plan = RenderPlan(project: AudioProject(), projectURL: nil)
    var playing = false
    var currentTime: Double = 0
    var loopRangeOverride: ClosedRange<Double>?
    var peakLeft: Float = 0
    var peakRight: Float = 0
    var reachedEnd = false

    func withLock<T>(_ body: (PlaybackRenderState) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(self)
    }
}

@MainActor
@Observable
public final class PlaybackEngine {
    public private(set) var isPlaying = false
    public private(set) var currentTime: Double = 0
    public private(set) var meterLeft: Float = 0
    public private(set) var meterRight: Float = 0

    public var loopRange: ClosedRange<Double>? {
        didSet {
            renderState.withLock { $0.loopRangeOverride = loopRange }
        }
    }

    @ObservationIgnored public var onTime: ((Double) -> Void)?

    @ObservationIgnored private let renderState = PlaybackRenderState()
    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var sourceNode: AVAudioSourceNode?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTickUptime: Double = 0
    @ObservationIgnored private var engineProducesFrames = false

    public init() {}

    public func update(project: AudioProject, projectURL: URL?) {
        let plan = RenderPlan(project: project, projectURL: projectURL, pcmStore: .shared, preloadMissing: false)
        renderState.withLock { state in
            state.plan = plan
            if state.currentTime > max(plan.totalDuration, 0.01) && plan.totalDuration > 0 {
                state.currentTime = plan.totalDuration
            }
        }
        if currentTime > project.totalDuration && project.totalDuration > 0 {
            currentTime = project.totalDuration
            onTime?(currentTime)
        }
    }

    public func schedule(project: AudioProject, projectURL: URL? = nil) {
        update(project: project, projectURL: projectURL)
    }

    public func play() {
        guard !isPlaying else { return }
        let total = renderState.withLock { $0.plan.totalDuration }
        if total > 0, currentTime >= total - 0.01 {
            seek(to: loopRange?.lowerBound ?? 0)
        }
        ensureAudioEngineStarted()
        lastTickUptime = ProcessInfo.processInfo.systemUptime
        renderState.withLock {
            $0.playing = true
            $0.reachedEnd = false
        }
        isPlaying = true
        startDisplayTimer()
    }

    public func pause() {
        guard isPlaying else { return }
        renderState.withLock {
            $0.playing = false
            $0.peakLeft = 0
            $0.peakRight = 0
        }
        isPlaying = false
        meterLeft = 0
        meterRight = 0
        stopDisplayTimer()
    }

    public func stop() {
        pause()
        seek(to: loopRange?.lowerBound ?? 0)
    }

    public func togglePlay() {
        if isPlaying { pause() } else { play() }
    }

    public func rewind() {
        seek(to: loopRange?.lowerBound ?? 0)
    }

    public func seek(to seconds: Double) {
        let total = renderState.withLock { $0.plan.totalDuration }
        let clamped = total > 0 ? min(max(0, seconds), total) : max(0, seconds)
        renderState.withLock {
            $0.currentTime = clamped
            $0.reachedEnd = false
        }
        currentTime = clamped
        onTime?(clamped)
    }

    public func shutdown() {
        pause()
        audioEngine?.stop()
        audioEngine = nil
        sourceNode = nil
    }

    // MARK: AVAudioEngine Setup

    private func ensureAudioEngineStarted() {
        if let engine = audioEngine, engine.isRunning { return }
        let engine = AVAudioEngine()
        let outRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let sampleRate = outRate > 0 ? outRate : 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }

        let state = self.renderState
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let n = Int(frameCount)
            guard abl.count >= 2,
                  let outL = abl[0].mData?.assumingMemoryBound(to: Float.self),
                  let outR = abl[1].mData?.assumingMemoryBound(to: Float.self) else {
                for buf in abl {
                    if let ptr = buf.mData { memset(ptr, 0, Int(buf.mDataByteSize)) }
                }
                return noErr
            }

            let snapshot = state.withLock { s -> (playing: Bool, time: Double, plan: RenderPlan, loop: ClosedRange<Double>?) in
                (s.playing, s.currentTime, s.plan, s.loopRangeOverride ?? s.plan.loopRange)
            }

            guard snapshot.playing else {
                vDSP_vclr(outL, 1, vDSP_Length(n))
                vDSP_vclr(outR, 1, vDSP_Length(n))
                return noErr
            }

            let (pL, pR) = snapshot.plan.render(
                startTime: snapshot.time,
                frameCount: n,
                sampleRate: sampleRate,
                outLeft: outL,
                outRight: outR
            )

            let dt = Double(n) / sampleRate
            var nextTime = snapshot.time + dt
            var ended = false

            if let loop = snapshot.loop, loop.upperBound > loop.lowerBound + 0.01 {
                if nextTime >= loop.upperBound {
                    nextTime = loop.lowerBound + (nextTime - loop.upperBound).truncatingRemainder(dividingBy: loop.upperBound - loop.lowerBound)
                }
            } else if snapshot.plan.totalDuration > 0, nextTime >= snapshot.plan.totalDuration {
                nextTime = snapshot.plan.totalDuration
                ended = true
            }

            state.withLock { s in
                if s.playing {
                    s.currentTime = nextTime
                    s.peakLeft = max(s.peakLeft * 0.7, pL)
                    s.peakRight = max(s.peakRight * 0.7, pR)
                    if ended {
                        s.playing = false
                        s.reachedEnd = true
                    }
                }
            }
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            self.audioEngine = engine
            self.sourceNode = node
            self.engineProducesFrames = true
        } catch {
            self.engineProducesFrames = false
        }
    }

    private func startDisplayTimer() {
        stopDisplayTimer()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickDisplay() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopDisplayTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tickDisplay() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = max(0, now - lastTickUptime)
        lastTickUptime = now

        let status = renderState.withLock { s -> (time: Double, pL: Float, pR: Float, ended: Bool, playing: Bool) in
            if !engineProducesFrames, s.playing {
                var next = s.currentTime + elapsed
                let loop = s.loopRangeOverride ?? s.plan.loopRange
                if let loop, loop.upperBound > loop.lowerBound + 0.01, next >= loop.upperBound {
                    next = loop.lowerBound
                } else if s.plan.totalDuration > 0, next >= s.plan.totalDuration {
                    next = s.plan.totalDuration
                    s.playing = false
                    s.reachedEnd = true
                }
                s.currentTime = next
            }
            return (s.currentTime, s.peakLeft, s.peakRight, s.reachedEnd, s.playing)
        }

        if abs(status.time - currentTime) > 1e-4 {
            currentTime = status.time
            onTime?(status.time)
        }
        meterLeft = min(status.pL, 1.0)
        meterRight = min(status.pR, 1.0)

        if status.ended || !status.playing {
            pause()
        }
    }
}
