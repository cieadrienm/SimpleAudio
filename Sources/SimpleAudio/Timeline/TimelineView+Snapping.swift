import AppKit
import SimpleAudioCore

enum TimelineGrid {
    static let niceSteps: [Double] = [
        0.0001, 0.0002, 0.0005,
        0.001, 0.002, 0.005,
        0.01, 0.02, 0.05,
        0.1, 0.2, 0.5,
        1, 2, 5, 10, 15, 30,
        60, 120, 300, 600,
    ]

    static func step(secondsPerPoint: Double, minPoints: Double) -> Double {
        let minTime = max(secondsPerPoint * minPoints, 0.0001)
        return niceSteps.first { $0 >= minTime } ?? 600
    }
}

extension TimelineView {
    func snapTargets(in proj: AudioProject, excludingClip clipID: UUID? = nil) -> [Double] {
        var targets: [Double] = [0, model.playhead]
        for track in proj.tracks {
            for clip in track.clips where clip.id != clipID {
                targets.append(clip.offset)
                targets.append(clip.end)
            }
        }
        for marker in proj.markers {
            targets.append(marker.time)
        }
        if let range = model.selectionRange {
            targets.append(range.lowerBound)
            targets.append(range.upperBound)
        }
        return targets
    }

    func snap(_ value: Double, targets: [Double]) -> (time: Double, snapped: Double?) {
        let clamped = max(0, value)
        guard model.snapping, !(NSEvent.modifierFlags.contains(.command)) else {
            return (clamped, nil)
        }
        let threshold = Double(Metrics.snapPoints) * secondsPerPoint
        var bestTarget: Double?
        var bestDist = threshold
        for t in targets {
            let d = abs(clamped - t)
            if d < bestDist {
                bestDist = d
                bestTarget = t
            }
        }
        if let bestTarget {
            return (max(0, bestTarget), bestTarget)
        }
        return (clamped, nil)
    }

    func snapSpan(
        start: Double,
        duration: Double,
        targets: [Double]
    ) -> (start: Double, snapped: Double?) {
        let clampedStart = max(0, start)
        guard model.snapping, !(NSEvent.modifierFlags.contains(.command)) else {
            return (clampedStart, nil)
        }
        let threshold = Double(Metrics.snapPoints) * secondsPerPoint
        var bestDelta: Double?
        var bestTarget: Double?
        var bestDist = threshold
        for t in targets {
            let dStart = abs(clampedStart - t)
            if dStart < bestDist {
                bestDist = dStart
                bestDelta = t - clampedStart
                bestTarget = t
            }
            let end = clampedStart + duration
            let dEnd = abs(end - t)
            if dEnd < bestDist {
                bestDist = dEnd
                bestDelta = t - end
                bestTarget = t
            }
        }
        if let bestDelta, let bestTarget {
            let snappedStart = max(0, clampedStart + bestDelta)
            return (snappedStart, bestTarget)
        }
        return (clampedStart, nil)
    }
}
