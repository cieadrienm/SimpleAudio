import Foundation

public enum FadeShape: String, Codable, CaseIterable, Sendable, Identifiable {
    case cosine
    case linear
    case exponential
    case logarithmic

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .cosine: return "Courbe S"
        case .linear: return "Linéaire"
        case .exponential: return "Exponentielle"
        case .logarithmic: return "Logarithmique"
        }
    }

    /// Evaluates the fade multiplier in `0...1` at `fraction` (`0` = left edge of fade, `1` = right edge of fade).
    public func gain(at fraction: Double, isIn: Bool) -> Double {
        let t = min(max(fraction, 0), 1)
        let u = isIn ? t : (1.0 - t)
        switch self {
        case .linear:
            return u
        case .cosine:
            return 0.5 * (1.0 - cos(.pi * u))
        case .exponential:
            return u * u
        case .logarithmic:
            return sqrt(u)
        }
    }
}

public struct AudioClip: Identifiable, Equatable, Codable, Sendable {
    public static let minDuration: Double = 0.005

    public var id: UUID
    public var name: String
    public var path: String
    /// Start position on the project timeline (seconds).
    public var offset: Double
    /// Start position inside the source audio file (seconds).
    public var sourceStart: Double
    /// Audible duration of this clip (seconds).
    public var duration: Double
    /// Total duration of the source audio file (seconds).
    public var sourceDuration: Double
    /// Clip gain in dB (`-60...+24`).
    public var gainDB: Double
    /// Clip stereo pan (`-1...+1`).
    public var pan: Double
    /// Fade-in duration in seconds (`0...duration`).
    public var fadeIn: Double
    /// Fade-out duration in seconds (`0...duration`).
    public var fadeOut: Double
    public var fadeShape: FadeShape
    public var mute: Bool
    public var reversed: Bool

    public init(
        id: UUID = UUID(),
        name: String? = nil,
        path: String,
        offset: Double = 0,
        sourceStart: Double = 0,
        duration: Double,
        sourceDuration: Double? = nil,
        gainDB: Double = 0,
        pan: Double = 0,
        fadeIn: Double = 0,
        fadeOut: Double = 0,
        fadeShape: FadeShape = .cosine,
        mute: Bool = false,
        reversed: Bool = false
    ) {
        self.id = id
        self.name = name ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        self.path = path
        self.offset = max(0, offset)
        self.sourceStart = max(0, sourceStart)
        self.duration = max(Self.minDuration, duration)
        self.sourceDuration = max(self.sourceStart + self.duration, sourceDuration ?? (self.sourceStart + self.duration))
        self.gainDB = gainDB
        self.pan = min(max(pan, -1), 1)
        self.fadeIn = max(0, fadeIn)
        self.fadeOut = max(0, fadeOut)
        self.fadeShape = fadeShape
        self.mute = mute
        self.reversed = reversed
        clampFades()
    }

    public var end: Double { offset + duration }
    public var sourceEnd: Double { sourceStart + duration }

    public var linearGain: Double {
        gainDB <= -60 ? 0 : pow(10.0, gainDB / 20.0)
    }

    /// Clamps `fadeIn` and `fadeOut` so they stay non-negative and their sum does not exceed `duration`.
    public mutating func clampFades() {
        fadeIn = min(max(0, fadeIn), duration)
        fadeOut = min(max(0, fadeOut), duration)
        let total = fadeIn + fadeOut
        if total > duration, total > 0 {
            let scale = duration / total
            fadeIn *= scale
            fadeOut *= scale
        }
    }

    /// Multiplier (`0...1`) from `fadeIn` and `fadeOut` at `localTime` (`0...duration` from clip start).
    public func fadeGain(atLocalTime localTime: Double) -> Double {
        guard localTime >= 0, localTime <= duration else { return 0 }
        var g = 1.0
        if fadeIn > 1e-6, localTime < fadeIn {
            g *= fadeShape.gain(at: localTime / fadeIn, isIn: true)
        }
        if fadeOut > 1e-6, localTime > duration - fadeOut {
            let intoOut = localTime - (duration - fadeOut)
            g *= fadeShape.gain(at: intoOut / fadeOut, isIn: false)
        }
        return g
    }

    /// Total linear amplitude multiplier at timeline `time` (`0` outside the clip or when muted).
    public func amplitude(atTimelineTime time: Double) -> Double {
        guard !mute, time >= offset, time <= end else { return 0 }
        return linearGain * fadeGain(atLocalTime: time - offset)
    }

    /// Source file time corresponding to timeline `time`. Accounts for `reversed`.
    public func sourceTime(atTimelineTime time: Double) -> Double {
        let local = min(max(time - offset, 0), duration)
        return reversed ? (sourceStart + duration - local) : (sourceStart + local)
    }
}

public struct AudioTrack: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var colorIndex: Int
    public var gainDB: Double
    /// Stereo balance `-1.0` (left) ... `0.0` (center) ... `+1.0` (right).
    public var pan: Double
    public var mute: Bool
    public var solo: Bool
    public var locked: Bool
    public var stereoSplit: Bool
    public var height: Double
    public var clips: [AudioClip]

    public init(
        id: UUID = UUID(),
        name: String,
        colorIndex: Int = 0,
        gainDB: Double = 0,
        pan: Double = 0,
        mute: Bool = false,
        solo: Bool = false,
        locked: Bool = false,
        stereoSplit: Bool = false,
        height: Double = 88,
        clips: [AudioClip] = []
    ) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.gainDB = gainDB
        self.pan = min(max(pan, -1), 1)
        self.mute = mute
        self.solo = solo
        self.locked = locked
        self.stereoSplit = stereoSplit
        self.height = min(max(height, 48), 260)
        self.clips = clips
    }

    public var linearGain: Double {
        gainDB <= -60 ? 0 : pow(10.0, gainDB / 20.0)
    }

    /// Unity-center stereo balance gains: `(1, 1)` at `pan == 0` so unpanned stereo files remain bit-exact.
    public var panGains: (left: Double, right: Double) {
        let p = min(max(pan, -1), 1)
        let left = p <= 0 ? 1.0 : cos(p * .pi / 2.0)
        let right = p >= 0 ? 1.0 : cos(-p * .pi / 2.0)
        return (left, right)
    }

    public var duration: Double {
        clips.map(\.end).max() ?? 0
    }
}

public struct AudioMarker: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var time: Double
    public var colorIndex: Int

    public init(id: UUID = UUID(), name: String, time: Double, colorIndex: Int = 0) {
        self.id = id
        self.name = name
        self.time = max(0, time)
        self.colorIndex = colorIndex
    }
}

/// A copied or cut slice of audio, holding its track offset and relative timeline position.
public struct ClipboardSlice: Equatable, Codable, Sendable {
    public var trackIndex: Int
    public var relativeOffset: Double
    public var clip: AudioClip

    public var duration: Double { clip.duration }
    public var sourceStart: Double { clip.sourceStart }

    public init(trackIndex: Int, relativeOffset: Double, clip: AudioClip) {
        self.trackIndex = trackIndex
        self.relativeOffset = relativeOffset
        self.clip = clip
    }
}

public struct AudioProject: Equatable, Codable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var sampleRate: Double
    public var masterGainDB: Double
    public var loopStart: Double?
    public var loopEnd: Double?
    public var tracks: [AudioTrack]
    public var markers: [AudioMarker]
    public var oscOutHost: String?
    public var oscOutPort: Int?

    public init(
        version: Int = Self.currentVersion,
        sampleRate: Double = 48_000,
        masterGainDB: Double = 0,
        loopRange: ClosedRange<Double>? = nil,
        tracks: [AudioTrack] = [AudioTrack(name: "Piste 1", colorIndex: 0)],
        markers: [AudioMarker] = [],
        oscOutHost: String? = nil,
        oscOutPort: Int? = nil
    ) {
        self.version = version
        self.sampleRate = sampleRate
        self.masterGainDB = masterGainDB
        self.loopStart = loopRange?.lowerBound
        self.loopEnd = loopRange?.upperBound
        self.tracks = tracks
        self.markers = markers
        self.oscOutHost = oscOutHost
        self.oscOutPort = oscOutPort
    }

    public var loopRange: ClosedRange<Double>? {
        get {
            guard let a = loopStart, let b = loopEnd, b > a + 1e-4 else { return nil }
            return a...b
        }
        set {
            loopStart = newValue?.lowerBound
            loopEnd = newValue?.upperBound
        }
    }

    public var masterLinearGain: Double {
        masterGainDB <= -60 ? 0 : pow(10.0, masterGainDB / 20.0)
    }

    public var totalDuration: Double {
        tracks.lazy.map(\.duration).max() ?? 0
    }

    public var allClips: [(trackIndex: Int, trackID: UUID, clip: AudioClip)] {
        var out: [(Int, UUID, AudioClip)] = []
        for (ti, t) in tracks.enumerated() {
            for c in t.clips { out.append((ti, t.id, c)) }
        }
        return out
    }

    public var clipCount: Int {
        tracks.reduce(0) { $0 + $1.clips.count }
    }

    public var hasSolo: Bool {
        tracks.contains(where: \.solo)
    }

    public func isTrackAudible(_ track: AudioTrack) -> Bool {
        !track.mute && (!hasSolo || track.solo)
    }

    /// Unique source file paths referenced across all tracks, sorted by name.
    public var sourcePaths: [String] {
        Array(Set(tracks.flatMap { $0.clips.map(\.path) })).sorted()
    }

    /// All snap candidate times (0, clip starts/ends, markers), sorted and deduplicated.
    public var cutPoints: [Double] {
        var pts: [Double] = [0]
        for t in tracks {
            for c in t.clips {
                pts.append(c.offset)
                pts.append(c.end)
            }
        }
        for m in markers { pts.append(m.time) }
        pts.sort()
        var unique: [Double] = []
        for p in pts {
            if let last = unique.last, abs(p - last) < 1e-6 { continue }
            unique.append(p)
        }
        return unique
    }

    public var sortedMarkers: [AudioMarker] {
        markers.sorted { $0.time == $1.time ? $0.name < $1.name : $0.time < $1.time }
    }

    public func trackIndex(of id: UUID) -> Int? {
        tracks.firstIndex { $0.id == id }
    }

    public func clipLocation(of id: UUID) -> (trackIndex: Int, clipIndex: Int)? {
        for (ti, t) in tracks.enumerated() {
            if let ci = t.clips.firstIndex(where: { $0.id == id }) {
                return (ti, ci)
            }
        }
        return nil
    }

    public func clip(id: UUID) -> AudioClip? {
        guard let (ti, ci) = clipLocation(of: id) else { return nil }
        return tracks[ti].clips[ci]
    }

    /// Resolves `path` against `projectURL`'s folder when relative.
    public static func resolve(_ path: String, relativeTo projectURL: URL?) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        if let base = projectURL?.deletingLastPathComponent() {
            return base.appendingPathComponent(expanded).standardizedFileURL
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(expanded).standardizedFileURL
    }

    /// Stores `fileURL` relative to `projectURL`'s folder when inside it or one level up, else full path.
    public static func storedPath(for fileURL: URL, relativeTo projectURL: URL?) -> String {
        let file = fileURL.standardizedFileURL
        guard let base = projectURL?.deletingLastPathComponent().standardizedFileURL else {
            return file.path
        }
        let baseComponents = base.pathComponents
        let fileComponents = file.pathComponents
        var common = 0
        while common < min(baseComponents.count, fileComponents.count),
              baseComponents[common] == fileComponents[common] {
            common += 1
        }
        let up = baseComponents.count - common
        if up <= 2 {
            let ups = Array(repeating: "..", count: up)
            let downs = Array(fileComponents.dropFirst(common))
            let rel = (ups + downs).joined(separator: "/")
            if !rel.isEmpty { return rel }
        }
        return file.path
    }
}
