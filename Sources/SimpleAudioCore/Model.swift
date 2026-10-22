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

public enum TrackKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case audio
    case midi

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .audio: return "Audio"
        case .midi: return "MIDI"
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

/// A single MIDI note event inside a MIDI track.
public struct MIDINote: Identifiable, Equatable, Codable, Sendable {
    public static let minDuration: Double = 0.01

    public var id: UUID
    /// MIDI note number `0...127` (`60` = Middle C / C4).
    public var pitch: Int
    /// Start position on the project timeline (seconds).
    public var start: Double
    /// Audible duration of the note (seconds).
    public var duration: Double
    /// MIDI velocity `1...127`.
    public var velocity: Int
    /// MIDI channel `0...15` (`9` = GM percussion channel 10).
    public var channel: Int
    public var mute: Bool

    public init(
        id: UUID = UUID(),
        pitch: Int,
        start: Double,
        duration: Double,
        velocity: Int = 100,
        channel: Int = 0,
        mute: Bool = false
    ) {
        self.id = id
        self.pitch = min(max(pitch, 0), 127)
        self.start = max(0, start)
        self.duration = max(Self.minDuration, duration)
        self.velocity = min(max(velocity, 1), 127)
        self.channel = min(max(channel, 0), 15)
        self.mute = mute
    }

    public var end: Double { start + duration }

    /// Normalized velocity in `0...1`.
    public var normalizedVelocity: Double {
        Double(velocity) / 127.0
    }

    /// Equal-temperament frequency in Hz (`A4 = 69 = 440 Hz`).
    public func frequencyHz(transpose: Int = 0) -> Double {
        let p = min(max(pitch + transpose, 0), 127)
        return 440.0 * pow(2.0, Double(p - 69) / 12.0)
    }
}

/// Standard General MIDI (GM1) 128 program names and helpers.
public enum GeneralMIDI {
    public static let programs: [String] = [
        // Piano (0-7)
        "Acoustic Grand Piano", "Bright Acoustic Piano", "Electric Grand Piano", "Honky-tonk Piano",
        "Electric Piano 1 (Rhodes)", "Electric Piano 2 (DX)", "Harpsichord", "Clavinet",
        // Chromatic Percussion (8-15)
        "Celesta", "Glockenspiel", "Music Box", "Vibraphone",
        "Marimba", "Xylophone", "Tubular Bells", "Dulcimer",
        // Organ (16-23)
        "Drawbar Organ", "Percussive Organ", "Rock Organ", "Church Organ",
        "Reed Organ", "Accordion", "Harmonica", "Tango Accordion",
        // Guitar (24-31)
        "Acoustic Guitar (Nylon)", "Acoustic Guitar (Steel)", "Electric Guitar (Jazz)", "Electric Guitar (Clean)",
        "Electric Guitar (Muted)", "Overdriven Guitar", "Distortion Guitar", "Guitar Harmonics",
        // Bass (32-39)
        "Acoustic Bass", "Electric Bass (Finger)", "Electric Bass (Pick)", "Fretless Bass",
        "Slap Bass 1", "Slap Bass 2", "Synth Bass 1", "Synth Bass 2",
        // Strings (40-47)
        "Violin", "Viola", "Cello", "Contrabass",
        "Tremolo Strings", "Pizzicato Strings", "Orchestral Harp", "Timpani",
        // Ensemble (48-55)
        "String Ensemble 1", "String Ensemble 2", "Synth Strings 1", "Synth Strings 2",
        "Choir Aahs", "Voice Oohs", "Synth Voice", "Orchestra Hit",
        // Brass (56-63)
        "Trumpet", "Trombone", "Tuba", "Muted Trumpet",
        "French Horn", "Brass Section", "Synth Brass 1", "Synth Brass 2",
        // Reed (64-71)
        "Soprano Sax", "Alto Sax", "Tenor Sax", "Baritone Sax",
        "Oboe", "English Horn", "Bassoon", "Clarinet",
        // Pipe (72-79)
        "Piccolo", "Flute", "Recorder", "Pan Flute",
        "Blown Bottle", "Shakuhachi", "Whistle", "Ocarina",
        // Synth Lead (80-87)
        "Lead 1 (Square)", "Lead 2 (Sawtooth)", "Lead 3 (Calliope)", "Lead 4 (Chiff)",
        "Lead 5 (Charang)", "Lead 6 (Voice)", "Lead 7 (Fifths)", "Lead 8 (Bass + Lead)",
        // Synth Pad (88-95)
        "Pad 1 (New Age)", "Pad 2 (Warm)", "Pad 3 (Polysynth)", "Pad 4 (Choir)",
        "Pad 5 (Bowed)", "Pad 6 (Metallic)", "Pad 7 (Halo)", "Pad 8 (Sweep)",
        // Synth Effects (96-103)
        "FX 1 (Rain)", "FX 2 (Soundtrack)", "FX 3 (Crystal)", "FX 4 (Atmosphere)",
        "FX 5 (Brightness)", "FX 6 (Goblins)", "FX 7 (Echoes)", "FX 8 (Sci-Fi)",
        // Ethnic (104-111)
        "Sitar", "Banjo", "Shamisen", "Koto",
        "Kalimba", "Bagpipe", "Fiddle", "Shanai",
        // Percussive & Sound Effects (112-127)
        "Tinkle Bell", "Agogo", "Steel Drums", "Woodblock",
        "Taiko Drum", "Melodic Tom", "Synth Drum", "Reverse Cymbal",
        "Guitar Fret Noise", "Breath Noise", "Seashore", "Bird Tweet",
        "Telephone Ring", "Helicopter", "Applause", "Gunshot"
    ]

    public static func programName(_ program: Int, isDrum: Bool = false) -> String {
        if isDrum { return "Kit de Batterie (Canal 10)" }
        let idx = min(max(program, 0), 127)
        return programs[idx]
    }

    public static func noteName(_ pitch: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let p = min(max(pitch, 0), 127)
        let octave = (p / 12) - 1
        return "\(names[p % 12])\(octave)"
    }

    public static func isBlackKey(_ pitch: Int) -> Bool {
        let mod = ((pitch % 12) + 12) % 12
        return mod == 1 || mod == 3 || mod == 6 || mod == 8 || mod == 10
    }

    public static func drumName(_ pitch: Int) -> String {
        switch pitch {
        case 35, 36: return "Kick"
        case 37: return "Rimshot"
        case 38, 40: return "Snare"
        case 39: return "Clap"
        case 41, 43: return "Low Tom"
        case 42: return "Closed Hat"
        case 44: return "Pedal Hat"
        case 45, 47: return "Mid Tom"
        case 46: return "Open Hat"
        case 48, 50: return "High Tom"
        case 49, 57: return "Crash"
        case 51, 59: return "Ride"
        default: return noteName(pitch)
        }
    }
}

public struct AudioTrack: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: TrackKind
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

    // MIDI properties (used when `kind == .midi`)
    public var channel: Int
    public var program: Int
    public var isDrum: Bool
    public var transpose: Int
    public var pianoRollExpanded: Bool
    public var notes: [MIDINote]

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
        kind: TrackKind = .audio,
        clips: [AudioClip] = [],
        channel: Int = 0,
        program: Int = 0,
        isDrum: Bool = false,
        transpose: Int = 0,
        pianoRollExpanded: Bool = false,
        notes: [MIDINote] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.colorIndex = colorIndex
        self.gainDB = gainDB
        self.pan = min(max(pan, -1), 1)
        self.mute = mute
        self.solo = solo
        self.locked = locked
        self.stereoSplit = stereoSplit
        self.height = min(max(height, 48), 340)
        self.clips = clips
        self.channel = min(max(channel, 0), 15)
        self.program = min(max(program, 0), 127)
        self.isDrum = isDrum || channel == 9
        self.transpose = min(max(transpose, -36), 36)
        self.pianoRollExpanded = pianoRollExpanded
        self.notes = notes.sorted {
            if abs($0.start - $1.start) > 1e-6 { return $0.start < $1.start }
            return $0.pitch < $1.pitch
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, colorIndex, gainDB, pan, mute, solo, locked, stereoSplit, height, clips
        case channel, program, isDrum, transpose, pianoRollExpanded, notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Piste"
        let decodedNotes = try c.decodeIfPresent([MIDINote].self, forKey: .notes) ?? []
        let decodedClips = try c.decodeIfPresent([AudioClip].self, forKey: .clips) ?? []
        self.kind = try c.decodeIfPresent(TrackKind.self, forKey: .kind)
            ?? (!decodedNotes.isEmpty && decodedClips.isEmpty ? .midi : .audio)
        self.colorIndex = try c.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0
        self.gainDB = try c.decodeIfPresent(Double.self, forKey: .gainDB) ?? 0
        self.pan = min(max(try c.decodeIfPresent(Double.self, forKey: .pan) ?? 0, -1), 1)
        self.mute = try c.decodeIfPresent(Bool.self, forKey: .mute) ?? false
        self.solo = try c.decodeIfPresent(Bool.self, forKey: .solo) ?? false
        self.locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        self.stereoSplit = try c.decodeIfPresent(Bool.self, forKey: .stereoSplit) ?? false
        self.height = min(max(try c.decodeIfPresent(Double.self, forKey: .height) ?? 88, 48), 340)
        self.clips = decodedClips
        let ch = min(max(try c.decodeIfPresent(Int.self, forKey: .channel) ?? 0, 0), 15)
        self.channel = ch
        self.program = min(max(try c.decodeIfPresent(Int.self, forKey: .program) ?? 0, 0), 127)
        self.isDrum = (try c.decodeIfPresent(Bool.self, forKey: .isDrum) ?? false) || ch == 9
        self.transpose = min(max(try c.decodeIfPresent(Int.self, forKey: .transpose) ?? 0, -36), 36)
        self.pianoRollExpanded = try c.decodeIfPresent(Bool.self, forKey: .pianoRollExpanded) ?? false
        self.notes = decodedNotes.sorted {
            if abs($0.start - $1.start) > 1e-6 { return $0.start < $1.start }
            return $0.pitch < $1.pitch
        }
    }

    public var isMIDI: Bool {
        kind == .midi
    }

    public var isAudio: Bool {
        kind == .audio
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
        let clipMax = clips.map(\.end).max() ?? 0
        let noteMax = notes.map(\.end).max() ?? 0
        return max(clipMax, noteMax)
    }

    public var instrumentLabel: String {
        GeneralMIDI.programName(program, isDrum: isDrum)
    }

    /// Returns `(minPitch, maxPitch)` padded to at least a 14-semitone span so the Piano-Roll has comfortable vertical breathing room.
    public var pitchBounds: (minPitch: Int, maxPitch: Int) {
        guard let lo = notes.map(\.pitch).min(), let hi = notes.map(\.pitch).max() else {
            return (48, 72)
        }
        let span = hi - lo
        let pad = max(2, (14 - span) / 2)
        return (max(0, lo - pad), min(127, hi + pad))
    }

    public mutating func sortNotes() {
        notes.sort {
            if abs($0.start - $1.start) > 1e-6 { return $0.start < $1.start }
            return $0.pitch < $1.pitch
        }
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

/// A copied or cut slice of a MIDI note, holding its relative track offset and timeline start offset.
public struct NoteClipboardSlice: Equatable, Codable, Sendable {
    public var trackOffset: Int
    public var relativeStart: Double
    public var note: MIDINote

    public init(trackOffset: Int, relativeStart: Double, note: MIDINote) {
        self.trackOffset = trackOffset
        self.relativeStart = relativeStart
        self.note = note
    }
}

public struct AudioProject: Equatable, Codable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var title: String
    public var sampleRate: Double
    public var masterGainDB: Double
    public var bpm: Double
    public var timeSignatureNumerator: Int
    public var timeSignatureDenominator: Int
    public var ticksPerQuarterNote: Int
    public var playbackRate: Double
    public var soundfontPath: String?
    public var loopStart: Double?
    public var loopEnd: Double?
    public var tracks: [AudioTrack]
    public var markers: [AudioMarker]
    public var oscOutHost: String?
    public var oscOutPort: Int?

    public init(
        version: Int = Self.currentVersion,
        title: String = "Projet SimpleAudio",
        sampleRate: Double = 48_000,
        masterGainDB: Double = 0,
        bpm: Double = 120.0,
        timeSignatureNumerator: Int = 4,
        timeSignatureDenominator: Int = 4,
        ticksPerQuarterNote: Int = 480,
        playbackRate: Double = 1.0,
        soundfontPath: String? = nil,
        loopRange: ClosedRange<Double>? = nil,
        tracks: [AudioTrack] = [AudioTrack(name: "Piste 1", colorIndex: 0)],
        markers: [AudioMarker] = [],
        oscOutHost: String? = nil,
        oscOutPort: Int? = nil
    ) {
        self.version = version
        self.title = title
        self.sampleRate = sampleRate
        self.masterGainDB = masterGainDB
        self.bpm = min(max(bpm, 20.0), 300.0)
        self.timeSignatureNumerator = min(max(timeSignatureNumerator, 1), 32)
        self.timeSignatureDenominator = min(max(timeSignatureDenominator, 1), 32)
        self.ticksPerQuarterNote = min(max(ticksPerQuarterNote, 24), 9600)
        self.playbackRate = min(max(playbackRate, 0.25), 4.0)
        self.soundfontPath = soundfontPath
        self.loopStart = loopRange?.lowerBound
        self.loopEnd = loopRange?.upperBound
        self.tracks = tracks
        self.markers = markers
        self.oscOutHost = oscOutHost
        self.oscOutPort = oscOutPort
    }

    private enum CodingKeys: String, CodingKey {
        case version, title, sampleRate, masterGainDB, bpm
        case timeSignatureNumerator, timeSignatureDenominator, ticksPerQuarterNote
        case playbackRate, soundfontPath
        case loopStart, loopEnd, tracks, markers, oscOutHost, oscOutPort
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        self.title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Projet SimpleAudio"
        self.sampleRate = try c.decodeIfPresent(Double.self, forKey: .sampleRate) ?? 48_000
        self.masterGainDB = try c.decodeIfPresent(Double.self, forKey: .masterGainDB) ?? 0
        self.bpm = min(max(try c.decodeIfPresent(Double.self, forKey: .bpm) ?? 120.0, 20.0), 300.0)
        self.timeSignatureNumerator = min(max(try c.decodeIfPresent(Int.self, forKey: .timeSignatureNumerator) ?? 4, 1), 32)
        self.timeSignatureDenominator = min(max(try c.decodeIfPresent(Int.self, forKey: .timeSignatureDenominator) ?? 4, 1), 32)
        self.ticksPerQuarterNote = min(max(try c.decodeIfPresent(Int.self, forKey: .ticksPerQuarterNote) ?? 480, 24), 9600)
        self.playbackRate = min(max(try c.decodeIfPresent(Double.self, forKey: .playbackRate) ?? 1.0, 0.25), 4.0)
        self.soundfontPath = try c.decodeIfPresent(String.self, forKey: .soundfontPath)
        self.loopStart = try c.decodeIfPresent(Double.self, forKey: .loopStart)
        self.loopEnd = try c.decodeIfPresent(Double.self, forKey: .loopEnd)
        self.tracks = try c.decodeIfPresent([AudioTrack].self, forKey: .tracks) ?? [AudioTrack(name: "Piste 1", colorIndex: 0)]
        self.markers = try c.decodeIfPresent([AudioMarker].self, forKey: .markers) ?? []
        self.oscOutHost = try c.decodeIfPresent(String.self, forKey: .oscOutHost)
        self.oscOutPort = try c.decodeIfPresent(Int.self, forKey: .oscOutPort)
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

    /// Seconds per quarter-note beat at the current `bpm`.
    public var secondsPerBeat: Double {
        60.0 / max(20.0, bpm)
    }

    /// Quarter-note beats per measure (`4.0` in 4/4, `3.0` in 3/4, `3.0` in 6/8).
    public var beatsPerBar: Double {
        Double(timeSignatureNumerator) * (4.0 / Double(max(1, timeSignatureDenominator)))
    }

    /// Seconds per measure (bar).
    public var secondsPerBar: Double {
        secondsPerBeat * beatsPerBar
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

    public var allNotes: [(trackIndex: Int, trackID: UUID, note: MIDINote)] {
        var out: [(Int, UUID, MIDINote)] = []
        for (ti, t) in tracks.enumerated() {
            for n in t.notes { out.append((ti, t.id, n)) }
        }
        return out
    }

    public var noteCount: Int {
        tracks.reduce(0) { $0 + $1.notes.count }
    }

    public var hasMIDITracks: Bool {
        tracks.contains { $0.isMIDI || !$0.notes.isEmpty }
    }

    public var hasAudioTracks: Bool {
        tracks.contains { !$0.isMIDI || !$0.clips.isEmpty }
    }

    public var hasContent: Bool {
        !allClips.isEmpty || !allNotes.isEmpty
    }

    public var hasSolo: Bool {
        tracks.contains(where: \.solo)
    }

    public func isTrackAudible(_ track: AudioTrack) -> Bool {
        !track.mute && (!hasSolo || track.solo)
    }

    /// Converts timeline `seconds` into 1-based `(bar, beat, subBeat)`.
    public func barBeat(forSeconds seconds: Double) -> (bar: Int, beat: Int, cent: Int) {
        let t = max(0, seconds)
        let spBar = max(0.05, secondsPerBar)
        let spBeat = max(0.01, secondsPerBeat * (4.0 / Double(max(1, timeSignatureDenominator))))
        let barIndex = Int((t / spBar).rounded(.down))
        let remInBar = t - Double(barIndex) * spBar
        let beatIndex = Int((remInBar / spBeat).rounded(.down))
        let remInBeat = remInBar - Double(beatIndex) * spBeat
        let cent = min(99, max(0, Int(((remInBeat / spBeat) * 100.0).rounded())))
        return (barIndex + 1, beatIndex + 1, cent)
    }

    /// Unique source file paths referenced across all tracks, sorted by name.
    public var sourcePaths: [String] {
        Array(Set(tracks.flatMap { $0.clips.map(\.path) })).sorted()
    }

    /// All snap candidate times (0, clip starts/ends, MIDI note starts/ends, markers), sorted and deduplicated.
    public var cutPoints: [Double] {
        var pts: [Double] = [0]
        for t in tracks {
            for c in t.clips {
                pts.append(c.offset)
                pts.append(c.end)
            }
            for n in t.notes {
                pts.append(n.start)
                pts.append(n.end)
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

    public func noteLocation(of id: UUID) -> (trackIndex: Int, noteIndex: Int)? {
        for (ti, t) in tracks.enumerated() {
            if let ni = t.notes.firstIndex(where: { $0.id == id }) {
                return (ti, ni)
            }
        }
        return nil
    }

    public func note(id: UUID) -> MIDINote? {
        guard let (ti, ni) = noteLocation(of: id) else { return nil }
        return tracks[ti].notes[ni]
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
