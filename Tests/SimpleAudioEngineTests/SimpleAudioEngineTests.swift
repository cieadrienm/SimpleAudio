import Foundation
import Testing
@testable import SimpleAudioCore
@testable import SimpleAudioEngine

@Suite("SimpleAudioEngine Tests")
@MainActor
struct SimpleAudioEngineTests {
    @Test("Synthetic audio generation, WaveformCache peak+RMS, and silence detection")
    func testWaveformAndAnalysis() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("EngineTests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let wavURL = tmp.appendingPathComponent("test.wav")
        try SyntheticAudio.writeSpeechCadenceWAV(to: wavURL, duration: 3.0)

        let cache = WaveformCache()
        let wave = cache.load(url: wavURL)
        #expect(wave != nil)
        #expect((wave?.duration ?? 0) > 2.9)
        #expect(!(wave?.peaks.isEmpty ?? true))
        #expect(!(wave?.rms.isEmpty ?? true))

        let pcm = cache.pcm(for: wavURL)
        #expect(pcm != nil)
        if let pcm {
            let silences = AudioAnalysis.detectSilences(in: pcm, thresholdDB: -38, minDuration: 0.12)
            #expect(!silences.isEmpty)
            let lufs = AudioAnalysis.measureIntegratedLUFS(left: pcm.left, right: pcm.right, sampleRate: pcm.sampleRate)
            #expect(lufs > -50 && lufs < 0)
        }
    }

    @Test("Multi-format audio export (WAV, AIFF, CAF, M4A) and stems export")
    func testMultiFormatExport() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("ExportTests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let demoProjectURL = try SyntheticAudio.generateDemoDirectory(at: tmp)
        let project = try DocumentStore.decode(Data(contentsOf: demoProjectURL))
        let cache = WaveformCache()

        for fmt in [ExportFormat.wav, .aiff, .caf, .m4a] {
            let outURL = tmp.appendingPathComponent("mix.\(fmt.fileExtension)")
            let res = try AudioExporter.export(
                project: project,
                waveforms: cache,
                to: outURL,
                options: ExportOptions(
                    format: fmt,
                    sampleRate: 48_000,
                    bitDepth: .int24,
                    channels: 2,
                    range: 0.2...2.2,
                    normalizePeak: true,
                    targetPeakDB: -0.1
                ),
                baseURL: demoProjectURL
            )
            #expect(fm.fileExists(atPath: res.url.path))
            #expect(abs(res.duration - 2.0) < 0.15)
        }

        let stemsDir = tmp.appendingPathComponent("stems", isDirectory: true)
        let stemURLs = try AudioExporter.exportStems(
            project: project,
            waveforms: cache,
            directory: stemsDir,
            format: .wav,
            baseURL: demoProjectURL
        )
        #expect(stemURLs.count == 3)
    }
}
