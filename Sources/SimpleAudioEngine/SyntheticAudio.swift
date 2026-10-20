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
            name: "Voix",
            colorIndex: 0,
            gainDB: 0,
            pan: 0,
            clips: [
                AudioClip(
                    name: "voix · 1",
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
                    name: "voix · 2",
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
            name: "Nappe",
            colorIndex: 1,
            gainDB: -4.5,
            pan: -0.15,
            stereoSplit: true,
            clips: [
                AudioClip(
                    name: "nappe",
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
            name: "Pulsation",
            colorIndex: 2,
            gainDB: -3.0,
            pan: 0.15,
            clips: [
                AudioClip(
                    name: "pulsation",
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
                AudioMarker(name: "Entrée rythme", time: 1.0, colorIndex: 2),
                AudioMarker(name: "Reprise voix", time: 3.60, colorIndex: 1),
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
}
