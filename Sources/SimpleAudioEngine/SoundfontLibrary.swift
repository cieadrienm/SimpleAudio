import Foundation
import SimpleAudioCore

/// Built-in sound and instrument presets available out-of-the-box for MIDI tracks.
public enum SoundPreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case gsMultitimbral = "gs_multitimbral"
    case grandPiano = "grand_piano"
    case brightPiano = "bright_piano"
    case electricPiano = "electric_piano"
    case harpsichord = "harpsichord"
    case vibraphone = "vibraphone"
    case acousticGuitar = "acoustic_guitar"
    case stringsEnsemble = "strings_ensemble"
    case choirAahs = "choir_aahs"
    case warmPad = "warm_pad"
    case analyticSynth = "analytic_synth"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .gsMultitimbral: return "Banque Apple GS (Multi-pistes)"
        case .grandPiano: return "Piano à queue (Grand Piano)"
        case .brightPiano: return "Piano brillant (Studio)"
        case .electricPiano: return "Piano électrique (Rhodes)"
        case .harpsichord: return "Clavecin (Harpsichord)"
        case .vibraphone: return "Vibraphone & Maillets"
        case .acousticGuitar: return "Guitare classique (Nylon)"
        case .stringsEnsemble: return "Ensemble de cordes"
        case .choirAahs: return "Chœur symphonique"
        case .warmPad: return "Nappe chaude (Warm Pad)"
        case .analyticSynth: return "Synthé Analytique (DSP)"
        }
    }

    public var subtitle: String {
        switch self {
        case .gsMultitimbral: return "Piano & 128 instruments Roland GS"
        case .grandPiano: return "Piano acoustique échantillonné (Programme 1)"
        case .brightPiano: return "Piano droit brillant (Programme 2)"
        case .electricPiano: return "Fender Rhodes doux (Programme 5)"
        case .harpsichord: return "Clavecin baroque (Programme 7)"
        case .vibraphone: return "Vibraphone métallique (Programme 12)"
        case .acousticGuitar: return "Guitare cordes nylon (Programme 25)"
        case .stringsEnsemble: return "Cordes orchestrales (Programme 49)"
        case .choirAahs: return "Voix & chœurs (Programme 53)"
        case .warmPad: return "Synthé analogique doux (Programme 90)"
        case .analyticSynth: return "Synthèse harmonique mathématique ultra-légère"
        }
    }

    public var icon: String {
        switch self {
        case .gsMultitimbral: return "pianokeys.inverse"
        case .grandPiano, .brightPiano, .electricPiano, .harpsichord: return "pianokeys"
        case .vibraphone: return "tuningfork"
        case .acousticGuitar: return "guitars"
        case .stringsEnsemble: return "music.quarternote.3"
        case .choirAahs: return "person.wave.2"
        case .warmPad: return "waveform.path.ecg"
        case .analyticSynth: return "waveform.circle"
        }
    }

    /// If non-nil, overrides melodic tracks' GM program with this specific instrument.
    public var forcedProgram: Int? {
        switch self {
        case .gsMultitimbral, .analyticSynth: return nil
        case .grandPiano: return 0
        case .brightPiano: return 1
        case .electricPiano: return 4
        case .harpsichord: return 6
        case .vibraphone: return 11
        case .acousticGuitar: return 24
        case .stringsEnsemble: return 48
        case .choirAahs: return 52
        case .warmPad: return 89
        }
    }

    public var usesAppleDLS: Bool {
        self != .analyticSynth
    }
}

/// Manages SoundFont (`.sf2` / `.dls`) discovery next to MIDI files, recent SoundFonts, and system DLS bank lookup.
public final class SoundfontLibrary: @unchecked Sendable {
    public static let shared = SoundfontLibrary()

    public struct Entry: Identifiable, Equatable, Sendable {
        public var id: String { url.standardizedFileURL.path }
        public let url: URL
        public var name: String { url.deletingPathExtension().lastPathComponent }
        public init(url: URL) { self.url = url }
    }

    public static func isSoundfontFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "sf2" || ext == "dls"
    }

    public func recentEntries() -> [Entry] {
        recentSoundfonts.map(Entry.init)
    }

    public func bestMatchSoundfont(forMIDIFile midiURL: URL) -> URL? {
        guessSoundfont(forMIDI: midiURL)
    }

    private let recentKey = "net.cieadrienm.simpleaudio.recentSoundfonts"
    private let defaultSFKey = "net.cieadrienm.simpleaudio.defaultSoundfont"
    private let looseMatchKey = "net.cieadrienm.simpleaudio.looseSFMatching"
    private let presetKey = "net.cieadrienm.simpleaudio.soundPreset"

    public static let systemDLSURL = URL(
        fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls"
    )

    public static var hasSystemDLS: Bool {
        FileManager.default.fileExists(atPath: systemDLSURL.path)
    }

    public init() {}

    public var activePreset: SoundPreset {
        get {
            guard let raw = UserDefaults.standard.string(forKey: presetKey),
                  let preset = SoundPreset(rawValue: raw) else {
                return .gsMultitimbral
            }
            return preset
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: presetKey)
        }
    }

    public var looseMatching: Bool {
        get { UserDefaults.standard.bool(forKey: looseMatchKey) }
        set { UserDefaults.standard.set(newValue, forKey: looseMatchKey) }
    }

    public var customDefaultSoundfont: URL? {
        get {
            guard let path = UserDefaults.standard.string(forKey: defaultSFKey),
                  !path.isEmpty,
                  FileManager.default.fileExists(atPath: path) else { return nil }
            return URL(fileURLWithPath: path)
        }
        set {
            UserDefaults.standard.set(newValue?.path ?? "", forKey: defaultSFKey)
        }
    }

    public var recentSoundfonts: [URL] {
        get {
            let paths = (UserDefaults.standard.array(forKey: recentKey) as? [String]) ?? []
            return paths
                .map { URL(fileURLWithPath: $0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        set {
            let unique = Array(NSOrderedSet(array: newValue.map(\.path))) as? [String] ?? []
            UserDefaults.standard.set(Array(unique.prefix(8)), forKey: recentKey)
        }
    }

    public func recordRecent(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard url.standardizedFileURL != Self.systemDLSURL.standardizedFileURL else { return }
        var current = recentSoundfonts.filter { $0.standardizedFileURL != url.standardizedFileURL }
        current.insert(url.standardizedFileURL, at: 0)
        recentSoundfonts = Array(current.prefix(8))
    }

    /// Automatically finds a companion `.sf2` or `.dls` file next to `midiURL` (same filename, same folder name, or parent folder name).
    public func guessSoundfont(forMIDI midiURL: URL) -> URL? {
        let fm = FileManager.default
        let midiDir = midiURL.deletingLastPathComponent()
        let parentDir = midiDir.deletingLastPathComponent()
        let baseName = midiURL.deletingPathExtension().lastPathComponent

        let candidates: [URL] = [
            midiDir.appendingPathComponent("\(baseName).sf2"),
            midiDir.appendingPathComponent("\(baseName).dls"),
            midiDir.appendingPathComponent("\(midiDir.lastPathComponent).sf2"),
            midiDir.appendingPathComponent("\(midiDir.lastPathComponent).dls"),
            parentDir.appendingPathComponent("\(parentDir.lastPathComponent).sf2"),
            parentDir.appendingPathComponent("\(parentDir.lastPathComponent).dls"),
        ]

        for candidate in candidates {
            if fm.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        if looseMatching,
           let items = try? fm.contentsOfDirectory(at: midiDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            let sfFiles = items.filter {
                let ext = $0.pathExtension.lowercased()
                return ext == "sf2" || ext == "dls"
            }
            if let closest = sfFiles.min(by: {
                Self.levenshtein($0.deletingPathExtension().lastPathComponent, baseName) <
                    Self.levenshtein($1.deletingPathExtension().lastPathComponent, baseName)
            }) {
                return closest
            }
        }

        return customDefaultSoundfont
    }

    public static func levenshtein(_ a: String, _ b: String) -> Int {
        let s = Array(a.lowercased())
        let t = Array(b.lowercased())
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }

        var prev = Array(0...t.count)
        var curr = Array(repeating: 0, count: t.count + 1)

        for i in 1...s.count {
            curr[0] = i
            for j in 1...t.count {
                let cost = (s[i - 1] == t[j - 1]) ? 0 : 1
                curr[j] = min(
                    curr[j - 1] + 1,
                    prev[j] + 1,
                    prev[j - 1] + cost
                )
            }
            prev = curr
        }
        return prev[t.count]
    }
}
