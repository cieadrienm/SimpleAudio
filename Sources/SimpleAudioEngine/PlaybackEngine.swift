import Accelerate
import AppKit
import AudioToolbox
import AVFoundation
import Foundation
import Observation
import SimpleAudioCore

/// Apple's built-in 16-channel multitimbral GM/GS SoundFont & DLS synthesizer (`kAudioUnitSubType_MIDISynth`).
public final class AppleMIDISynth: AVAudioUnitMIDIInstrument, @unchecked Sendable {
    public private(set) var loadedBankURL: URL

    public init(soundBankURL: URL? = nil) throws {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: kAudioUnitSubType_MIDISynth,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        let resolvedURL = soundBankURL ?? SoundfontLibrary.systemDLSURL
        self.loadedBankURL = resolvedURL
        super.init(audioComponentDescription: description)

        try setSoundBankURL(resolvedURL)
    }

    public func setSoundBankURL(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudio_FileNotFoundError))
        }
        var bankURL: Unmanaged<CFURL> = Unmanaged.passUnretained(url as CFURL)
        let status = AudioUnitSetProperty(
            self.audioUnit,
            AudioUnitPropertyID(kMusicDeviceProperty_SoundBankURL),
            AudioUnitScope(kAudioUnitScope_Global),
            0,
            &bankURL,
            UInt32(MemoryLayout<Unmanaged<CFURL>>.size)
        )
        if status != noErr {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        self.loadedBankURL = url
    }

    public func preload(configs: [MIDIRenderPlan.ChannelConfig]) {
        let au = self.audioUnit
        var enabledBit: UInt32 = 1
        _ = AudioUnitSetProperty(
            au,
            AudioUnitPropertyID(kAUMIDISynthProperty_EnablePreload),
            AudioUnitScope(kAudioUnitScope_Global),
            0,
            &enabledBit,
            UInt32(MemoryLayout<UInt32>.size)
        )
        MusicDeviceMIDIEvent(au, 0xC0, 0, 0, 0)
        MusicDeviceMIDIEvent(au, 0xC9, 0, 0, 0)
        for cfg in configs {
            let ch = cfg.channel & 0x0F
            MusicDeviceMIDIEvent(au, UInt32(0xC0 | ch), UInt32(cfg.program & 0x7F), 0, 0)
        }
        enabledBit = 0
        _ = AudioUnitSetProperty(
            au,
            AudioUnitPropertyID(kAUMIDISynthProperty_EnablePreload),
            AudioUnitScope(kAudioUnitScope_Global),
            0,
            &enabledBit,
            UInt32(MemoryLayout<UInt32>.size)
        )
        applyChannelConfigs(configs)
    }

    public func applyChannelConfigs(_ configs: [MIDIRenderPlan.ChannelConfig]) {
        let au = self.audioUnit
        for cfg in configs {
            let ch = cfg.channel & 0x0F
            if ch == 9 {
                MusicDeviceMIDIEvent(au, UInt32(0xB0 | ch), 0, 120, 0)
                MusicDeviceMIDIEvent(au, UInt32(0xB0 | ch), 32, 0, 0)
            } else {
                MusicDeviceMIDIEvent(au, UInt32(0xB0 | ch), 0, 0, 0)
                MusicDeviceMIDIEvent(au, UInt32(0xB0 | ch), 32, 0, 0)
            }
            MusicDeviceMIDIEvent(au, UInt32(0xC0 | ch), UInt32(cfg.program & 0x7F), 0, 0)
            MusicDeviceMIDIEvent(au, UInt32(0xB0 | ch), 7, UInt32(cfg.volumeCC & 0x7F), 0)
            MusicDeviceMIDIEvent(au, UInt32(0xB0 | ch), 10, UInt32(cfg.panCC & 0x7F), 0)
        }
    }

    public func allNotesOff() {
        let au = self.audioUnit
        for ch: UInt32 in 0..<16 {
            MusicDeviceMIDIEvent(au, 0xB0 | ch, 123, 0, 0)
            MusicDeviceMIDIEvent(au, 0xB0 | ch, 120, 0, 0)
        }
    }
}

/// Immutable pre-compiled MIDI note event for lock-free real-time synthesis and offline bounce.
public struct ScheduledNote: Sendable {
    public let start: Double
    public let end: Double
    public let releaseEnd: Double
    public let pitch: Int
    public let frequency: Float
    public let velocity: Float
    public let midiVelocity: UInt8
    public let leftGain: Float
    public let rightGain: Float
    public let program: Int
    public let isDrum: Bool
    public let channel: Int
    public let synthChannel: UInt8

    public init(
        start: Double,
        end: Double,
        releaseEnd: Double,
        pitch: Int,
        frequency: Float,
        velocity: Float,
        midiVelocity: UInt8 = 100,
        leftGain: Float,
        rightGain: Float,
        program: Int,
        isDrum: Bool,
        channel: Int,
        synthChannel: UInt8 = 0
    ) {
        self.start = start
        self.end = end
        self.releaseEnd = releaseEnd
        self.pitch = pitch
        self.frequency = frequency > 0 ? frequency : Float(440.0 * pow(2.0, Double(pitch - 69) / 12.0))
        self.velocity = velocity
        self.midiVelocity = midiVelocity
        self.leftGain = leftGain
        self.rightGain = rightGain
        self.program = program
        self.isDrum = isDrum
        self.channel = channel
        self.synthChannel = synthChannel
    }
}

/// Immutable MIDI render plan built from an `AudioProject`'s MIDI tracks.
public struct MIDIRenderPlan: Sendable {
    public struct ChannelConfig: Sendable, Equatable {
        public let channel: UInt8
        public let program: UInt8
        public let volumeCC: UInt8
        public let panCC: UInt8
    }

    private static let melodicChannels: [UInt8] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14]

    public let notes: [ScheduledNote]
    public let channelConfigs: [ChannelConfig]
    public let totalDuration: Double
    public let playbackRate: Double
    public let loopRange: ClosedRange<Double>?
    public let masterGain: Float

    public init(project: AudioProject, onlyTrackID: UUID? = nil, forcedProgram: Int? = nil) {
        let master = Float(project.masterLinearGain)
        var compiled: [ScheduledNote] = []
        compiled.reserveCapacity(project.noteCount)
        var configs: [ChannelConfig] = []
        var melodicIndex = 0

        for track in project.tracks where !track.notes.isEmpty || track.isMIDI {
            if let onlyTrackID, track.id != onlyTrackID { continue }
            if onlyTrackID == nil && !project.isTrackAudible(track) { continue }

            let trackGain = Float(track.linearGain) * master
            guard trackGain > 1e-5 else { continue }

            let isDrum = track.isDrum || track.channel == 9
            let synthCh: UInt8
            if isDrum {
                synthCh = 9
            } else {
                synthCh = Self.melodicChannels[melodicIndex % Self.melodicChannels.count]
                melodicIndex += 1
            }

            let effectiveProgram = isDrum ? 0 : (forcedProgram ?? track.program)

            let panClamped = min(max(track.pan, -1.0), 1.0)
            let angle = (panClamped + 1.0) * (.pi / 4.0)
            let leftPan = Float(cos(angle)) * trackGain
            let rightPan = Float(sin(angle)) * trackGain

            let volCC = UInt8(min(max(Int((min(trackGain, 1.5) / 1.0 * 108.0).rounded()), 1), 127))
            let panCC = UInt8(min(max(Int(((panClamped + 1.0) * 0.5 * 127.0).rounded()), 0), 127))
            configs.append(
                ChannelConfig(
                    channel: synthCh,
                    program: UInt8(min(max(effectiveProgram, 0), 127)),
                    volumeCC: volCC,
                    panCC: panCC
                )
            )

            let releaseTail = Self.releaseTime(program: effectiveProgram, isDrum: isDrum)

            for note in track.notes where !note.mute {
                let effectivePitch = min(max(note.pitch + (isDrum ? 0 : track.transpose), 0), 127)
                let freq = Float(440.0 * pow(2.0, Double(effectivePitch - 69) / 12.0))
                let vel = Float(note.normalizedVelocity)
                let scaledMidiVel = UInt8(min(max(Int((Double(note.velocity) * min(Double(trackGain), 1.35)).rounded()), 1), 127))
                let start = note.start
                let end = note.end
                compiled.append(
                    ScheduledNote(
                        start: start,
                        end: end,
                        releaseEnd: end + releaseTail,
                        pitch: effectivePitch,
                        frequency: freq,
                        velocity: vel,
                        midiVelocity: scaledMidiVel,
                        leftGain: leftPan,
                        rightGain: rightPan,
                        program: effectiveProgram,
                        isDrum: isDrum,
                        channel: track.channel,
                        synthChannel: synthCh
                    )
                )
            }
        }

        compiled.sort { $0.start < $1.start }
        self.notes = compiled
        self.channelConfigs = configs
        self.totalDuration = project.totalDuration
        self.playbackRate = min(max(project.playbackRate, 0.25), 2.0)
        self.loopRange = project.loopRange
        self.masterGain = master
    }

    public static func releaseTime(program: Int, isDrum: Bool) -> Double {
        if isDrum { return 0.08 }
        switch program {
        case 0...7: return 0.22
        case 8...15: return 0.28
        case 16...23: return 0.08
        case 24...39: return 0.16
        case 40...55, 88...95: return 0.28
        default: return 0.15
        }
    }

    @inline(__always)
    public func meterEnvelope(at t: Double) -> (Float, Float) {
        guard !notes.isEmpty, t >= 0 else { return (0, 0) }
        var left: Float = 0
        var right: Float = 0
        for n in notes {
            if n.start > t { break }
            if t >= n.releaseEnd { continue }
            let age = Float(t - n.start)
            let dur = Float(max(0.02, n.end - n.start))
            let decay = exp(-1.8 * age)
            let release: Float = age > dur ? max(0, 1.0 - (age - dur) / Float(max(0.04, n.releaseEnd - n.end))) : 1.0
            let amp = n.velocity * (0.35 + 0.65 * decay) * release
            left += amp * n.leftGain
            right += amp * n.rightGain
        }
        return (min(1.0, left * 0.55), min(1.0, right * 0.55))
    }

    @inline(__always)
    public func sample(at t: Double) -> (Float, Float) {
        guard !notes.isEmpty, t >= 0 else { return (0, 0) }
        var left: Float = 0
        var right: Float = 0

        for n in notes {
            if n.start > t { break }
            if t >= n.releaseEnd { continue }
            let localTime = t - n.start
            let noteDur = n.end - n.start
            let s = Self.synthesizeVoice(note: n, localTime: localTime, noteDuration: noteDur)
            left += s * n.leftGain
            right += s * n.rightGain
        }

        let scale: Float = 0.26
        return (tanh(left * scale), tanh(right * scale))
    }

    @inline(__always)
    public static func synthesizeVoice(note: ScheduledNote, localTime: Double, noteDuration: Double) -> Float {
        guard localTime >= 0 else { return 0 }
        let t = Float(localTime)
        let dur = Float(max(0.01, noteDuration))
        let vel = note.velocity

        if note.isDrum {
            return synthesizeDrum(pitch: note.pitch, t: t, velocity: vel)
        }

        let f = note.frequency
        let omega = 2.0 * Float.pi * f * t

        let prog = note.program
        let attack: Float
        let decayRate: Float
        let sustainLevel: Float
        let releaseLen = Float(max(0.02, note.releaseEnd - note.end))

        switch prog {
        case 0...7:
            attack = 0.004; decayRate = 1.6; sustainLevel = 0.35
        case 8...15:
            attack = 0.002; decayRate = 3.2; sustainLevel = 0.15
        case 16...23:
            attack = 0.008; decayRate = 0.2; sustainLevel = 0.90
        case 24...31:
            attack = 0.004; decayRate = 2.2; sustainLevel = 0.28
        case 32...39:
            attack = 0.005; decayRate = 1.8; sustainLevel = 0.45
        case 40...55, 88...95:
            attack = 0.045; decayRate = 0.5; sustainLevel = 0.82
        case 56...79:
            attack = 0.018; decayRate = 0.7; sustainLevel = 0.78
        default:
            attack = 0.006; decayRate = 0.9; sustainLevel = 0.68
        }

        let envAttack = min(t / attack, 1.0)
        let envDecay = sustainLevel + (1.0 - sustainLevel) * exp(-decayRate * max(0, t - attack))
        var env = envAttack * envDecay

        if t > dur {
            let relProgress = (t - dur) / releaseLen
            if relProgress >= 1.0 { return 0 }
            let releaseFactor = 1.0 - relProgress
            env *= (releaseFactor * releaseFactor)
        }

        let sig: Float
        switch prog {
        case 0...7:
            let h1 = sin(omega)
            let h2 = 0.42 * vel * sin(2.0 * omega) * exp(-1.2 * t)
            let h3 = 0.18 * vel * sin(3.0 * omega) * exp(-2.4 * t)
            let h4 = 0.08 * vel * sin(4.0 * omega) * exp(-4.0 * t)
            sig = h1 + h2 + h3 + h4
        case 8...15:
            let h1 = sin(omega)
            let h2 = 0.35 * sin(2.0 * omega)
            let h3 = 0.22 * sin(2.756 * omega) * exp(-3.5 * t)
            sig = h1 + h2 + h3
        case 16...23:
            sig = 0.55 * sin(omega) + 0.35 * sin(2.0 * omega) + 0.20 * sin(3.0 * omega) + 0.12 * sin(4.0 * omega)
        case 32...39:
            let h1 = sin(omega)
            let h2 = 0.52 * sin(2.0 * omega) * exp(-1.5 * t)
            let h3 = 0.20 * sin(3.0 * omega) * exp(-3.0 * t)
            sig = h1 + h2 + h3
        case 40...55, 88...95:
            let detune = 2.0 * Float.pi * (f * 1.003) * t
            let h1 = 0.55 * (sin(omega) + 0.7 * sin(detune))
            let h2 = 0.28 * sin(2.0 * omega)
            let h3 = 0.14 * sin(3.0 * omega)
            sig = h1 + h2 + h3
        default:
            let h1 = sin(omega)
            let h2 = 0.40 * sin(2.0 * omega)
            let h3 = 0.22 * sin(3.0 * omega)
            let h4 = 0.10 * sin(4.0 * omega)
            sig = h1 + h2 + h3 + h4
        }

        return sig * env * vel
    }

    @inline(__always)
    public static func synthesizeDrum(pitch: Int, t: Float, velocity: Float) -> Float {
        guard t >= 0 else { return 0 }
        let seed = UInt32(bitPattern: Int32((t * 48_000.0).rounded())) &* 1_664_525 &+ 1_013_904_223
        let noise = Float(Int32(bitPattern: seed)) / Float(Int32.max)

        switch pitch {
        case 35, 36:
            guard t < 0.26 else { return 0 }
            let env = exp(-14.0 * t)
            let phase = 2.0 * Float.pi * (44.0 * t + (90.0 / 28.0) * (1.0 - exp(-28.0 * t)))
            let click = noise * exp(-90.0 * t) * 0.25
            return (sin(phase) * env + click) * velocity * 1.35
        case 37, 38, 39, 40:
            guard t < 0.24 else { return 0 }
            let tone = sin(2.0 * Float.pi * 185.0 * t) * exp(-22.0 * t) * 0.55
            let snap = noise * exp(-16.0 * t) * 0.75
            return (tone + snap) * velocity * 1.15
        case 42, 44:
            guard t < 0.09 else { return 0 }
            let metallic = sin(2.0 * Float.pi * 6200.0 * t) * 0.3 + noise * 0.7
            return metallic * exp(-42.0 * t) * velocity * 0.75
        case 46, 49, 51, 52, 55:
            guard t < 0.35 else { return 0 }
            let metallic = (sin(2.0 * Float.pi * 5400.0 * t) + sin(2.0 * Float.pi * 7850.0 * t)) * 0.25 + noise * 0.65
            return metallic * exp(-10.0 * t) * velocity * 0.80
        default:
            guard t < 0.28 else { return 0 }
            let baseFreq = Float(90.0 + Double(max(0, min(pitch - 40, 30))) * 6.0)
            let env = exp(-13.0 * t)
            return sin(2.0 * Float.pi * baseFreq * t) * env * velocity
        }
    }
}

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
/// Combines sample-accurate Audio clip mixing with polyphonic MIDI synthesis (`MIDIRenderPlan`).
public struct RenderPlan: @unchecked Sendable {
    public let tracks: [PreparedTrack]
    public let midiPlan: MIDIRenderPlan
    public let masterGain: Float
    public let totalDuration: Double
    public let playbackRate: Double
    public let loopRange: ClosedRange<Double>?

    public var hasRenderableContent: Bool {
        !tracks.isEmpty || !midiPlan.notes.isEmpty
    }

    public init(
        project: AudioProject,
        projectURL: URL?,
        pcmStore: PCMStore = .shared,
        preloadMissing: Bool = false,
        forcedMIDIProgram: Int? = nil
    ) {
        self.masterGain = Float(project.masterLinearGain)
        self.totalDuration = project.totalDuration
        self.playbackRate = min(max(project.playbackRate, 0.25), 2.0)
        self.loopRange = project.loopRange
        self.midiPlan = MIDIRenderPlan(project: project, forcedProgram: forcedMIDIProgram)

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
        outRight: UnsafeMutablePointer<Float>,
        synthesizeMIDI: Bool = true
    ) -> (peakL: Float, peakR: Float) {
        let count = vDSP_Length(frameCount)
        vDSP_vclr(outLeft, 1, count)
        vDSP_vclr(outRight, 1, count)
        guard (hasRenderableContent), masterGain > 1e-6, sampleRate > 0, frameCount > 0 else { return (0, 0) }

        let dt = (1.0 / sampleRate) * playbackRate
        let endTime = startTime + Double(frameCount) * dt

        for track in tracks {
            let tL = track.leftGain * masterGain
            let tR = track.rightGain * masterGain
            for item in track.clips {
                let c = item.clip
                guard c.end > startTime, c.offset < endTime else { continue }
                let firstFrame = max(0, Int(((c.offset - startTime) / dt).rounded(.down)))
                let lastFrame = min(frameCount, Int(((c.end - startTime) / dt).rounded(.up)))
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

        if synthesizeMIDI && !midiPlan.notes.isEmpty {
            for i in 0..<frameCount {
                let t = startTime + Double(i) * dt
                let (mL, mR) = midiPlan.sample(at: t)
                outLeft[i] += mL
                outRight[i] += mR
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
    struct ActiveSynthNote {
        var channel: UInt8
        var pitch: UInt8
        var end: Double
    }

    private let lock = NSLock()
    var plan = RenderPlan(project: AudioProject(), projectURL: nil)
    var playing = false
    var currentTime: Double = 0
    var bufferUptime: Double = 0
    var loopRangeOverride: ClosedRange<Double>?
    var peakLeft: Float = 0
    var peakRight: Float = 0
    var reachedEnd = false
    var previewVoices: [ScheduledNote] = []
    var activeSynthNotes: [ActiveSynthNote] = []
    var needsSynthSync = true
    var useAppleSynth = true
    var synthUnit: AudioUnit?
    var previewGenerations: [UInt16: UInt64] = [:]

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
    public private(set) var activeSoundfontURL: URL?
    public private(set) var activePreset: SoundPreset = SoundfontLibrary.shared.activePreset

    public var activeSoundfontName: String {
        if let url = activeSoundfontURL {
            return url.deletingPathExtension().lastPathComponent
        }
        return activePreset.title
    }

    public var usesSampledInstruments: Bool {
        activeSoundfontURL != nil || (activePreset.usesAppleDLS && SoundfontLibrary.hasSystemDLS)
    }

    public var loopRange: ClosedRange<Double>? {
        didSet {
            renderState.withLock { $0.loopRangeOverride = loopRange }
        }
    }

    @ObservationIgnored public var onTime: ((Double) -> Void)?

    @ObservationIgnored private let renderState = PlaybackRenderState()
    @ObservationIgnored private var lastProject = AudioProject()
    @ObservationIgnored private var lastProjectURL: URL?
    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var sourceNode: AVAudioSourceNode?
    @ObservationIgnored private var midiSynth: AppleMIDISynth?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTickUptime: Double = 0
    @ObservationIgnored private var engineProducesFrames = false

    public init() {
        self.activePreset = SoundfontLibrary.shared.activePreset
    }

    public func setPreset(_ preset: SoundPreset) {
        SoundfontLibrary.shared.activePreset = preset
        self.activePreset = preset
        let plan = RenderPlan(
            project: lastProject,
            projectURL: lastProjectURL,
            pcmStore: .shared,
            preloadMissing: false,
            forcedMIDIProgram: preset.forcedProgram
        )
        let sampled = usesSampledInstruments
        renderState.withLock { state in
            state.plan = plan
            state.needsSynthSync = true
            state.useAppleSynth = sampled
        }
        if let synth = midiSynth {
            synth.allNotesOff()
            synth.preload(configs: plan.midiPlan.channelConfigs)
        }
    }

    @discardableResult
    public func loadSoundfont(_ url: URL?) -> Bool {
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            activeSoundfontURL = nil
            let sampled = usesSampledInstruments
            renderState.withLock {
                $0.needsSynthSync = true
                $0.useAppleSynth = sampled
            }
            if let synth = midiSynth, SoundfontLibrary.hasSystemDLS {
                try? synth.setSoundBankURL(SoundfontLibrary.systemDLSURL)
                let cfgs = renderState.withLock { $0.plan.midiPlan.channelConfigs }
                synth.preload(configs: cfgs)
            }
            return false
        }
        let ext = url.pathExtension.lowercased()
        guard ext == "sf2" || ext == "dls" else { return false }
        activeSoundfontURL = url
        SoundfontLibrary.shared.recordRecent(url)
        let sampled = usesSampledInstruments
        renderState.withLock {
            $0.needsSynthSync = true
            $0.useAppleSynth = sampled
        }
        if let synth = midiSynth {
            do {
                synth.allNotesOff()
                try synth.setSoundBankURL(url)
                let cfgs = renderState.withLock { $0.plan.midiPlan.channelConfigs }
                synth.preload(configs: cfgs)
            } catch {
                shutdown()
            }
        }
        return true
    }

    public func update(project: AudioProject, projectURL: URL?, soundfontURL: URL? = nil) {
        self.lastProject = project
        self.lastProjectURL = projectURL
        let plan = RenderPlan(
            project: project,
            projectURL: projectURL,
            pcmStore: .shared,
            preloadMissing: false,
            forcedMIDIProgram: activePreset.forcedProgram
        )
        let sampled = usesSampledInstruments
        renderState.withLock { state in
            state.plan = plan
            state.needsSynthSync = true
            state.useAppleSynth = sampled
            if state.currentTime > max(plan.totalDuration, 0.01) && plan.totalDuration > 0 {
                state.currentTime = plan.totalDuration
            }
        }
        if currentTime > project.totalDuration && project.totalDuration > 0 {
            currentTime = project.totalDuration
            onTime?(currentTime)
        }

        if let sf = soundfontURL {
            loadSoundfont(sf)
        } else if let path = project.soundfontPath, !path.isEmpty {
            loadSoundfont(URL(fileURLWithPath: path))
        } else if let synth = midiSynth {
            synth.applyChannelConfigs(plan.midiPlan.channelConfigs)
        }
    }

    public func schedule(project: AudioProject, projectURL: URL? = nil) {
        update(project: project, projectURL: projectURL)
    }

    /// Auditions a single MIDI note in real time (e.g. when clicking or dragging a note or piano key in the Piano-Roll).
    public func previewNote(
        pitch: Int,
        velocity: Int = 100,
        program: Int = 0,
        isDrum: Bool = false,
        duration: Double = 0.24
    ) {
        ensureAudioEngineStarted()
        let p = min(max(pitch, 0), 127)
        let effProgram = isDrum ? 0 : (activePreset.forcedProgram ?? program)
        let freq = Float(440.0 * pow(2.0, Double(p - 69) / 12.0))
        let vel = Float(min(max(velocity, 1), 127)) / 127.0
        let note = ScheduledNote(
            start: 0,
            end: duration,
            releaseEnd: duration + 0.14,
            pitch: p,
            frequency: freq,
            velocity: vel,
            midiVelocity: UInt8(min(max(velocity, 1), 127)),
            leftGain: 0.72,
            rightGain: 0.72,
            program: effProgram,
            isDrum: isDrum,
            channel: isDrum ? 9 : 15,
            synthChannel: isDrum ? 9 : 15
        )
        renderState.withLock { s in
            s.previewVoices.append(note)
            if s.previewVoices.count > 8 {
                s.previewVoices.removeFirst(s.previewVoices.count - 8)
            }
            s.peakLeft = max(s.peakLeft, vel * 0.65)
            s.peakRight = max(s.peakRight, vel * 0.65)
        }

        if let synth = midiSynth, usesSampledInstruments {
            let au = synth.audioUnit
            let ch: UInt8 = isDrum ? 9 : 15
            let pVal = UInt8(p)
            let vVal = UInt8(min(max(velocity, 1), 127))
            if !isDrum {
                MusicDeviceMIDIEvent(au, UInt32(0xC0 | ch), UInt32(effProgram & 0x7F), 0, 0)
                MusicDeviceMIDIEvent(au, UInt32(0xB0 | ch), 7, 114, 0)
                MusicDeviceMIDIEvent(au, UInt32(0xB0 | ch), 10, 64, 0)
            }
            MusicDeviceMIDIEvent(au, UInt32(0x80 | ch), UInt32(pVal), 0, 0)
            MusicDeviceMIDIEvent(au, UInt32(0x90 | ch), UInt32(pVal), UInt32(vVal), 0)

            let key = (UInt16(ch) << 8) | UInt16(pVal)
            let gen = renderState.withLock { s -> UInt64 in
                let next = (s.previewGenerations[key] ?? 0) &+ 1
                s.previewGenerations[key] = next
                return next
            }
            let state = renderState
            DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + duration) { [weak synth] in
                guard let synth else { return }
                let currentGen = state.withLock { $0.previewGenerations[key] }
                if currentGen == gen {
                    MusicDeviceMIDIEvent(synth.audioUnit, UInt32(0x80 | ch), UInt32(pVal), 0, 0)
                }
            }
        }
    }

    public func previewNote(
        pitch: Int,
        velocity: Int = 100,
        channel: Int,
        program: Int = 0,
        duration: Double = 0.24
    ) {
        previewNote(
            pitch: pitch,
            velocity: velocity,
            program: program,
            isDrum: channel == 9,
            duration: duration
        )
    }

    public func play() {
        guard !isPlaying else { return }
        let total = renderState.withLock { $0.plan.totalDuration }
        if total > 0, currentTime >= total - 0.01 {
            seek(to: loopRange?.lowerBound ?? 0)
        }
        ensureAudioEngineStarted()
        let nowUptime = ProcessInfo.processInfo.systemUptime
        lastTickUptime = nowUptime
        let cfgs = renderState.withLock { s -> [MIDIRenderPlan.ChannelConfig] in
            s.playing = true
            s.reachedEnd = false
            s.needsSynthSync = true
            s.bufferUptime = nowUptime
            return s.plan.midiPlan.channelConfigs
        }
        midiSynth?.applyChannelConfigs(cfgs)
        isPlaying = true
        startDisplayTimer()
    }

    public func pause() {
        guard isPlaying else { return }
        renderState.withLock {
            $0.playing = false
            $0.needsSynthSync = true
            $0.activeSynthNotes.removeAll()
            $0.peakLeft = 0
            $0.peakRight = 0
        }
        midiSynth?.allNotesOff()
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
        let nowUptime = ProcessInfo.processInfo.systemUptime
        renderState.withLock {
            $0.currentTime = clamped
            $0.bufferUptime = nowUptime
            $0.reachedEnd = false
            $0.needsSynthSync = true
            $0.activeSynthNotes.removeAll()
        }
        midiSynth?.allNotesOff()
        currentTime = clamped
        onTime?(clamped)
    }

    public func shutdown() {
        pause()
        midiSynth?.allNotesOff()
        audioEngine?.stop()
        audioEngine = nil
        sourceNode = nil
        midiSynth = nil
    }

    // MARK: AVAudioEngine Setup

    private func ensureAudioEngineStarted() {
        let isAutomated = CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--snapshot")
        guard !isAutomated else { return }
        if let engine = audioEngine, engine.isRunning { return }
        let engine = AVAudioEngine()
        let outRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let sampleRate = outRate > 0 ? outRate : 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }

        let bankURL = activeSoundfontURL ?? (SoundfontLibrary.hasSystemDLS ? SoundfontLibrary.systemDLSURL : nil)
        var attachedSynth: AppleMIDISynth?
        if let bankURL, let synth = try? AppleMIDISynth(soundBankURL: bankURL) {
            engine.attach(synth)
            engine.connect(synth, to: engine.mainMixerNode, format: format)
            attachedSynth = synth
            self.midiSynth = synth
        }

        let sampled = usesSampledInstruments
        let cfgs = renderState.withLock { s -> [MIDIRenderPlan.ChannelConfig] in
            s.useAppleSynth = sampled && attachedSynth != nil
            s.synthUnit = attachedSynth?.audioUnit
            return s.plan.midiPlan.channelConfigs
        }

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

            let snapshot = state.withLock { s -> (
                playing: Bool,
                time: Double,
                plan: RenderPlan,
                loop: ClosedRange<Double>?,
                useApple: Bool,
                synthUnit: AudioUnit?,
                syncNeeded: Bool,
                activeNotes: [PlaybackRenderState.ActiveSynthNote],
                previews: [ScheduledNote]
            ) in
                (
                    s.playing,
                    s.currentTime,
                    s.plan,
                    s.loopRangeOverride ?? s.plan.loopRange,
                    s.useAppleSynth && s.synthUnit != nil,
                    s.synthUnit,
                    s.needsSynthSync,
                    s.activeSynthNotes,
                    s.previewVoices
                )
            }

            let rawDt = 1.0 / sampleRate
            let dt = rawDt * snapshot.plan.playbackRate
            var activeNotes = snapshot.activeNotes
            var syncNeeded = snapshot.syncNeeded
            var previews = snapshot.previews
            var pL: Float = 0
            var pR: Float = 0

            if snapshot.playing {
                // Render audio clips (+ analytic MIDI if AppleMIDISynth is not used)
                let (audioPL, audioPR) = snapshot.plan.render(
                    startTime: snapshot.time,
                    frameCount: n,
                    sampleRate: sampleRate,
                    outLeft: outL,
                    outRight: outR,
                    synthesizeMIDI: !snapshot.useApple
                )
                pL = audioPL
                pR = audioPR

                // If AppleMIDISynth is active and MIDI notes exist, schedule sample-accurate MIDI events
                if snapshot.useApple, let au = snapshot.synthUnit, !snapshot.plan.midiPlan.notes.isEmpty {
                    let midiPlan = snapshot.plan.midiPlan
                    let t0 = snapshot.time
                    let t1 = t0 + Double(n) * dt

                    if syncNeeded {
                        for act in activeNotes {
                            MusicDeviceMIDIEvent(au, UInt32(0x80 | act.channel), UInt32(act.pitch), 0, 0)
                        }
                        activeNotes.removeAll(keepingCapacity: true)
                        for cfg in midiPlan.channelConfigs {
                            let ch = cfg.channel & 0x0F
                            MusicDeviceMIDIEvent(au, UInt32(0xC0 | ch), UInt32(cfg.program & 0x7F), 0, 0)
                            MusicDeviceMIDIEvent(au, UInt32(0xB0 | ch), 7, UInt32(cfg.volumeCC & 0x7F), 0)
                            MusicDeviceMIDIEvent(au, UInt32(0xB0 | ch), 10, UInt32(cfg.panCC & 0x7F), 0)
                        }
                        for note in midiPlan.notes {
                            if note.start > t0 { break }
                            if note.start < t0 && note.end > t0 + 0.005 {
                                let ch = note.synthChannel & 0x0F
                                let p = UInt8(min(max(note.pitch, 0), 127))
                                MusicDeviceMIDIEvent(au, UInt32(0x90 | ch), UInt32(p), UInt32(note.midiVelocity), 0)
                                activeNotes.append(PlaybackRenderState.ActiveSynthNote(channel: ch, pitch: p, end: note.end))
                            }
                        }
                        syncNeeded = false
                    }

                    var idx = activeNotes.count - 1
                    while idx >= 0 {
                        let act = activeNotes[idx]
                        if act.end <= t1 {
                            let offset = UInt32(min(max(Int(((act.end - t0) / max(dt, 1e-9)).rounded()), 0), max(0, n - 1)))
                            MusicDeviceMIDIEvent(au, UInt32(0x80 | act.channel), UInt32(act.pitch), 0, offset)
                            activeNotes.remove(at: idx)
                        }
                        idx -= 1
                    }

                    for note in midiPlan.notes {
                        if note.start < t0 { continue }
                        if note.start >= t1 { break }
                        let ch = note.synthChannel & 0x0F
                        let p = UInt8(min(max(note.pitch, 0), 127))
                        let offset = UInt32(min(max(Int(((note.start - t0) / max(dt, 1e-9)).rounded()), 0), max(0, n - 1)))

                        if let existingIdx = activeNotes.firstIndex(where: { $0.channel == ch && $0.pitch == p }) {
                            MusicDeviceMIDIEvent(au, UInt32(0x80 | ch), UInt32(p), 0, offset)
                            activeNotes.remove(at: existingIdx)
                        }
                        MusicDeviceMIDIEvent(au, UInt32(0x90 | ch), UInt32(p), UInt32(note.midiVelocity), offset)

                        if note.end <= t1 {
                            let endOffset = max(offset + 1, UInt32(min(max(Int(((note.end - t0) / max(dt, 1e-9)).rounded()), 0), max(0, n - 1))))
                            MusicDeviceMIDIEvent(au, UInt32(0x80 | ch), UInt32(p), 0, endOffset)
                        } else {
                            activeNotes.append(PlaybackRenderState.ActiveSynthNote(channel: ch, pitch: p, end: note.end))
                        }
                    }

                    let (envL, envR) = midiPlan.meterEnvelope(at: t0)
                    pL = max(pL, envL)
                    pR = max(pR, envR)
                }
            } else {
                vDSP_vclr(outL, 1, vDSP_Length(n))
                vDSP_vclr(outR, 1, vDSP_Length(n))
            }

            // Preview voices (analytic fallback or meter tracking)
            if !previews.isEmpty {
                if snapshot.useApple {
                    let blockSpan = Double(n) * rawDt
                    for pIdx in previews.indices {
                        let voice = previews[pIdx]
                        let elapsed = -voice.start
                        pL = max(pL, voice.velocity * 0.65)
                        pR = max(pR, voice.velocity * 0.65)
                        previews[pIdx] = ScheduledNote(
                            start: -(elapsed + blockSpan),
                            end: voice.end,
                            releaseEnd: voice.releaseEnd,
                            pitch: voice.pitch,
                            frequency: voice.frequency,
                            velocity: voice.velocity,
                            midiVelocity: voice.midiVelocity,
                            leftGain: voice.leftGain,
                            rightGain: voice.rightGain,
                            program: voice.program,
                            isDrum: voice.isDrum,
                            channel: voice.channel,
                            synthChannel: voice.synthChannel
                        )
                    }
                    previews.removeAll { (-$0.start) >= $0.releaseEnd }
                } else {
                    for i in 0..<n {
                        var sL: Float = 0
                        var sR: Float = 0
                        for pIdx in previews.indices {
                            let voice = previews[pIdx]
                            let elapsed = -voice.start
                            let s = MIDIRenderPlan.synthesizeVoice(note: voice, localTime: elapsed, noteDuration: voice.end)
                            sL += s * voice.leftGain * 0.25
                            sR += s * voice.rightGain * 0.25
                            previews[pIdx] = ScheduledNote(
                                start: -(elapsed + rawDt),
                                end: voice.end,
                                releaseEnd: voice.releaseEnd,
                                pitch: voice.pitch,
                                frequency: voice.frequency,
                                velocity: voice.velocity,
                                midiVelocity: voice.midiVelocity,
                                leftGain: voice.leftGain,
                                rightGain: voice.rightGain,
                                program: voice.program,
                                isDrum: voice.isDrum,
                                channel: voice.channel,
                                synthChannel: voice.synthChannel
                            )
                        }
                        previews.removeAll { (-$0.start) >= $0.releaseEnd }
                        outL[i] += sL
                        outR[i] += sR
                        if abs(outL[i]) > pL { pL = abs(outL[i]) }
                        if abs(outR[i]) > pR { pR = abs(outR[i]) }
                    }
                }
            }

            guard snapshot.playing else {
                state.withLock { s in
                    s.previewVoices = previews
                    if !previews.isEmpty {
                        s.peakLeft = max(s.peakLeft * 0.7, pL)
                        s.peakRight = max(s.peakRight * 0.7, pR)
                    }
                }
                return noErr
            }

            var nextTime = snapshot.time + Double(n) * dt
            var ended = false

            if let loop = snapshot.loop, loop.upperBound > loop.lowerBound + 0.01 {
                if nextTime >= loop.upperBound {
                    nextTime = loop.lowerBound + (nextTime - loop.upperBound).truncatingRemainder(dividingBy: loop.upperBound - loop.lowerBound)
                    syncNeeded = true
                }
            } else if snapshot.plan.totalDuration > 0, nextTime >= snapshot.plan.totalDuration {
                nextTime = snapshot.plan.totalDuration
                ended = true
                if let au = snapshot.synthUnit {
                    for act in activeNotes {
                        MusicDeviceMIDIEvent(au, UInt32(0x80 | act.channel), UInt32(act.pitch), 0, UInt32(max(0, n - 1)))
                    }
                }
                activeNotes.removeAll(keepingCapacity: true)
            }

            let callbackUptime = ProcessInfo.processInfo.systemUptime
            state.withLock { s in
                s.previewVoices = previews
                s.activeSynthNotes = activeNotes
                s.needsSynthSync = syncNeeded
                if s.playing {
                    s.currentTime = nextTime
                    s.bufferUptime = callbackUptime
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
            self.midiSynth?.preload(configs: cfgs)
        } catch {
            self.engineProducesFrames = false
        }
    }

    private func startDisplayTimer() {
        stopDisplayTimer()
        let fps = min(max(NSScreen.main?.maximumFramesPerSecond ?? 60, 60), 120)
        let t = Timer(timeInterval: 1.0 / Double(fps), repeats: true) { [weak self] _ in
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
            if s.playing {
                let sinceCallback = now - s.bufferUptime
                if !engineProducesFrames || sinceCallback > 0.08 {
                    var next = s.currentTime + elapsed * s.plan.playbackRate
                    let loop = s.loopRangeOverride ?? s.plan.loopRange
                    if let loop, loop.upperBound > loop.lowerBound + 0.01, next >= loop.upperBound {
                        next = loop.lowerBound
                    } else if s.plan.totalDuration > 0, next >= s.plan.totalDuration {
                        next = s.plan.totalDuration
                        s.playing = false
                        s.reachedEnd = true
                    }
                    s.currentTime = next
                    s.bufferUptime = now
                    return (next, s.peakLeft, s.peakRight, s.reachedEnd, s.playing)
                } else {
                    let subBufferDt = min(max(0, sinceCallback), 0.045)
                    var visualTime = s.currentTime + subBufferDt * s.plan.playbackRate
                    let loop = s.loopRangeOverride ?? s.plan.loopRange
                    if let loop, loop.upperBound > loop.lowerBound + 0.01 {
                        if visualTime > loop.upperBound {
                            visualTime = loop.upperBound
                        }
                    } else if s.plan.totalDuration > 0, visualTime > s.plan.totalDuration {
                        visualTime = s.plan.totalDuration
                    }
                    return (visualTime, s.peakLeft, s.peakRight, s.reachedEnd, s.playing)
                }
            }
            return (s.currentTime, s.peakLeft, s.peakRight, s.reachedEnd, s.playing)
        }

        if abs(status.time - currentTime) > 1e-5 {
            currentTime = status.time
            onTime?(status.time)
        }
        if abs(status.pL - meterLeft) > 0.002 || (status.pL == 0 && meterLeft != 0) {
            meterLeft = min(status.pL, 1.0)
        }
        if abs(status.pR - meterRight) > 0.002 || (status.pR == 0 && meterRight != 0) {
            meterRight = min(status.pR, 1.0)
        }

        if status.ended || !status.playing {
            pause()
        }
    }
}
