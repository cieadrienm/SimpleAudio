import Accelerate
import AudioToolbox
import AVFoundation
import Combine
import Foundation
import SimpleAudioCore

/// Decoded planar float32 PCM samples of an audio file, kept in a lock-free store so both the real-time
/// audio render thread, the waveform view (at sample zoom), and the offline exporter can read it directly.
public final class AudioPCMData: @unchecked Sendable {
    public let url: URL
    public let sampleRate: Double
    public let channels: [[Float]]
    public let frameCount: Int
    public let duration: Double
    public let maxPeak: Float
    public let formatSummary: String

    public init(url: URL, sampleRate: Double, channels: [[Float]], formatSummary: String) {
        self.url = url
        self.sampleRate = max(1, sampleRate)
        self.channels = channels
        self.frameCount = channels.first?.count ?? 0
        self.duration = self.sampleRate > 0 ? Double(self.frameCount) / self.sampleRate : 0
        var peak: Float = 0
        for ch in channels where !ch.isEmpty {
            var m: Float = 0
            ch.withUnsafeBufferPointer { p in
                vDSP_maxmgv(p.baseAddress!, 1, &m, vDSP_Length(ch.count))
            }
            if m > peak { peak = m }
        }
        self.maxPeak = peak
        self.formatSummary = formatSummary
    }

    public var channelCount: Int { channels.count }
    public var left: [Float] { channels.first ?? [] }
    public var right: [Float] { channels.count >= 2 ? channels[1] : left }

    /// Reads an interpolated stereo sample `(left, right)` at `seconds` in the file.
    @inline(__always)
    public func sample(at seconds: Double) -> (Float, Float) {
        guard frameCount > 0, seconds >= 0 else { return (0, 0) }
        let pos = seconds * sampleRate
        let idx = Int(pos)
        guard idx >= 0, idx < frameCount else { return (0, 0) }
        let frac = Float(pos - Double(idx))
        let next = min(idx + 1, frameCount - 1)
        let c0 = channels[0]
        let s0 = c0[idx] + frac * (c0[next] - c0[idx])
        if channels.count >= 2 {
            let c1 = channels[1]
            let s1 = c1[idx] + frac * (c1[next] - c1[idx])
            return (s0, s1)
        }
        return (s0, s0)
    }
}

/// High-resolution amplitude envelope of an audio file (400 bins/s peak + RMS + L/R).
public struct Waveform: Equatable, Sendable {
    public var binsPerSecond: Double
    public var peaks: [Float]
    public var rms: [Float]
    public var leftPeaks: [Float]
    public var rightPeaks: [Float]
    public var sampleRate: Double
    public var channelCount: Int
    public var fileDuration: Double
    public var maxPeak: Float
    public var formatSummary: String
    public var isComplete: Bool

    public init(
        binsPerSecond: Double = WaveformCache.binsPerSecond,
        peaks: [Float],
        rms: [Float] = [],
        leftPeaks: [Float] = [],
        rightPeaks: [Float] = [],
        sampleRate: Double = 48_000,
        channelCount: Int = 2,
        fileDuration: Double? = nil,
        maxPeak: Float = 0,
        formatSummary: String = "",
        isComplete: Bool = true
    ) {
        self.binsPerSecond = binsPerSecond
        self.peaks = peaks
        self.rms = rms.isEmpty ? peaks.map { $0 * 0.65 } : rms
        self.leftPeaks = leftPeaks.isEmpty ? peaks : leftPeaks
        self.rightPeaks = rightPeaks.isEmpty ? peaks : rightPeaks
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.fileDuration = fileDuration ?? (binsPerSecond > 0 ? Double(peaks.count) / binsPerSecond : 0)
        self.maxPeak = maxPeak > 0 ? maxPeak : (peaks.max() ?? 0)
        self.formatSummary = formatSummary
        self.isComplete = isComplete
    }

    public var duration: Double {
        fileDuration > 0 ? fileDuration : (binsPerSecond > 0 ? Double(peaks.count) / binsPerSecond : 0)
    }

    /// Maximum peak and RMS over `[seconds, seconds + window)`.
    public func values(at seconds: Double, window: Double) -> (peak: Float, rms: Float, left: Float, right: Float) {
        guard !peaks.isEmpty, binsPerSecond > 0, seconds.isFinite else { return (0, 0, 0, 0) }
        let a = Int((seconds * binsPerSecond + 1e-9).rounded(.down))
        let b = Int(((seconds + max(0, window.isFinite ? window : 0)) * binsPerSecond - 1e-9).rounded(.up))
        let lo = max(0, a), hi = min(peaks.count, max(b, a + 1))
        guard lo < hi else { return (0, 0, 0, 0) }
        let len = vDSP_Length(hi - lo)
        var p: Float = 0, r: Float = 0, l: Float = 0, rt: Float = 0
        peaks.withUnsafeBufferPointer { ptr in vDSP_maxv(ptr.baseAddress! + lo, 1, &p, len) }
        if hi <= rms.count {
            rms.withUnsafeBufferPointer { ptr in vDSP_maxv(ptr.baseAddress! + lo, 1, &r, len) }
        }
        if hi <= leftPeaks.count {
            leftPeaks.withUnsafeBufferPointer { ptr in vDSP_maxv(ptr.baseAddress! + lo, 1, &l, len) }
        } else { l = p }
        if hi <= rightPeaks.count {
            rightPeaks.withUnsafeBufferPointer { ptr in vDSP_maxv(ptr.baseAddress! + lo, 1, &rt, len) }
        } else { rt = p }
        return (p, r, l, rt)
    }
}

/// Thread-safe store of decoded `AudioPCMData` accessible from the real-time audio thread and offline exporter.
public final class PCMStore: @unchecked Sendable {
    public static let shared = PCMStore()

    private let lock = NSLock()
    private var storage: [URL: AudioPCMData] = [:]

    public init() {}

    public func get(_ url: URL) -> AudioPCMData? {
        let key = url.standardizedFileURL
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    public func set(_ data: AudioPCMData, for url: URL) {
        let key = url.standardizedFileURL
        lock.lock()
        storage[key] = data
        lock.unlock()
    }

    public func remove(_ url: URL) {
        let key = url.standardizedFileURL
        lock.lock()
        storage[key] = nil
        lock.unlock()
    }

    /// Loads or returns cached PCM synchronously (used off the main thread by exporter or tests).
    public func loadSync(_ url: URL) throws -> AudioPCMData {
        let key = url.standardizedFileURL
        if let existing = get(key) { return existing }
        let (pcm, _) = try WaveformCache.decodeFile(url: key)
        set(pcm, for: key)
        return pcm
    }
}

/// Per-file waveform & PCM cache, computed off the main thread with `AVAudioFile` + `Accelerate`.
@MainActor
public final class WaveformCache: ObservableObject {
    public static let shared = WaveformCache()
    public nonisolated static let binsPerSecond: Double = 400

    public var onUpdate: (() -> Void)?
    @Published public private(set) var progress: [URL: Double] = [:]

    private var store: [URL: Waveform] = [:]
    private var tasks: [URL: Task<Void, Never>] = [:]

    public init() {}

    public func envelope(for url: URL) -> Waveform? {
        let key = url.standardizedFileURL
        if let w = store[key] { return w }
        start(key)
        return nil
    }

    public func pcm(for url: URL) -> AudioPCMData? {
        PCMStore.shared.get(url)
    }

    public var pendingCount: Int { tasks.count }

    public func waveform(for url: URL) async -> Waveform {
        let key = url.standardizedFileURL
        if let w = store[key], w.isComplete { return w }
        start(key)
        await tasks[key]?.value
        return store[key] ?? Waveform(peaks: [])
    }

    /// Synchronously decodes and caches `url` (convenient for tests and immediate single-file open).
    @discardableResult
    public func preloadSync(_ url: URL) -> Waveform? {
        let key = url.standardizedFileURL
        if let w = store[key], w.isComplete { return w }
        guard let (pcm, wave) = try? Self.decodeFile(url: key) else { return nil }
        PCMStore.shared.set(pcm, for: key)
        store[key] = wave
        onUpdate?()
        return wave
    }

    @discardableResult
    public func load(url: URL) -> Waveform? {
        preloadSync(url)
    }

    public func loadPCM(for url: URL) -> AudioPCMData? {
        let key = url.standardizedFileURL
        if let existing = PCMStore.shared.get(key) { return existing }
        _ = preloadSync(key)
        return PCMStore.shared.get(key)
    }

    public func probe(url: URL) -> (duration: Double, sampleRate: Double, channels: Int) {
        if let w = preloadSync(url) {
            return (w.duration, w.sampleRate, w.channelCount)
        }
        return (0, 48_000, 2)
    }

    public func invalidate(_ url: URL) {
        let key = url.standardizedFileURL
        tasks[key]?.cancel()
        tasks[key] = nil
        store[key] = nil
        progress[key] = nil
        PCMStore.shared.remove(key)
    }

    private func start(_ url: URL) {
        guard tasks[url] == nil, store[url]?.isComplete != true else { return }
        progress[url] = 0
        tasks[url] = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let (pcm, wave) = try Self.decodeFile(url: url)
                PCMStore.shared.set(pcm, for: url)
                await self?.land(url, wave)
            } catch {
                await self?.land(url, Waveform(peaks: []))
            }
        }
    }

    private func land(_ url: URL, _ w: Waveform) {
        store[url] = w
        tasks[url] = nil
        progress[url] = nil
        onUpdate?()
    }

    // MARK: Fast AVAudioFile + Accelerate Decoder

    public enum DecodeError: Error, LocalizedError {
        case unreadable(URL)
        public var errorDescription: String? {
            if case .unreadable(let u) = self { return "Fichier audio illisible : \(u.lastPathComponent)" }
            return nil
        }
    }

    /// Decodes an audio file into planar float channels + 400 Hz peak/RMS/L/R `Waveform` in one pass.
    public nonisolated static func decodeFile(
        url: URL,
        binsPerSecond: Double = binsPerSecond
    ) throws -> (AudioPCMData, Waveform) {
        if let result = try? decodeWithAVAudioFile(url: url, binsPerSecond: binsPerSecond) {
            return result
        }
        return try decodeWithAssetReader(url: url, binsPerSecond: binsPerSecond)
    }

    private nonisolated static func decodeWithAVAudioFile(
        url: URL,
        binsPerSecond: Double
    ) throws -> (AudioPCMData, Waveform) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let chCount = Int(format.channelCount)
        let totalFrames = Int(file.length)
        guard sampleRate > 0, chCount > 0, totalFrames > 0 else {
            throw DecodeError.unreadable(url)
        }

        let ext = url.pathExtension.uppercased()
        let rateKHz = sampleRate.truncatingRemainder(dividingBy: 1000) == 0
            ? "\(Int(sampleRate / 1000)) kHz"
            : String(format: "%.1f kHz", sampleRate / 1000)
        let chLabel = chCount == 1 ? "Mono" : (chCount == 2 ? "Stéréo" : "\(chCount) canaux")
        let summary = "\(ext.isEmpty ? "AUDIO" : ext) · \(rateKHz) · \(chLabel)"

        var channels = Array(repeating: [Float](), count: min(chCount, 2))
        for c in channels.indices { channels[c].reserveCapacity(totalFrames) }

        let chunkSize: AVAudioFrameCount = 65_536
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else {
            throw DecodeError.unreadable(url)
        }

        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: chunkSize)
            let n = Int(buffer.frameLength)
            guard n > 0, let floatData = buffer.floatChannelData else { break }
            for c in channels.indices {
                channels[c].append(contentsOf: UnsafeBufferPointer(start: floatData[c], count: n))
            }
        }

        guard let firstChannel = channels.first, !firstChannel.isEmpty else {
            throw DecodeError.unreadable(url)
        }

        let pcm = AudioPCMData(url: url, sampleRate: sampleRate, channels: channels, formatSummary: summary)
        let wave = buildWaveform(from: pcm, binsPerSecond: binsPerSecond)
        return (pcm, wave)
    }

    private nonisolated static func decodeWithAssetReader(
        url: URL,
        binsPerSecond: Double
    ) throws -> (AudioPCMData, Waveform) {
        let asset = AVURLAsset(url: url)
        let semaphore = DispatchSemaphore(value: 0)
        final class TrackBox: @unchecked Sendable { var track: AVAssetTrack? }
        let box = TrackBox()
        Task.detached {
            box.track = try? await asset.load(.tracks).first { $0.mediaType == .audio }
            semaphore.signal()
        }
        semaphore.wait()
        guard let track = box.track else { throw DecodeError.unreadable(url) }

        let sampleRate = 48_000.0
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: sampleRate,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw DecodeError.unreadable(url) }
        reader.add(output)
        guard reader.startReading() else { throw DecodeError.unreadable(url) }

        var left: [Float] = []
        var right: [Float] = []
        var scratch: [Float] = []
        while let sb = output.copyNextSampleBuffer() {
            guard let bb = CMSampleBufferGetDataBuffer(sb) else { continue }
            let length = CMBlockBufferGetDataLength(bb)
            let count = length / MemoryLayout<Float>.size
            guard count >= 2 else { continue }
            if scratch.count < count { scratch = [Float](repeating: 0, count: count) }
            scratch.withUnsafeMutableBytes { raw in
                _ = CMBlockBufferCopyDataBytes(bb, atOffset: 0, dataLength: count * MemoryLayout<Float>.size, destination: raw.baseAddress!)
            }
            let frames = count / 2
            left.reserveCapacity(left.count + frames)
            right.reserveCapacity(right.count + frames)
            for i in 0..<frames {
                left.append(scratch[i * 2])
                right.append(scratch[i * 2 + 1])
            }
        }
        guard !left.isEmpty else { throw DecodeError.unreadable(url) }
        let ext = url.pathExtension.uppercased()
        let summary = "\(ext.isEmpty ? "AUDIO" : ext) · 48 kHz · Stéréo"
        let pcm = AudioPCMData(url: url, sampleRate: sampleRate, channels: [left, right], formatSummary: summary)
        let wave = buildWaveform(from: pcm, binsPerSecond: binsPerSecond)
        return (pcm, wave)
    }

    public nonisolated static func buildWaveform(from pcm: AudioPCMData, binsPerSecond: Double = binsPerSecond) -> Waveform {
        let totalFrames = pcm.frameCount
        guard totalFrames > 0, pcm.sampleRate > 0 else {
            return Waveform(binsPerSecond: binsPerSecond, peaks: [], formatSummary: pcm.formatSummary)
        }
        let samplesPerBin = max(1, Int((pcm.sampleRate / binsPerSecond).rounded()))
        let binCount = (totalFrames + samplesPerBin - 1) / samplesPerBin

        var peaks = [Float](repeating: 0, count: binCount)
        var rms = [Float](repeating: 0, count: binCount)
        var leftPeaks = [Float](repeating: 0, count: binCount)
        var rightPeaks = [Float](repeating: 0, count: binCount)

        let ch0 = pcm.channels[0]
        let ch1 = pcm.channels.count >= 2 ? pcm.channels[1] : pcm.channels[0]
        let isStereo = pcm.channels.count >= 2

        ch0.withUnsafeBufferPointer { p0 in
            ch1.withUnsafeBufferPointer { p1 in
                for b in 0..<binCount {
                    let start = b * samplesPerBin
                    let count = min(samplesPerBin, totalFrames - start)
                    guard count > 0 else { continue }
                    let len = vDSP_Length(count)
                    var lPeak: Float = 0
                    var lRMS: Float = 0
                    vDSP_maxmgv(p0.baseAddress! + start, 1, &lPeak, len)
                    vDSP_rmsqv(p0.baseAddress! + start, 1, &lRMS, len)
                    if isStereo {
                        var rPeak: Float = 0
                        var rRMS: Float = 0
                        vDSP_maxmgv(p1.baseAddress! + start, 1, &rPeak, len)
                        vDSP_rmsqv(p1.baseAddress! + start, 1, &rRMS, len)
                        leftPeaks[b] = min(lPeak, 1)
                        rightPeaks[b] = min(rPeak, 1)
                        peaks[b] = min(max(lPeak, rPeak), 1)
                        rms[b] = min(sqrt(0.5 * (lRMS * lRMS + rRMS * rRMS)), 1)
                    } else {
                        leftPeaks[b] = min(lPeak, 1)
                        rightPeaks[b] = min(lPeak, 1)
                        peaks[b] = min(lPeak, 1)
                        rms[b] = min(lRMS, 1)
                    }
                }
            }
        }

        return Waveform(
            binsPerSecond: pcm.sampleRate / Double(samplesPerBin),
            peaks: peaks,
            rms: rms,
            leftPeaks: leftPeaks,
            rightPeaks: rightPeaks,
            sampleRate: pcm.sampleRate,
            channelCount: pcm.channelCount,
            fileDuration: pcm.duration,
            maxPeak: pcm.maxPeak,
            formatSummary: pcm.formatSummary,
            isComplete: true
        )
    }
}
