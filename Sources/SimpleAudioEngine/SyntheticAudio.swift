import Foundation
import SimpleAudioCore

/// Generates musical synthetic audio files and a sample multitrack project for instant testing,
/// snapshots (`--snapshot`), and `--self-test`.
public enum SyntheticAudio {
    /// Writes three distinct stereo WAV files (`voix.wav`, `nappe.wav`, `pulsation.wav`) and a `demo.simpleaudio`
    /// project in `directory`, returning the project URL and the project model.
    @discardableResult
    public static func createDemoFixtures(in directory: URL) throws -> (projectURL: URL, project: AudioProject) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sampleRate = 48_000.0

        // 1. "voix.wav" — articulated speech-like phrases with clear silences between words (8.0 s)
        let voixURL = directory.appendingPathComponent("voix.wav")
        if !FileManager.default.fileExists(atPath: voixURL.path) {
            let n = Int(8.0 * sampleRate)
            var left = [Float](repeating: 0, count: n)
            var right = [Float](repeating: 0, count: n)
            let phrases: [(start: Double, end: Double, f0: Double)] = [
                (0.25, 1.45, 195),
                (1.85, 3.20, 220),
                (3.65, 5.10, 185),
                (5.55, 7.45, 210),
            ]
            for p in phrases {
                let i0 = Int(p.start * sampleRate)
                let i1 = min(n, Int(p.end * sampleRate))
                for i in i0..<i1 {
                    let t = Double(i) / sampleRate
                    let local = t - p.start
                    let dur = p.end - p.start
                    let syllable = 0.55 + 0.45 * sin(2 * .pi * 4.2 * local)
                    let edgeEnv = min(1.0, min(local / 0.04, (dur - local) / 0.06))
                    let pitch = p.f0 * (1.0 + 0.03 * sin(2 * .pi * 5.5 * local))
                    let sig = 0.48 * sin(2 * .pi * pitch * t)
                        + 0.24 * sin(2 * .pi * pitch * 2 * t)
                        + 0.12 * sin(2 * .pi * pitch * 3 * t)
                    let val = Float(sig * syllable * edgeEnv)
                    left[i] = val * 0.95
                    right[i] = val * 0.88
                }
            }
            try AudioExporter.writeAudioFile(
                left: left,
                right: right,
                to: voixURL,
                options: AudioExportOptions(format: .wav, sampleRate: sampleRate, bitDepth: 24, channels: 2)
            )
        }

        // 2. "nappe.wav" — warm stereo harmonic pad (10.0 s)
        let nappeURL = directory.appendingPathComponent("nappe.wav")
        if !FileManager.default.fileExists(atPath: nappeURL.path) {
            let n = Int(10.0 * sampleRate)
            var left = [Float](repeating: 0, count: n)
            var right = [Float](repeating: 0, count: n)
            let notes = [220.0, 277.18, 329.63, 440.0]
            for i in 0..<n {
                let t = Double(i) / sampleRate
                let swell = 0.55 + 0.35 * sin(2 * .pi * 0.25 * t)
                var sL = 0.0, sR = 0.0
                for (k, f) in notes.enumerated() {
                    let detune = 1.0 + Double(k - 1) * 0.0015
                    sL += sin(2 * .pi * f * detune * t) * 0.18
                    sR += cos(2 * .pi * f * (2.0 - detune) * t) * 0.18
                }
                left[i] = Float(sL * swell)
                right[i] = Float(sR * swell)
            }
            try AudioExporter.writeAudioFile(
                left: left,
                right: right,
                to: nappeURL,
                options: AudioExportOptions(format: .wav, sampleRate: sampleRate, bitDepth: 24, channels: 2)
            )
        }

        // 3. "pulsation.wav" — rhythmic percussive transients at 120 BPM (8.0 s)
        let pulsationURL = directory.appendingPathComponent("pulsation.wav")
        if !FileManager.default.fileExists(atPath: pulsationURL.path) {
            let n = Int(8.0 * sampleRate)
            var left = [Float](repeating: 0, count: n)
            var right = [Float](repeating: 0, count: n)
            let beatInterval = 0.5
            var beat = 0.0
            while beat < 7.8 {
                let i0 = Int(beat * sampleRate)
                let i1 = min(n, Int((beat + 0.18) * sampleRate))
                let isDownbeat = Int((beat / beatInterval).rounded()) % 4 == 0
                let baseFreq = isDownbeat ? 110.0 : 165.0
                for i in i0..<i1 {
                    let dt = Double(i - i0) / sampleRate
                    let env = exp(-dt * 24.0)
                    let v = Float(sin(2 * .pi * baseFreq * dt * (1.0 - dt * 1.8)) * env * (isDownbeat ? 0.75 : 0.48))
                    left[i] = v
                    right[i] = v
                }
                beat += beatInterval
            }
            try AudioExporter.writeAudioFile(
                left: left,
                right: right,
                to: pulsationURL,
                options: AudioExportOptions(format: .wav, sampleRate: sampleRate, bitDepth: 24, channels: 2)
            )
        }

        let track1 = AudioTrack(
            name: L("Voix", "Vocals"),
            colorIndex: 0,
            gainDB: 0,
            pan: 0,
            clips: [
                AudioClip(
                    name: L("voix · 1", "vocals · 1"),
                    path: "voix.wav",
                    offset: 0.0,
                    sourceStart: 0.15,
                    duration: 3.25,
                    sourceDuration: 8.0,
                    gainDB: 0,
                    fadeIn: 0.12,
                    fadeOut: 0.25,
                    fadeShape: .cosine
                ),
                AudioClip(
                    name: L("voix · 2", "vocals · 2"),
                    path: "voix.wav",
                    offset: 3.60,
                    sourceStart: 3.55,
                    duration: 3.95,
                    sourceDuration: 8.0,
                    gainDB: 1.5,
                    fadeIn: 0.18,
                    fadeOut: 0.45,
                    fadeShape: .cosine
                ),
            ]
        )

        let track2 = AudioTrack(
            name: L("Nappe", "Pad"),
            colorIndex: 1,
            gainDB: -4.5,
            pan: -0.15,
            stereoSplit: true,
            clips: [
                AudioClip(
                    name: L("nappe", "pad"),
                    path: "nappe.wav",
                    offset: 0.0,
                    sourceStart: 0.0,
                    duration: 8.0,
                    sourceDuration: 10.0,
                    gainDB: -1.0,
                    fadeIn: 0.85,
                    fadeOut: 1.20,
                    fadeShape: .cosine
                ),
            ]
        )

        let track3 = AudioTrack(
            name: L("Pulsation", "Pulse"),
            colorIndex: 2,
            gainDB: -3.0,
            pan: 0.15,
            clips: [
                AudioClip(
                    name: L("pulsation", "pulse"),
                    path: "pulsation.wav",
                    offset: 1.0,
                    sourceStart: 0.0,
                    duration: 6.5,
                    sourceDuration: 8.0,
                    gainDB: 0,
                    fadeIn: 0.30,
                    fadeOut: 0.60,
                    fadeShape: .linear
                ),
            ]
        )

        let project = AudioProject(
            sampleRate: sampleRate,
            masterGainDB: 0,
            tracks: [track1, track2, track3],
            markers: [
                AudioMarker(name: "Intro", time: 0.0, colorIndex: 0),
                AudioMarker(name: L("Entrée rythme", "Rhythm In"), time: 1.0, colorIndex: 2),
                AudioMarker(name: L("Reprise voix", "Vocal Return"), time: 3.60, colorIndex: 1),
            ]
        )

        let projectURL = directory.appendingPathComponent("demo.simpleaudio")
        let data = try DocumentStore.encode(project)
        try data.write(to: projectURL, options: .atomic)
        return (projectURL, project)
    }

    @discardableResult
    public static func generateDemoDirectory(at directory: URL) throws -> URL {
        try createDemoFixtures(in: directory).projectURL
    }

    public static func writeSpeechCadenceWAV(to url: URL, duration: Double = 3.0, sampleRate: Double = 48_000) throws {
        let n = max(1, Int(duration * sampleRate))
        var left = [Float](repeating: 0, count: n)
        var right = [Float](repeating: 0, count: n)
        let phrases: [(start: Double, end: Double, f0: Double)] = [
            (0.15, min(duration * 0.40, duration - 0.1), 195),
            (min(duration * 0.55, duration - 0.1), max(duration * 0.56, duration - 0.15), 220),
        ]
        for p in phrases where p.end > p.start {
            let i0 = Int(p.start * sampleRate)
            let i1 = min(n, Int(p.end * sampleRate))
            for i in i0..<i1 {
                let t = Double(i) / sampleRate
                let local = t - p.start
                let dur = max(0.05, p.end - p.start)
                let env = min(1.0, min(local / 0.03, (dur - local) / 0.04))
                let val = Float(0.55 * sin(2 * .pi * p.f0 * t) * env)
                left[i] = val
                right[i] = val * 0.92
            }
        }
        try AudioExporter.writeAudioFile(
            left: left,
            right: right,
            to: url,
            options: AudioExportOptions(format: .wav, sampleRate: sampleRate, bitDepth: 24, channels: 2)
        )
    }

    /// Generates a rich multitrack MIDI demo project (`Grand Piano`, `Basse Électrique`, `Ensemble de Cordes`, `Batterie GM`).
    public static func makeMIDIDemoProject() -> AudioProject {
        let bpm = 120.0
        let beat = 60.0 / bpm

        var pianoNotes: [MIDINote] = []
        let progression: [[Int]] = [
            [57, 60, 64, 67],
            [53, 57, 60, 64],
            [48, 55, 60, 64],
            [55, 59, 62, 67],
            [57, 60, 64, 69],
            [53, 57, 60, 65],
            [48, 52, 55, 60],
            [55, 59, 62, 65],
        ]
        let melodyPatterns: [[(subBeat: Double, dur: Double, pitch: Int, vel: Int)]] = [
            [(0.0, 0.75, 72, 102), (0.75, 0.75, 76, 96), (1.5, 1.0, 79, 108), (2.5, 0.75, 76, 92), (3.25, 0.75, 72, 88)],
            [(0.0, 1.0, 69, 100), (1.0, 0.5, 72, 94), (1.5, 1.0, 76, 105), (2.5, 1.5, 74, 96)],
            [(0.0, 0.75, 72, 104), (0.75, 0.75, 74, 96), (1.5, 1.0, 76, 110), (2.5, 0.75, 79, 102), (3.25, 0.75, 76, 94)],
            [(0.0, 1.5, 74, 104), (1.5, 0.5, 72, 92), (2.0, 1.0, 71, 98), (3.0, 1.0, 67, 90)],
        ]

        for (barIdx, chord) in progression.enumerated() {
            let barStart = Double(barIdx) * 4.0 * beat
            for p in chord {
                pianoNotes.append(MIDINote(pitch: p, start: barStart, duration: 1.85 * beat, velocity: 78, channel: 0))
                pianoNotes.append(MIDINote(pitch: p, start: barStart + 2.0 * beat, duration: 1.85 * beat, velocity: 74, channel: 0))
            }
            let motif = melodyPatterns[barIdx % melodyPatterns.count]
            for m in motif {
                pianoNotes.append(
                    MIDINote(
                        pitch: m.pitch,
                        start: barStart + m.subBeat * beat,
                        duration: m.dur * beat * 0.92,
                        velocity: m.vel,
                        channel: 0
                    )
                )
            }
        }

        var bassNotes: [MIDINote] = []
        let bassRoots = [45, 41, 36, 43, 45, 41, 36, 43]
        for (barIdx, root) in bassRoots.enumerated() {
            let barStart = Double(barIdx) * 4.0 * beat
            let fifth = root + 7
            let octave = root + 12
            let pattern: [(Double, Double, Int, Int)] = [
                (0.0, 0.9, root, 106),
                (1.0, 0.45, root, 92),
                (1.5, 0.9, fifth, 98),
                (2.5, 0.7, octave, 102),
                (3.25, 0.7, fifth, 94),
            ]
            for (b, d, p, v) in pattern {
                bassNotes.append(MIDINote(pitch: p, start: barStart + b * beat, duration: d * beat, velocity: v, channel: 1))
            }
        }

        var stringNotes: [MIDINote] = []
        let stringVoicings: [[Int]] = [
            [64, 69, 72], [60, 65, 69], [60, 64, 67], [59, 62, 67],
            [64, 69, 76], [60, 65, 72], [60, 64, 72], [59, 62, 71],
        ]
        for (barIdx, voicing) in stringVoicings.enumerated() {
            let barStart = Double(barIdx) * 4.0 * beat
            for p in voicing {
                stringNotes.append(MIDINote(pitch: p, start: barStart, duration: 3.85 * beat, velocity: 76, channel: 2))
            }
        }

        var drumNotes: [MIDINote] = []
        for barIdx in 0..<8 {
            let barStart = Double(barIdx) * 4.0 * beat
            for kb in [0.0, 1.5, 2.0] {
                drumNotes.append(MIDINote(pitch: 36, start: barStart + kb * beat, duration: 0.22, velocity: 112, channel: 9))
            }
            for sb in [1.0, 3.0] {
                drumNotes.append(MIDINote(pitch: 38, start: barStart + sb * beat, duration: 0.20, velocity: 104, channel: 9))
            }
            for step in 0..<8 {
                let hb = Double(step) * 0.5
                let isOpen = (step == 7)
                drumNotes.append(
                    MIDINote(
                        pitch: isOpen ? 46 : 42,
                        start: barStart + hb * beat,
                        duration: isOpen ? 0.24 : 0.12,
                        velocity: step % 2 == 0 ? 88 : 68,
                        channel: 9
                    )
                )
            }
        }

        let tracks: [AudioTrack] = [
            AudioTrack(
                name: "Grand Piano",
                colorIndex: 0,
                gainDB: 0.0,
                pan: -0.15,
                kind: .midi,
                channel: 0,
                program: 0,
                isDrum: false,
                pianoRollExpanded: true,
                notes: pianoNotes
            ),
            AudioTrack(
                name: L("Basse Électrique", "Electric Bass"),
                colorIndex: 1,
                gainDB: -1.0,
                pan: 0.0,
                kind: .midi,
                channel: 1,
                program: 33,
                isDrum: false,
                notes: bassNotes
            ),
            AudioTrack(
                name: L("Ensemble de Cordes", "String Ensemble"),
                colorIndex: 4,
                gainDB: -2.5,
                pan: 0.22,
                kind: .midi,
                channel: 2,
                program: 48,
                isDrum: false,
                notes: stringNotes
            ),
            AudioTrack(
                name: L("Batterie GM", "GM Drums"),
                colorIndex: 2,
                gainDB: -1.5,
                pan: 0.0,
                kind: .midi,
                channel: 9,
                program: 0,
                isDrum: true,
                notes: drumNotes
            ),
        ]

        return AudioProject(
            title: L("Démo MIDI — Horizon", "MIDI Demo — Horizon"),
            bpm: bpm,
            timeSignatureNumerator: 4,
            timeSignatureDenominator: 4,
            ticksPerQuarterNote: 480,
            tracks: tracks,
            markers: [
                AudioMarker(name: "Intro", time: 0.0, colorIndex: 0),
                AudioMarker(name: L("Thème A", "Theme A"), time: 4.0, colorIndex: 1),
                AudioMarker(name: "Variation", time: 8.0, colorIndex: 4),
                AudioMarker(name: "Coda", time: 12.0, colorIndex: 2),
            ]
        )
    }

    public static func writeDemoMIDIFile(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let project = makeMIDIDemoProject()
        let data = MIDIFileCodec.encode(project)
        try data.write(to: url, options: .atomic)
    }

    /// Generates a hybrid Audio + MIDI demo project combining `Voix`, `Nappe`, `Grand Piano (MIDI)`, and `Batterie GM (MIDI)`.
    @discardableResult
    public static func createHybridDemoFixtures(in directory: URL) throws -> (projectURL: URL, project: AudioProject) {
        let (_, audioProj) = try createDemoFixtures(in: directory)
        let midiProj = makeMIDIDemoProject()

        var hybrid = audioProj
        hybrid.title = L("Démo Hybride Audio + MIDI", "Hybrid Audio + MIDI Demo")
        hybrid.bpm = 120.0
        var pianoTrack = midiProj.tracks[0]
        pianoTrack.notes = pianoTrack.notes.filter { $0.start < 8.0 }
        pianoTrack.pianoRollExpanded = true
        var bassTrack = midiProj.tracks[1]
        bassTrack.notes = bassTrack.notes.filter { $0.start < 8.0 }
        hybrid.tracks.append(pianoTrack)
        hybrid.tracks.append(bassTrack)

        let projectURL = directory.appendingPathComponent("demo-hybrid.simpleaudio")
        let data = try DocumentStore.encode(hybrid)
        try data.write(to: projectURL, options: .atomic)
        return (projectURL, hybrid)
    }
}
