import Accelerate
import AudioToolbox
import AVFoundation
import Foundation
import SimpleAudioCore

public typealias ExportFormat = AudioExportFormat

public enum ExportBitDepth: Int, CaseIterable, Codable, Sendable, Identifiable {
    case int16 = 16
    case int24 = 24
    case float32 = 32

    public var id: Int { rawValue }
    public var label: String {
        switch self {
        case .int16: return "16 bits"
        case .int24: return "24 bits"
        case .float32: return "32f"
        }
    }
}

public struct ExportOptions: Equatable, Sendable {
    public var format: ExportFormat
    public var sampleRate: Double
    public var bitDepth: ExportBitDepth
    public var bitRateKbps: Int
    public var channels: Int
    public var range: ClosedRange<Double>?
    public var normalizePeak: Bool
    public var targetPeakDB: Double
    public var normalizeLUFS: Bool
    public var targetLUFS: Double

    public init(
        format: ExportFormat = .wav,
        sampleRate: Double = 48_000,
        bitDepth: ExportBitDepth = .int24,
        bitRateKbps: Int = 256,
        channels: Int = 2,
        range: ClosedRange<Double>? = nil,
        normalizePeak: Bool = false,
        targetPeakDB: Double = -0.1,
        normalizeLUFS: Bool = false,
        targetLUFS: Double = -14.0
    ) {
        self.format = format
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.bitRateKbps = bitRateKbps
        self.channels = channels
        self.range = range
        self.normalizePeak = normalizePeak
        self.targetPeakDB = targetPeakDB
        self.normalizeLUFS = normalizeLUFS
        self.targetLUFS = targetLUFS
    }

    public var audioExportOptions: AudioExportOptions {
        let norm: AudioNormalization = normalizeLUFS ? .lufs : (normalizePeak ? .peak : .none)
        return AudioExportOptions(
            format: format,
            sampleRate: sampleRate,
            bitDepth: bitDepth.rawValue,
            bitRateKbps: bitRateKbps,
            channels: channels,
            normalization: norm,
            range: range
        )
    }
}

public struct ExportResult: Equatable, Sendable {
    public var url: URL
    public var format: ExportFormat
    public var duration: Double
    public var sampleRate: Double
    public var channels: Int
    public var peakDB: Double
    public var integratedLUFS: Double
    public var appliedGainDB: Double
}

public enum AudioExportFormat: String, CaseIterable, Codable, Sendable, Identifiable {
    case wav
    case aiff
    case caf
    case m4a
    case alac
    case flac
    case mp3

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .wav: return "WAV (PCM)"
        case .aiff: return "AIFF (PCM)"
        case .caf: return "CAF (Core Audio)"
        case .m4a: return "M4A (AAC)"
        case .alac: return "M4A (Apple Lossless)"
        case .flac: return "FLAC"
        case .mp3: return "MP3"
        }
    }

    public var fileExtension: String {
        switch self {
        case .wav: return "wav"
        case .aiff: return "aiff"
        case .caf: return "caf"
        case .m4a, .alac: return "m4a"
        case .flac: return "flac"
        case .mp3: return "mp3"
        }
    }

    public var supportsBitDepth: Bool {
        switch self {
        case .wav, .aiff, .caf, .alac, .flac: return true
        case .m4a, .mp3: return false
        }
    }
}

public enum AudioNormalization: String, CaseIterable, Codable, Sendable, Identifiable {
    case none
    case peak
    case lufs

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .none: return "Aucune"
        case .peak: return "Crête (−0.1 dBFS)"
        case .lufs: return "Loudness (−14 LUFS)"
        }
    }
}

public struct AudioExportOptions: Equatable, Sendable {
    public var format: AudioExportFormat
    public var sampleRate: Double
    public var bitDepth: Int
    public var bitRateKbps: Int
    public var channels: Int
    public var normalization: AudioNormalization
    public var range: ClosedRange<Double>?

    public init(
        format: AudioExportFormat = .wav,
        sampleRate: Double = 48_000,
        bitDepth: Int = 24,
        bitRateKbps: Int = 256,
        channels: Int = 2,
        normalization: AudioNormalization = .none,
        range: ClosedRange<Double>? = nil
    ) {
        self.format = format
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.bitRateKbps = bitRateKbps
        self.channels = min(max(channels, 1), 2)
        self.normalization = normalization
        self.range = range
    }
}

public enum AudioExportError: Error, LocalizedError, Equatable {
    case emptyProject
    case invalidRange
    case cannotCreateFile(String)
    case encodingFailed(String)
    case ffmpegRequiredForMP3

    public var errorDescription: String? {
        switch self {
        case .emptyProject: return "Projet vide (aucun clip à exporter)"
        case .invalidRange: return "Plage d'export invalide"
        case .cannotCreateFile(let m): return "Impossible de créer le fichier : \(m)"
        case .encodingFailed(let m): return "Échec de l'encodage : \(m)"
        case .ffmpegRequiredForMP3: return "ffmpeg est requis pour l'export MP3"
        }
    }
}

public enum AudioExporter {
    /// Renders `project` into memory as `(left: [Float], right: [Float])` at `options.sampleRate` and applies normalization.
    public static func renderMixdown(
        project: AudioProject,
        projectURL: URL?,
        options: AudioExportOptions = AudioExportOptions(),
        pcmStore: PCMStore = .shared,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> (left: [Float], right: [Float], peakDB: Double, lufs: Double) {
        let plan = RenderPlan(project: project, projectURL: projectURL, pcmStore: pcmStore, preloadMissing: true)
        let start = options.range?.lowerBound ?? 0
        let end = options.range?.upperBound ?? plan.totalDuration
        let duration = end - start
        guard duration > 0.001, !plan.tracks.isEmpty else {
            throw AudioExportError.emptyProject
        }

        let sampleRate = max(8_000, options.sampleRate)
        let totalFrames = max(1, Int((duration * sampleRate).rounded()))
        var left = [Float](repeating: 0, count: totalFrames)
        var right = [Float](repeating: 0, count: totalFrames)

        let chunkFrames = 65_536
        var rendered = 0
        try left.withUnsafeMutableBufferPointer { pL in
            try right.withUnsafeMutableBufferPointer { pR in
                while rendered < totalFrames {
                    if Task.isCancelled { throw CancellationError() }
                    let take = min(chunkFrames, totalFrames - rendered)
                    let chunkStart = start + Double(rendered) / sampleRate
                    _ = plan.render(
                        startTime: chunkStart,
                        frameCount: take,
                        sampleRate: sampleRate,
                        outLeft: pL.baseAddress! + rendered,
                        outRight: pR.baseAddress! + rendered
                    )
                    rendered += take
                    progress?(0.7 * Double(rendered) / Double(totalFrames))
                }
            }
        }

        // Downmix to mono if requested
        if options.channels == 1 {
            var half: Float = 0.5
            vDSP_vasm(left, 1, right, 1, &half, &left, 1, vDSP_Length(totalFrames))
            right = left
        }

        // Normalization
        switch options.normalization {
        case .none:
            break
        case .peak:
            var maxL: Float = 0, maxR: Float = 0
            vDSP_maxmgv(left, 1, &maxL, vDSP_Length(totalFrames))
            vDSP_maxmgv(right, 1, &maxR, vDSP_Length(totalFrames))
            let peak = max(maxL, maxR)
            if peak > 1e-6 {
                let target = Float(pow(10.0, -0.1 / 20.0))
                var scale = target / peak
                vDSP_vsmul(left, 1, &scale, &left, 1, vDSP_Length(totalFrames))
                vDSP_vsmul(right, 1, &scale, &right, 1, vDSP_Length(totalFrames))
            }
        case .lufs:
            let measuredLUFS = AudioAnalysis.measureIntegratedLUFS(left: left, right: right, sampleRate: sampleRate)
            if measuredLUFS > -65 {
                let deltaDB = -14.0 - measuredLUFS
                var scale = Float(pow(10.0, deltaDB / 20.0))
                // Cap scale so true peak does not exceed -1.0 dBFS
                var maxL: Float = 0, maxR: Float = 0
                vDSP_maxmgv(left, 1, &maxL, vDSP_Length(totalFrames))
                vDSP_maxmgv(right, 1, &maxR, vDSP_Length(totalFrames))
                let peak = max(maxL, maxR)
                let ceiling = Float(pow(10.0, -1.0 / 20.0))
                if peak * scale > ceiling, peak > 1e-6 {
                    scale = ceiling / peak
                }
                vDSP_vsmul(left, 1, &scale, &left, 1, vDSP_Length(totalFrames))
                vDSP_vsmul(right, 1, &scale, &right, 1, vDSP_Length(totalFrames))
            }
        }

        // Soft clip protection at ±1.0
        var lo: Float = -1.0, hi: Float = 1.0
        vDSP_vclip(left, 1, &lo, &hi, &left, 1, vDSP_Length(totalFrames))
        vDSP_vclip(right, 1, &lo, &hi, &right, 1, vDSP_Length(totalFrames))

        var finalPeakL: Float = 0, finalPeakR: Float = 0
        vDSP_maxmgv(left, 1, &finalPeakL, vDSP_Length(totalFrames))
        vDSP_maxmgv(right, 1, &finalPeakR, vDSP_Length(totalFrames))
        let maxPeak = max(finalPeakL, finalPeakR)
        let peakDB = maxPeak > 1e-6 ? 20.0 * log10(Double(maxPeak)) : -120.0
        let finalLUFS = AudioAnalysis.measureIntegratedLUFS(left: left, right: right, sampleRate: sampleRate)

        progress?(0.85)
        return (left, right, peakDB, finalLUFS)
    }

    /// Exports `project` to `destination` in the requested format.
    @discardableResult
    public static func export(
        project: AudioProject,
        waveforms: WaveformCache? = nil,
        to destination: URL,
        options: ExportOptions = ExportOptions(),
        baseURL: URL? = nil
    ) throws -> ExportResult {
        let ao = options.audioExportOptions
        let mix = try renderMixdown(project: project, projectURL: baseURL, options: ao, pcmStore: .shared)
        try writeAudioFile(left: mix.left, right: mix.right, to: destination, options: ao)
        let dur = Double(mix.left.count) / max(1, options.sampleRate)
        return ExportResult(
            url: destination,
            format: options.format,
            duration: dur,
            sampleRate: options.sampleRate,
            channels: options.channels,
            peakDB: mix.peakDB,
            integratedLUFS: mix.lufs,
            appliedGainDB: 0
        )
    }

    @discardableResult
    public static func exportStems(
        project: AudioProject,
        waveforms: WaveformCache? = nil,
        directory: URL,
        format: ExportFormat = .wav,
        sampleRate: Double = 48_000,
        bitDepth: ExportBitDepth = .int24,
        range: ClosedRange<Double>? = nil,
        baseURL: URL? = nil
    ) throws -> [URL] {
        let baseName = baseURL?.deletingPathExtension().lastPathComponent ?? "Stem"
        let opts = AudioExportOptions(format: format, sampleRate: sampleRate, bitDepth: bitDepth.rawValue, channels: 2, range: range)
        return try exportStems(project: project, projectURL: baseURL, into: directory, baseName: baseName, options: opts)
    }

    @discardableResult
    public static func export(
        project: AudioProject,
        projectURL: URL?,
        to destination: URL,
        options: AudioExportOptions = AudioExportOptions(),
        pcmStore: PCMStore = .shared,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> (url: URL, peakDB: Double, lufs: Double) {
        let mix = try renderMixdown(project: project, projectURL: projectURL, options: options, pcmStore: pcmStore, progress: progress)
        try writeAudioFile(
            left: mix.left,
            right: mix.right,
            to: destination,
            options: options
        )
        progress?(1.0)
        return (destination, mix.peakDB, mix.lufs)
    }

    /// Exports each audible track to its own stem file `<directory>/<project>-<track>.<ext>`.
    public static func exportStems(
        project: AudioProject,
        projectURL: URL?,
        into directory: URL,
        baseName: String,
        options: AudioExportOptions = AudioExportOptions(),
        pcmStore: PCMStore = .shared
    ) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [URL] = []
        for (i, track) in project.tracks.enumerated() where !track.mute && !track.clips.isEmpty {
            var single = project
            var soloTrack = track
            soloTrack.solo = false
            single.tracks = [soloTrack]
            let safeTrackName = track.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            let fileName = "\(baseName)-\(String(format: "%02d", i + 1))-\(safeTrackName).\(options.format.fileExtension)"
            let outURL = directory.appendingPathComponent(fileName)
            _ = try export(project: single, projectURL: projectURL, to: outURL, options: options, pcmStore: pcmStore)
            written.append(outURL)
        }
        return written
    }

    /// Writes planar `(left, right)` float samples to `destination` using Core Audio (`AVAudioFile` / `ffmpeg` for MP3).
    public static func writeAudioFile(
        left: [Float],
        right: [Float],
        to destination: URL,
        options: AudioExportOptions
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: destination)

        if options.format == .mp3 {
            try writeMP3WithFFmpeg(left: left, right: right, to: destination, options: options)
            return
        }

        let frames = AVAudioFrameCount(left.count)
        let ch = AVAudioChannelCount(options.channels)
        guard let processingFormat = AVAudioFormat(standardFormatWithSampleRate: options.sampleRate, channels: ch),
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: frames),
              let floatData = pcmBuffer.floatChannelData else {
            throw AudioExportError.cannotCreateFile(destination.lastPathComponent)
        }
        pcmBuffer.frameLength = frames
        left.withUnsafeBufferPointer { src in
            floatData[0].update(from: src.baseAddress!, count: left.count)
        }
        if options.channels >= 2 {
            right.withUnsafeBufferPointer { src in
                floatData[1].update(from: src.baseAddress!, count: right.count)
            }
        }

        let settings = fileSettings(for: options)
        let isFloat = (settings[AVLinearPCMIsFloatKey] as? Bool) ?? false

        do {
            let outFile = try AVAudioFile(
                forWriting: destination,
                settings: settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: !isFloat && options.format == .flac
            )
            try outFile.write(from: pcmBuffer)
        } catch {
            // Fallback to ffmpeg if system encoder refuses specific bit-depth/container combo
            if let ffmpeg = findFFmpeg() {
                try writeViaFFmpeg(ffmpeg: ffmpeg, left: left, right: right, to: destination, options: options)
            } else {
                throw AudioExportError.encodingFailed(error.localizedDescription)
            }
        }
    }

    private static func fileSettings(for options: AudioExportOptions) -> [String: Any] {
        let sr = options.sampleRate
        let ch = options.channels
        let depth = options.bitDepth
        let isFloat = depth == 32

        switch options.format {
        case .wav:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sr,
                AVNumberOfChannelsKey: ch,
                AVLinearPCMBitDepthKey: depth,
                AVLinearPCMIsFloatKey: isFloat,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        case .aiff:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sr,
                AVNumberOfChannelsKey: ch,
                AVLinearPCMBitDepthKey: depth,
                AVLinearPCMIsFloatKey: isFloat,
                AVLinearPCMIsBigEndianKey: !isFloat,
                AVLinearPCMIsNonInterleaved: false,
            ]
        case .caf:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sr,
                AVNumberOfChannelsKey: ch,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        case .m4a:
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sr,
                AVNumberOfChannelsKey: ch,
                AVEncoderBitRateKey: options.bitRateKbps * 1000,
            ]
        case .alac:
            return [
                AVFormatIDKey: kAudioFormatAppleLossless,
                AVSampleRateKey: sr,
                AVNumberOfChannelsKey: ch,
                AVEncoderBitDepthHintKey: depth == 32 ? 24 : depth,
            ]
        case .flac:
            return [
                AVFormatIDKey: kAudioFormatFLAC,
                AVSampleRateKey: sr,
                AVNumberOfChannelsKey: ch,
                AVLinearPCMBitDepthKey: depth == 32 ? 24 : depth,
            ]
        case .mp3:
            return [:]
        }
    }

    public static func findFFmpeg() -> URL? {
        let candidates = [
            "/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg",
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/opt/local/bin/ffmpeg",
        ] + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/ffmpeg" }
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private static func writeMP3WithFFmpeg(
        left: [Float],
        right: [Float],
        to destination: URL,
        options: AudioExportOptions
    ) throws {
        guard let ffmpeg = findFFmpeg() else {
            throw AudioExportError.ffmpegRequiredForMP3
        }
        try writeViaFFmpeg(ffmpeg: ffmpeg, left: left, right: right, to: destination, options: options)
    }

    private static func writeViaFFmpeg(
        ffmpeg: URL,
        left: [Float],
        right: [Float],
        to destination: URL,
        options: AudioExportOptions
    ) throws {
        let tempWAV = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimpleAudio-export-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tempWAV) }

        var wavOptions = options
        wavOptions.format = .wav
        wavOptions.bitDepth = 32
        try writeAudioFile(left: left, right: right, to: tempWAV, options: wavOptions)

        var args = ["-y", "-loglevel", "error", "-i", tempWAV.path]
        switch options.format {
        case .mp3:
            args += ["-c:a", "libmp3lame", "-b:a", "\(options.bitRateKbps)k"]
        case .flac:
            args += ["-c:a", "flac"]
        case .m4a:
            args += ["-c:a", "aac", "-b:a", "\(options.bitRateKbps)k"]
        case .alac:
            args += ["-c:a", "alac"]
        default:
            break
        }
        args.append(destination.path)

        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = args
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let msg = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw AudioExportError.encodingFailed(msg.isEmpty ? "ffmpeg code \(process.terminationStatus)" : msg)
        }
    }
}
