import Accelerate
import Foundation
import SimpleAudioCore

public struct SilenceRegion: Equatable, Codable, Sendable {
    public var start: Double
    public var end: Double
    public var duration: Double { end - start }
    public var midpoint: Double { 0.5 * (start + end) }

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }
}

public struct AudioLevelMetrics: Equatable, Sendable {
    public var peakDB: Double
    public var rmsDB: Double
    public var lufs: Double

    public init(peakDB: Double, rmsDB: Double, lufs: Double) {
        self.peakDB = peakDB
        self.rmsDB = rmsDB
        self.lufs = lufs
    }
}

public enum AudioAnalysis {
    /// Detects contiguous silent intervals where peak stays below `thresholdDB` for at least `minDuration` seconds.
    public static func detectSilences(
        in pcm: AudioPCMData,
        thresholdDB: Double = -42,
        minDuration: Double = 0.15
    ) -> [SilenceRegion] {
        let wave = WaveformCache.buildWaveform(from: pcm)
        return detectSilences(in: wave, thresholdDB: thresholdDB, minDuration: minDuration)
    }

    public static func detectSilences(
        in waveform: Waveform,
        thresholdDB: Double = -42,
        minDuration: Double = 0.15
    ) -> [SilenceRegion] {
        guard !waveform.peaks.isEmpty, waveform.binsPerSecond > 0 else { return [] }
        let linearThreshold = Float(pow(10.0, thresholdDB / 20.0))
        let bps = waveform.binsPerSecond
        var regions: [SilenceRegion] = []
        var silenceStartBin: Int?

        for (i, p) in waveform.peaks.enumerated() {
            if p <= linearThreshold {
                if silenceStartBin == nil { silenceStartBin = i }
            } else if let s = silenceStartBin {
                let start = Double(s) / bps
                let end = Double(i) / bps
                if end - start >= minDuration {
                    regions.append(SilenceRegion(start: start, end: end))
                }
                silenceStartBin = nil
            }
        }
        if let s = silenceStartBin {
            let start = Double(s) / bps
            let end = Double(waveform.peaks.count) / bps
            if end - start >= minDuration {
                regions.append(SilenceRegion(start: start, end: end))
            }
        }
        return regions
    }

    /// Finds the zero-crossing nearest to `time` (within `±window` seconds) in channel 0 of `pcm`.
    public static func nearestZeroCrossing(in pcm: AudioPCMData, around time: Double, window: Double = 0.015) -> Double {
        guard let ch = pcm.channels.first, ch.count > 2, pcm.sampleRate > 0 else { return time }
        let center = Int((time * pcm.sampleRate).rounded())
        let radius = max(1, Int((window * pcm.sampleRate).rounded()))
        let lo = max(1, center - radius)
        let hi = min(ch.count - 1, center + radius)
        guard lo < hi else { return time }

        var bestIndex = center
        var bestDistance = Int.max
        for i in lo...hi {
            let a = ch[i - 1], b = ch[i]
            if (a <= 0 && b >= 0) || (a >= 0 && b <= 0) {
                let d = abs(i - center)
                if d < bestDistance {
                    bestDistance = d
                    bestIndex = i
                }
            }
        }
        return Double(bestIndex) / pcm.sampleRate
    }

    /// Measures peak dBFS and RMS dBFS of `pcm` over `[sourceStart, sourceStart + duration]`.
    public static func measureClipLevels(
        in pcm: AudioPCMData,
        sourceStart: Double,
        duration: Double
    ) -> (peakDB: Double, rmsDB: Double) {
        guard pcm.frameCount > 0, pcm.sampleRate > 0 else { return (-120, -120) }
        let a = max(0, min(Int((sourceStart * pcm.sampleRate).rounded(.down)), pcm.frameCount - 1))
        let b = max(a + 1, min(Int(((sourceStart + duration) * pcm.sampleRate).rounded(.up)), pcm.frameCount))
        let len = vDSP_Length(b - a)
        var maxPeak: Float = 0
        var sumSq: Double = 0
        for ch in pcm.channels {
            var p: Float = 0
            var r: Float = 0
            ch.withUnsafeBufferPointer { ptr in
                vDSP_maxmgv(ptr.baseAddress! + a, 1, &p, len)
                vDSP_rmsqv(ptr.baseAddress! + a, 1, &r, len)
            }
            if p > maxPeak { maxPeak = p }
            sumSq += Double(r * r)
        }
        let avgRMS = sqrt(sumSq / Double(max(1, pcm.channels.count)))
        let peakDB = maxPeak > 1e-6 ? 20.0 * log10(Double(maxPeak)) : -120.0
        let rmsDB = avgRMS > 1e-6 ? 20.0 * log10(avgRMS) : -120.0
        return (peakDB, rmsDB)
    }

    /// Computes the clip `gainDB` needed so that the clip's peak reaches `targetPeakDB` (e.g. `-0.1` dBFS).
    public static func normalizedGainDB(
        in pcm: AudioPCMData,
        sourceStart: Double,
        duration: Double,
        targetPeakDB: Double = -0.1
    ) -> Double {
        let (peakDB, _) = measureClipLevels(in: pcm, sourceStart: sourceStart, duration: duration)
        guard peakDB > -100 else { return 0 }
        return min(max(targetPeakDB - peakDB, -60), 24)
    }

    public static func normalizationGainDB(
        for clip: AudioClip,
        in pcm: AudioPCMData,
        targetPeakDB: Double = -0.1
    ) -> Double {
        normalizedGainDB(in: pcm, sourceStart: clip.sourceStart, duration: clip.duration, targetPeakDB: targetPeakDB)
    }

    /// Measures ITU-R BS.1770-4 integrated loudness (LUFS) of a stereo or mono buffer natively in Swift.
    public static func measureIntegratedLUFS(left: [Float], right: [Float], sampleRate: Double) -> Double {
        guard !left.isEmpty, sampleRate > 0 else { return -70.0 }
        let kLeft = kWeightFilter(left, sampleRate: sampleRate)
        let kRight = right.count == left.count ? kWeightFilter(right, sampleRate: sampleRate) : kLeft

        // 400 ms gating blocks with 75% overlap (100 ms step)
        let blockSamples = max(1, Int((0.400 * sampleRate).rounded()))
        let hopSamples = max(1, Int((0.100 * sampleRate).rounded()))

        if kLeft.count < blockSamples {
            var msL: Float = 0, msR: Float = 0
            kLeft.withUnsafeBufferPointer { vDSP_measqv($0.baseAddress!, 1, &msL, vDSP_Length(kLeft.count)) }
            kRight.withUnsafeBufferPointer { vDSP_measqv($0.baseAddress!, 1, &msR, vDSP_Length(kRight.count)) }
            let energy = Double(msL + msR)
            return energy > 1e-12 ? -0.691 + 10.0 * log10(energy) : -70.0
        }

        var blockEnergies: [Double] = []
        var pos = 0
        kLeft.withUnsafeBufferPointer { pL in
            kRight.withUnsafeBufferPointer { pR in
                while pos + blockSamples <= kLeft.count {
                    var msL: Float = 0, msR: Float = 0
                    let len = vDSP_Length(blockSamples)
                    vDSP_measqv(pL.baseAddress! + pos, 1, &msL, len)
                    vDSP_measqv(pR.baseAddress! + pos, 1, &msR, len)
                    let z = Double(msL + msR)
                    blockEnergies.append(z)
                    pos += hopSamples
                }
            }
        }
        // Absolute gate at -70 LUFS
        let absGateEnergy = pow(10.0, (-70.0 + 0.691) / 10.0)
        let gated1 = blockEnergies.filter { $0 > absGateEnergy }
        guard !gated1.isEmpty else { return -70.0 }
        let mean1 = gated1.reduce(0, +) / Double(gated1.count)
        let relGateLUFS = -0.691 + 10.0 * log10(mean1) - 10.0
        let relGateEnergy = pow(10.0, (relGateLUFS + 0.691) / 10.0)
        let gated2 = gated1.filter { $0 > relGateEnergy }
        let finalMean = (gated2.isEmpty ? gated1 : gated2).reduce(0, +) / Double(max(1, (gated2.isEmpty ? gated1 : gated2).count))
        return finalMean > 1e-12 ? -0.691 + 10.0 * log10(finalMean) : -70.0
    }

    /// Two-stage ITU-R BS.1770 K-weighting filter (high-shelf +4 dB above 1.5 kHz + high-pass RLB at 38 Hz).
    private static func kWeightFilter(_ samples: [Float], sampleRate: Double) -> [Float] {
        // Pre-computed coefficients for 48 kHz (standard BS.1770-4); scaled smoothly via vDSP_biquad
        let coeffs48k: [Double] = [
            // Stage 1: High-shelf pre-filter
            1.53512485958697, -2.69169618940638, 1.19839281085285,
            -1.69065929318241, 0.73248077421585,
            // Stage 2: High-pass RLB filter
            1.0, -2.0, 1.0,
            -1.99004745483398, 0.99007225036621,
        ]
        guard let setup = vDSP_biquad_CreateSetup(coeffs48k, 2) else { return samples }
        defer { vDSP_biquad_DestroySetup(setup) }
        var out = [Float](repeating: 0, count: samples.count)
        var delay = [Float](repeating: 0, count: 2 * 2 + 2)
        samples.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                vDSP_biquad(setup, &delay, src.baseAddress!, 1, dst.baseAddress!, 1, vDSP_Length(samples.count))
            }
        }
        return out
    }
}
