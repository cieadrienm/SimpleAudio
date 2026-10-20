import Foundation

extension AudioProject {
    // MARK: Track operations

    @discardableResult
    public mutating func addTrack(name: String? = nil, at index: Int? = nil) -> UUID {
        let idx = index.map { min(max($0, 0), tracks.count) } ?? tracks.count
        let defaultName = name ?? "Piste \(tracks.count + 1)"
        let track = AudioTrack(name: defaultName, colorIndex: tracks.count)
        tracks.insert(track, at: idx)
        return track.id
    }

    public mutating func removeTrack(_ id: UUID) {
        guard let i = trackIndex(of: id), !tracks[i].locked else { return }
        tracks.remove(at: i)
    }

    public mutating func moveTrack(_ id: UUID, to destination: Int) {
        guard let from = trackIndex(of: id) else { return }
        let track = tracks.remove(at: from)
        let clamped = min(max(destination, 0), tracks.count)
        tracks.insert(track, at: clamped)
    }

    @discardableResult
    public mutating func duplicateTrack(_ id: UUID) -> UUID? {
        guard let i = trackIndex(of: id) else { return nil }
        var copy = tracks[i]
        copy.id = UUID()
        copy.name = copy.name + " (copie)"
        copy.colorIndex = tracks.count
        copy.locked = false
        copy.clips = copy.clips.map { c in
            var cc = c
            cc.id = UUID()
            return cc
        }
        tracks.insert(copy, at: i + 1)
        return copy.id
    }

    public mutating func setTrack(
        _ id: UUID,
        name: String? = nil,
        gainDB: Double? = nil,
        pan: Double? = nil,
        mute: Bool? = nil,
        solo: Bool? = nil,
        locked: Bool? = nil,
        stereoSplit: Bool? = nil,
        height: Double? = nil,
        colorIndex: Int? = nil
    ) {
        guard let i = trackIndex(of: id) else { return }
        if let name, !name.isEmpty { tracks[i].name = name }
        if let gainDB { tracks[i].gainDB = min(max(gainDB, -60), 24) }
        if let pan { tracks[i].pan = min(max(pan, -1), 1) }
        if let mute { tracks[i].mute = mute }
        if let solo { tracks[i].solo = solo }
        if let locked { tracks[i].locked = locked }
        if let stereoSplit { tracks[i].stereoSplit = stereoSplit }
        if let height { tracks[i].height = min(max(height, 48), 260) }
        if let colorIndex { tracks[i].colorIndex = max(0, colorIndex) }
    }

    // MARK: Clip operations

    @discardableResult
    public mutating func addClip(_ clip: AudioClip, toTrack trackID: UUID? = nil) -> UUID {
        let ti: Int
        if let trackID, let idx = trackIndex(of: trackID) {
            ti = idx
        } else if !tracks.isEmpty {
            ti = 0
        } else {
            let newID = addTrack()
            ti = trackIndex(of: newID) ?? 0
        }
        guard !tracks[ti].locked else { return clip.id }
        tracks[ti].clips.append(clip)
        sortClips(inTrackAt: ti)
        return clip.id
    }

    /// Trims the left edge of a clip: `newOffset` moves `offset` and `sourceStart` together while keeping `end` fixed.
    public mutating func trimClipStart(id: UUID, to newOffset: Double, knownSourceDuration: Double? = nil) {
        guard let (ti, ci) = clipLocation(of: id), !tracks[ti].locked else { return }
        var c = tracks[ti].clips[ci]
        let oldEnd = c.end
        let minOffset: Double
        if c.reversed {
            let maxDur = knownSourceDuration ?? c.sourceDuration
            minOffset = max(0, oldEnd - (maxDur - c.sourceStart))
        } else {
            minOffset = max(0, c.offset - c.sourceStart)
        }
        let maxOffset = oldEnd - AudioClip.minDuration
        let clampedOffset = min(max(newOffset, minOffset), maxOffset)
        let delta = clampedOffset - c.offset
        guard abs(delta) > 1e-7 else { return }
        c.offset = clampedOffset
        c.duration = max(AudioClip.minDuration, oldEnd - clampedOffset)
        if !c.reversed {
            c.sourceStart = max(0, c.sourceStart + delta)
        }
        c.fadeIn = max(0, c.fadeIn - delta)
        c.clampFades()
        tracks[ti].clips[ci] = c
        sortClips(inTrackAt: ti)
    }

    /// Trims the right edge of a clip: `newEnd` changes `duration` while keeping `offset` fixed.
    public mutating func trimClipEnd(id: UUID, to newEnd: Double, knownSourceDuration: Double? = nil) {
        guard let (ti, ci) = clipLocation(of: id), !tracks[ti].locked else { return }
        var c = tracks[ti].clips[ci]
        let minEnd = c.offset + AudioClip.minDuration
        let maxDur = knownSourceDuration ?? c.sourceDuration
        let maxEnd: Double
        if c.reversed {
            maxEnd = c.offset + c.sourceEnd
        } else {
            maxEnd = c.offset + max(AudioClip.minDuration, maxDur - c.sourceStart)
        }
        let clampedEnd = min(max(newEnd, minEnd), maxEnd)
        let newDuration = max(AudioClip.minDuration, clampedEnd - c.offset)
        let delta = newDuration - c.duration
        guard abs(delta) > 1e-7 else { return }
        if c.reversed {
            c.sourceStart = max(0, c.sourceStart - delta)
        }
        c.duration = newDuration
        c.fadeOut = max(0, c.fadeOut + delta)
        c.clampFades()
        tracks[ti].clips[ci] = c
    }

    public mutating func moveClip(id: UUID, toOffset newOffset: Double, toTrack targetTrackID: UUID? = nil) {
        guard let (ti, ci) = clipLocation(of: id), !tracks[ti].locked else { return }
        var c = tracks[ti].clips[ci]
        c.offset = max(0, newOffset)
        if let targetTrackID, let destTI = trackIndex(of: targetTrackID), destTI != ti {
            guard !tracks[destTI].locked else { return }
            tracks[ti].clips.remove(at: ci)
            tracks[destTI].clips.append(c)
            sortClips(inTrackAt: destTI)
        } else {
            tracks[ti].clips[ci] = c
            sortClips(inTrackAt: ti)
        }
    }

    /// Slips the audio inside a clip (`sourceStart` shifts by `delta`, `offset` and `duration` stay put).
    public mutating func slipClip(id: UUID, by delta: Double, knownSourceDuration: Double? = nil) {
        guard let (ti, ci) = clipLocation(of: id), !tracks[ti].locked else { return }
        var c = tracks[ti].clips[ci]
        let maxDur = knownSourceDuration ?? c.sourceDuration
        let upper = max(0, maxDur - c.duration)
        c.sourceStart = min(max(0, c.sourceStart + delta), upper)
        tracks[ti].clips[ci] = c
    }

    /// Splits clip `id` at timeline `time`, returning `(leftID, rightID)` if `time` is strictly inside the clip.
    @discardableResult
    public mutating func splitClip(id: UUID, at time: Double, crossfadeProtection: Double = 0.005) -> (UUID, UUID)? {
        guard let (ti, ci) = clipLocation(of: id), !tracks[ti].locked else { return nil }
        let c = tracks[ti].clips[ci]
        guard time > c.offset + AudioClip.minDuration, time < c.end - AudioClip.minDuration else { return nil }
        let leftDuration = time - c.offset
        let rightDuration = c.end - time

        var left = c
        left.duration = leftDuration
        left.fadeOut = min(crossfadeProtection, leftDuration / 3)
        if c.reversed {
            left.sourceStart = c.sourceStart + rightDuration
        }
        left.clampFades()

        var right = c
        right.id = UUID()
        right.offset = time
        right.duration = rightDuration
        right.fadeIn = min(crossfadeProtection, rightDuration / 3)
        if !c.reversed {
            right.sourceStart = c.sourceStart + leftDuration
        }
        right.clampFades()

        tracks[ti].clips[ci] = left
        tracks[ti].clips.insert(right, at: ci + 1)
        sortClips(inTrackAt: ti)
        return (left.id, right.id)
    }

    /// Splits all clips under `time` on `trackIDs` (or all unlocked tracks when `trackIDs` is nil/empty).
    @discardableResult
    public mutating func splitAt(time: Double, clipIDs: Set<UUID>? = nil, trackIDs: Set<UUID>? = nil) -> [UUID] {
        var created: [UUID] = []
        for ti in tracks.indices where !tracks[ti].locked {
            if let trackIDs, !trackIDs.isEmpty, !trackIDs.contains(tracks[ti].id) { continue }
            let matching = tracks[ti].clips.filter { c in
                if let clipIDs, !clipIDs.isEmpty, !clipIDs.contains(c.id) { return false }
                return time > c.offset + AudioClip.minDuration && time < c.end - AudioClip.minDuration
            }
            for c in matching {
                if let (_, rightID) = splitClip(id: c.id, at: time) {
                    created.append(rightID)
                }
            }
        }
        return created
    }

    public mutating func removeClips(_ ids: Set<UUID>, ripple: Bool = false) {
        guard !ids.isEmpty else { return }
        for ti in tracks.indices where !tracks[ti].locked {
            let removed = tracks[ti].clips.filter { ids.contains($0.id) }
            guard !removed.isEmpty else { continue }
            tracks[ti].clips.removeAll { ids.contains($0.id) }
            if ripple, let first = removed.map(\.offset).min(), let last = removed.map(\.end).max() {
                let shift = max(0, last - first)
                for ci in tracks[ti].clips.indices where tracks[ti].clips[ci].offset >= last - 1e-6 {
                    tracks[ti].clips[ci].offset = max(first, tracks[ti].clips[ci].offset - shift)
                }
            }
        }
    }

    @discardableResult
    public mutating func duplicateClips(_ ids: Set<UUID>) -> [UUID] {
        var newIDs: [UUID] = []
        for ti in tracks.indices where !tracks[ti].locked {
            let selected = tracks[ti].clips.filter { ids.contains($0.id) }
            guard !selected.isEmpty,
                  let minStart = selected.map(\.offset).min(),
                  let maxEnd = selected.map(\.end).max() else { continue }
            let span = max(AudioClip.minDuration, maxEnd - minStart)
            for c in selected {
                var copy = c
                copy.id = UUID()
                copy.offset = c.offset + span
                tracks[ti].clips.append(copy)
                newIDs.append(copy.id)
            }
            sortClips(inTrackAt: ti)
        }
        return newIDs
    }

    public mutating func setClipFades(id: UUID, fadeIn: Double? = nil, fadeOut: Double? = nil, shape: FadeShape? = nil) {
        guard let (ti, ci) = clipLocation(of: id), !tracks[ti].locked else { return }
        var c = tracks[ti].clips[ci]
        if let fadeIn { c.fadeIn = min(max(0, fadeIn), c.duration) }
        if let fadeOut { c.fadeOut = min(max(0, fadeOut), c.duration) }
        if let shape { c.fadeShape = shape }
        c.clampFades()
        tracks[ti].clips[ci] = c
    }

    public mutating func setClipGain(id: UUID, db: Double) {
        guard let (ti, ci) = clipLocation(of: id), !tracks[ti].locked else { return }
        tracks[ti].clips[ci].gainDB = min(max(db, -60), 24)
    }

    public mutating func setClipMute(id: UUID, _ mute: Bool) {
        guard let (ti, ci) = clipLocation(of: id), !tracks[ti].locked else { return }
        tracks[ti].clips[ci].mute = mute
    }

    public mutating func setClipReversed(id: UUID, _ reversed: Bool) {
        guard let (ti, ci) = clipLocation(of: id), !tracks[ti].locked else { return }
        tracks[ti].clips[ci].reversed = reversed
    }

    public mutating func setClipName(id: UUID, _ name: String) {
        guard let (ti, ci) = clipLocation(of: id), !tracks[ti].locked, !name.isEmpty else { return }
        tracks[ti].clips[ci].name = name
    }

    public mutating func setClipTiming(id: UUID, offset: Double? = nil, sourceStart: Double? = nil, duration: Double? = nil) {
        guard let (ti, ci) = clipLocation(of: id), !tracks[ti].locked else { return }
        var c = tracks[ti].clips[ci]
        if let offset { c.offset = max(0, offset) }
        if let sourceStart { c.sourceStart = max(0, sourceStart) }
        if let duration {
            let maxAllowed = max(AudioClip.minDuration, c.sourceDuration - c.sourceStart)
            c.duration = min(max(AudioClip.minDuration, duration), maxAllowed)
        }
        c.clampFades()
        tracks[ti].clips[ci] = c
        sortClips(inTrackAt: ti)
    }

    /// Creates a crossfade of `duration` seconds between two consecutive clips on a track by overlapping or setting fades.
    public mutating func crossfade(clipA idA: UUID, clipB idB: UUID, duration: Double = 0.25) {
        guard let (tiA, ciA) = clipLocation(of: idA),
              let (tiB, ciB) = clipLocation(of: idB),
              tiA == tiB, !tracks[tiA].locked else { return }
        let firstIdx = min(ciA, ciB), secondIdx = max(ciA, ciB)
        var a = tracks[tiA].clips[firstIdx]
        var b = tracks[tiA].clips[secondIdx]
        let d = min(max(0.01, duration), min(a.duration, b.duration) * 0.5)
        // If they touch or nearly touch, overlap them by d/2 each (when source handles allow) or shift B left by d.
        if abs(b.offset - a.end) < d {
            let overlap = b.offset < a.end ? (a.end - b.offset) : d
            if b.offset >= a.end {
                b.offset = max(a.offset + AudioClip.minDuration, a.end - d)
            }
            a.fadeOut = max(a.fadeOut, overlap)
            b.fadeIn = max(b.fadeIn, overlap)
            a.clampFades()
            b.clampFades()
            tracks[tiA].clips[firstIdx] = a
            tracks[tiA].clips[secondIdx] = b
            sortClips(inTrackAt: tiA)
        }
    }

    // MARK: Time-Range (Selection) Operations — Copy, Cut, Paste, Delete, Crop, Silence, Fade

    /// Extracts audio slices overlapping `range` on `trackIDs` (nil = all tracks).
    public func extractSlices(in range: ClosedRange<Double>, trackIDs: Set<UUID>? = nil) -> [ClipboardSlice] {
        guard range.upperBound > range.lowerBound + AudioClip.minDuration else { return [] }
        var slices: [ClipboardSlice] = []
        for (ti, track) in tracks.enumerated() {
            if let trackIDs, !trackIDs.isEmpty, !trackIDs.contains(track.id) { continue }
            for c in track.clips {
                let lo = max(range.lowerBound, c.offset)
                let hi = min(range.upperBound, c.end)
                guard hi - lo >= AudioClip.minDuration else { continue }
                var slice = c
                slice.id = UUID()
                let trimLeft = lo - c.offset
                let trimRight = c.end - hi
                slice.offset = lo
                slice.duration = hi - lo
                if c.reversed {
                    slice.sourceStart = c.sourceStart + trimRight
                } else {
                    slice.sourceStart = c.sourceStart + trimLeft
                }
                slice.fadeIn = max(0, c.fadeIn - trimLeft)
                slice.fadeOut = max(0, c.fadeOut - trimRight)
                if trimLeft > 1e-5 { slice.fadeIn = max(slice.fadeIn, min(0.005, slice.duration / 4)) }
                if trimRight > 1e-5 { slice.fadeOut = max(slice.fadeOut, min(0.005, slice.duration / 4)) }
                slice.clampFades()
                slices.append(ClipboardSlice(trackIndex: ti, relativeOffset: lo - range.lowerBound, clip: slice))
            }
        }
        return slices
    }

    /// Extracts whole selected clips as `ClipboardSlice`s relative to the earliest selected clip.
    public func extractClips(_ ids: Set<UUID>) -> [ClipboardSlice] {
        var found: [(Int, AudioClip)] = []
        for (ti, track) in tracks.enumerated() {
            for c in track.clips where ids.contains(c.id) {
                found.append((ti, c))
            }
        }
        guard let minOffset = found.map({ $0.1.offset }).min() else { return [] }
        return found.map { ti, c in
            var copy = c
            copy.id = UUID()
            return ClipboardSlice(trackIndex: ti, relativeOffset: c.offset - minOffset, clip: copy)
        }
    }

    /// Deletes the audio inside `range` on `trackIDs` (nil = all unlocked tracks).
    /// When `ripple == true`, clips starting at or after `range.upperBound` shift left by `range`'s length.
    public mutating func deleteRange(_ range: ClosedRange<Double>, trackIDs: Set<UUID>? = nil, ripple: Bool = false) {
        let span = range.upperBound - range.lowerBound
        guard span >= AudioClip.minDuration else { return }
        for ti in tracks.indices where !tracks[ti].locked {
            if let trackIDs, !trackIDs.isEmpty, !trackIDs.contains(tracks[ti].id) { continue }
            // Split any clip crossing range.lowerBound or range.upperBound
            for c in tracks[ti].clips where range.lowerBound > c.offset + AudioClip.minDuration && range.lowerBound < c.end - AudioClip.minDuration {
                _ = splitClip(id: c.id, at: range.lowerBound)
            }
            for c in tracks[ti].clips where range.upperBound > c.offset + AudioClip.minDuration && range.upperBound < c.end - AudioClip.minDuration {
                _ = splitClip(id: c.id, at: range.upperBound)
            }
            // Remove clips wholly inside range
            tracks[ti].clips.removeAll { c in
                c.offset >= range.lowerBound - 1e-5 && c.end <= range.upperBound + 1e-5
            }
            // Trim any clip still slightly overlapping due to minDuration edge cases
            for ci in tracks[ti].clips.indices {
                let c = tracks[ti].clips[ci]
                if c.offset < range.lowerBound, c.end > range.lowerBound, c.end <= range.upperBound {
                    trimClipEnd(id: c.id, to: range.lowerBound)
                } else if c.offset >= range.lowerBound, c.offset < range.upperBound, c.end > range.upperBound {
                    trimClipStart(id: c.id, to: range.upperBound)
                }
            }
            if ripple {
                for ci in tracks[ti].clips.indices where tracks[ti].clips[ci].offset >= range.upperBound - 1e-5 {
                    tracks[ti].clips[ci].offset = max(range.lowerBound, tracks[ti].clips[ci].offset - span)
                }
            }
            sortClips(inTrackAt: ti)
        }
    }

    /// Crops (`Rogner`) to `range`: keeps only the audio inside `range` and shifts it to `t = 0`.
    public mutating func cropToRange(_ range: ClosedRange<Double>, trackIDs: Set<UUID>? = nil) {
        guard range.upperBound > range.lowerBound + AudioClip.minDuration else { return }
        let slices = extractSlices(in: range, trackIDs: trackIDs)
        for ti in tracks.indices where !tracks[ti].locked {
            if let trackIDs, !trackIDs.isEmpty, !trackIDs.contains(tracks[ti].id) { continue }
            tracks[ti].clips.removeAll()
        }
        for s in slices where tracks.indices.contains(s.trackIndex) && !tracks[s.trackIndex].locked {
            var c = s.clip
            c.offset = max(0, s.relativeOffset)
            tracks[s.trackIndex].clips.append(c)
        }
        for ti in tracks.indices { sortClips(inTrackAt: ti) }
        // Shift markers inside range
        markers = markers.compactMap { m in
            guard m.time >= range.lowerBound && m.time <= range.upperBound else { return nil }
            var shifted = m
            shifted.time = m.time - range.lowerBound
            return shifted
        }
        if let loop = loopRange {
            let lo = max(0, loop.lowerBound - range.lowerBound)
            let hi = min(range.upperBound - range.lowerBound, loop.upperBound - range.lowerBound)
            loopRange = hi > lo + 1e-4 ? lo...hi : nil
        }
    }

    /// Silences (`Muet`) the audio inside `range` by splitting at its boundaries and muting the interior clips.
    public mutating func silenceRange(_ range: ClosedRange<Double>, trackIDs: Set<UUID>? = nil) {
        guard range.upperBound > range.lowerBound + AudioClip.minDuration else { return }
        for ti in tracks.indices where !tracks[ti].locked {
            if let trackIDs, !trackIDs.isEmpty, !trackIDs.contains(tracks[ti].id) { continue }
            for c in tracks[ti].clips where range.lowerBound > c.offset + AudioClip.minDuration && range.lowerBound < c.end - AudioClip.minDuration {
                _ = splitClip(id: c.id, at: range.lowerBound)
            }
            for c in tracks[ti].clips where range.upperBound > c.offset + AudioClip.minDuration && range.upperBound < c.end - AudioClip.minDuration {
                _ = splitClip(id: c.id, at: range.upperBound)
            }
            for ci in tracks[ti].clips.indices {
                let c = tracks[ti].clips[ci]
                if c.offset >= range.lowerBound - 1e-5 && c.end <= range.upperBound + 1e-5 {
                    tracks[ti].clips[ci].mute = true
                }
            }
        }
    }

    /// Applies a fade-in across `range`: if `range` starts near a clip's start (or inside it, splitting first),
    /// sets `fadeIn` so it reaches full volume at `range.upperBound`.
    public mutating func fadeInRange(_ range: ClosedRange<Double>, shape: FadeShape? = nil, trackIDs: Set<UUID>? = nil) {
        guard range.upperBound > range.lowerBound + AudioClip.minDuration else { return }
        for ti in tracks.indices where !tracks[ti].locked {
            if let trackIDs, !trackIDs.isEmpty, !trackIDs.contains(tracks[ti].id) { continue }
            // If range.lowerBound is strictly inside a clip (more than 20ms after clip start), split there first
            for c in tracks[ti].clips where range.lowerBound > c.offset + 0.02 && range.lowerBound < c.end - AudioClip.minDuration {
                _ = splitClip(id: c.id, at: range.lowerBound, crossfadeProtection: 0)
            }
            for ci in tracks[ti].clips.indices {
                var c = tracks[ti].clips[ci]
                guard c.offset <= range.upperBound, c.end > range.lowerBound else { continue }
                if abs(c.offset - range.lowerBound) <= 0.05 || (c.offset >= range.lowerBound && c.offset < range.upperBound) {
                    c.fadeIn = min(max(AudioClip.minDuration, range.upperBound - c.offset), c.duration)
                    if let shape { c.fadeShape = shape }
                    c.clampFades()
                    tracks[ti].clips[ci] = c
                }
            }
        }
    }

    /// Applies a fade-out across `range`: if `range` ends near a clip's end (or inside it, splitting first),
    /// sets `fadeOut` so it starts attenuating at `range.lowerBound`.
    public mutating func fadeOutRange(_ range: ClosedRange<Double>, shape: FadeShape? = nil, trackIDs: Set<UUID>? = nil) {
        guard range.upperBound > range.lowerBound + AudioClip.minDuration else { return }
        for ti in tracks.indices where !tracks[ti].locked {
            if let trackIDs, !trackIDs.isEmpty, !trackIDs.contains(tracks[ti].id) { continue }
            for c in tracks[ti].clips where range.upperBound > c.offset + AudioClip.minDuration && range.upperBound < c.end - 0.02 {
                _ = splitClip(id: c.id, at: range.upperBound, crossfadeProtection: 0)
            }
            for ci in tracks[ti].clips.indices {
                var c = tracks[ti].clips[ci]
                guard c.offset < range.upperBound, c.end >= range.lowerBound else { continue }
                if abs(c.end - range.upperBound) <= 0.05 || (c.end <= range.upperBound && c.end > range.lowerBound) {
                    c.fadeOut = min(max(AudioClip.minDuration, c.end - range.lowerBound), c.duration)
                    if let shape { c.fadeShape = shape }
                    c.clampFades()
                    tracks[ti].clips[ci] = c
                }
            }
        }
    }

    /// Pastes `slices` at `time`. If `slices` all came from one track and `targetTrackID` is given, pastes onto
    /// `targetTrackID`; if `insertRipple == true`, splits at `time` and shifts subsequent clips right to make room.
    @discardableResult
    public mutating func paste(_ slices: [ClipboardSlice], at time: Double, targetTrackID: UUID? = nil, insertRipple: Bool = true) -> [UUID] {
        guard !slices.isEmpty else { return [] }
        if tracks.isEmpty { addTrack() }
        let baseTrackIndex = slices.map(\.trackIndex).min() ?? 0
        let targetBaseIndex = targetTrackID.flatMap(trackIndex(of:)) ?? baseTrackIndex
        var pastedIDs: [UUID] = []

        // Group slices by destination track
        var byTrack: [Int: [ClipboardSlice]] = [:]
        for s in slices {
            let dest = min(max(targetBaseIndex + (s.trackIndex - baseTrackIndex), 0), max(tracks.count - 1, 0))
            byTrack[dest, default: []].append(s)
        }

        for (ti, trackSlices) in byTrack where tracks.indices.contains(ti) && !tracks[ti].locked {
            let span = trackSlices.map { $0.relativeOffset + $0.clip.duration }.max() ?? 0
            if insertRipple, span > 0 {
                // Split any clip under `time` and shift clips after `time` right by `span`
                for c in tracks[ti].clips where time > c.offset + AudioClip.minDuration && time < c.end - AudioClip.minDuration {
                    _ = splitClip(id: c.id, at: time)
                }
                for ci in tracks[ti].clips.indices where tracks[ti].clips[ci].offset >= time - 1e-6 {
                    tracks[ti].clips[ci].offset += span
                }
            }
            for s in trackSlices {
                var c = s.clip
                c.id = UUID()
                c.offset = max(0, time + s.relativeOffset)
                tracks[ti].clips.append(c)
                pastedIDs.append(c.id)
            }
            sortClips(inTrackAt: ti)
        }
        return pastedIDs
    }

    // MARK: Markers

    @discardableResult
    public mutating func addMarker(name: String? = nil, at time: Double, colorIndex: Int? = nil) -> UUID {
        let markerName = name ?? "M\(markers.count + 1)"
        let marker = AudioMarker(name: markerName, time: max(0, time), colorIndex: colorIndex ?? markers.count)
        markers.append(marker)
        return marker.id
    }

    public mutating func removeMarker(_ id: UUID) {
        markers.removeAll { $0.id == id }
    }

    public mutating func setMarker(_ id: UUID, name: String? = nil, time: Double? = nil, colorIndex: Int? = nil) {
        guard let i = markers.firstIndex(where: { $0.id == id }) else { return }
        if let name { markers[i].name = name }
        if let time { markers[i].time = max(0, time) }
        if let colorIndex { markers[i].colorIndex = max(0, colorIndex) }
    }

    // MARK: Internal

    public mutating func sortClips(inTrackAt ti: Int) {
        guard tracks.indices.contains(ti) else { return }
        tracks[ti].clips.sort { a, b in
            if abs(a.offset - b.offset) > 1e-7 { return a.offset < b.offset }
            return a.id.uuidString < b.id.uuidString
        }
    }
}

public enum EditError: Error, Equatable, Sendable {
    case trackNotFound
    case clipNotFound
    case markerNotFound
    case invalidSplitPoint
    case emptyRange
    case invalidArg(String)
}

public enum Operations {
    @discardableResult
    public static func addTrack(_ proj: inout AudioProject, name: String? = nil, at index: Int? = nil) -> AudioTrack {
        let id = proj.addTrack(name: name, at: index)
        let idx = proj.trackIndex(of: id) ?? 0
        return proj.tracks[idx]
    }

    public static func removeTrack(_ proj: inout AudioProject, id: UUID) throws {
        guard proj.trackIndex(of: id) != nil else { throw EditError.trackNotFound }
        proj.removeTrack(id)
    }

    @discardableResult
    public static func duplicateTrack(_ proj: inout AudioProject, id: UUID) throws -> AudioTrack {
        guard let newID = proj.duplicateTrack(id), let idx = proj.trackIndex(of: newID) else {
            throw EditError.trackNotFound
        }
        return proj.tracks[idx]
    }

    public static func renameTrack(_ proj: inout AudioProject, id: UUID, name: String) throws {
        guard proj.trackIndex(of: id) != nil else { throw EditError.trackNotFound }
        proj.setTrack(id, name: name)
    }

    public static func setTrackGain(_ proj: inout AudioProject, id: UUID, gainDB: Double) throws {
        guard proj.trackIndex(of: id) != nil else { throw EditError.trackNotFound }
        proj.setTrack(id, gainDB: gainDB)
    }

    public static func setTrackPan(_ proj: inout AudioProject, id: UUID, pan: Double) throws {
        guard proj.trackIndex(of: id) != nil else { throw EditError.trackNotFound }
        proj.setTrack(id, pan: pan)
    }

    public static func setTrackMute(_ proj: inout AudioProject, id: UUID, mute: Bool) throws {
        guard proj.trackIndex(of: id) != nil else { throw EditError.trackNotFound }
        proj.setTrack(id, mute: mute)
    }

    public static func setTrackSolo(_ proj: inout AudioProject, id: UUID, solo: Bool) throws {
        guard proj.trackIndex(of: id) != nil else { throw EditError.trackNotFound }
        proj.setTrack(id, solo: solo)
    }

    public static func setTrackColor(_ proj: inout AudioProject, id: UUID, colorIndex: Int) throws {
        guard proj.trackIndex(of: id) != nil else { throw EditError.trackNotFound }
        proj.setTrack(id, colorIndex: colorIndex)
    }

    public static func addClip(_ proj: inout AudioProject, toTrack trackID: UUID, clip: AudioClip) throws {
        guard proj.trackIndex(of: trackID) != nil else { throw EditError.trackNotFound }
        proj.addClip(clip, toTrack: trackID)
    }

    public static func renameClip(_ proj: inout AudioProject, id: UUID, name: String) throws {
        guard proj.clipLocation(of: id) != nil else { throw EditError.clipNotFound }
        proj.setClipName(id: id, name)
    }

    public static func moveClip(_ proj: inout AudioProject, id: UUID, toTrack trackID: UUID, offset: Double) throws {
        guard proj.clipLocation(of: id) != nil else { throw EditError.clipNotFound }
        proj.moveClip(id: id, toOffset: offset, toTrack: trackID)
    }

    public static func slipClip(_ proj: inout AudioProject, id: UUID, toSourceStart sourceStart: Double) throws {
        guard let (ti, ci) = proj.clipLocation(of: id) else { throw EditError.clipNotFound }
        let delta = sourceStart - proj.tracks[ti].clips[ci].sourceStart
        proj.slipClip(id: id, by: delta)
    }

    public static func trimClip(
        _ proj: inout AudioProject,
        id: UUID,
        offset: Double,
        sourceStart: Double,
        duration: Double
    ) throws {
        guard proj.clipLocation(of: id) != nil else { throw EditError.clipNotFound }
        proj.setClipTiming(id: id, offset: offset, sourceStart: sourceStart, duration: duration)
    }

    @discardableResult
    public static func splitClip(_ proj: inout AudioProject, id: UUID, at time: Double) throws -> (UUID, UUID) {
        guard let pair = proj.splitClip(id: id, at: time, crossfadeProtection: 0) else {
            throw EditError.invalidSplitPoint
        }
        return pair
    }

    @discardableResult
    public static func splitAtTime(_ proj: inout AudioProject, time: Double) throws -> [(UUID, UUID)] {
        var pairs: [(UUID, UUID)] = []
        for ti in proj.tracks.indices where !proj.tracks[ti].locked {
            for c in proj.tracks[ti].clips where time > c.offset + AudioClip.minDuration && time < c.end - AudioClip.minDuration {
                if let pair = proj.splitClip(id: c.id, at: time, crossfadeProtection: 0) {
                    pairs.append(pair)
                }
            }
        }
        return pairs
    }

    public static func removeClips(_ proj: inout AudioProject, ids: Set<UUID>, ripple: Bool = false) throws {
        proj.removeClips(ids, ripple: ripple)
    }

    @discardableResult
    public static func duplicateClips(_ proj: inout AudioProject, ids: [UUID]) throws -> [UUID] {
        proj.duplicateClips(Set(ids))
    }

    public static func setFade(
        _ proj: inout AudioProject,
        id: UUID,
        fadeIn: Double? = nil,
        fadeOut: Double? = nil,
        shape: FadeShape? = nil
    ) throws {
        guard proj.clipLocation(of: id) != nil else { throw EditError.clipNotFound }
        proj.setClipFades(id: id, fadeIn: fadeIn, fadeOut: fadeOut, shape: shape)
    }

    public static func setClipGain(_ proj: inout AudioProject, id: UUID, gainDB: Double) throws {
        guard proj.clipLocation(of: id) != nil else { throw EditError.clipNotFound }
        proj.setClipGain(id: id, db: gainDB)
    }

    public static func setClipPan(_ proj: inout AudioProject, id: UUID, pan: Double) throws {
        guard let (ti, ci) = proj.clipLocation(of: id), !proj.tracks[ti].locked else { throw EditError.clipNotFound }
        proj.tracks[ti].clips[ci].pan = min(max(pan, -1), 1)
    }

    public static func setClipReversed(_ proj: inout AudioProject, id: UUID, reversed: Bool) throws {
        guard proj.clipLocation(of: id) != nil else { throw EditError.clipNotFound }
        proj.setClipReversed(id: id, reversed)
    }

    public static func setClipMute(_ proj: inout AudioProject, id: UUID, mute: Bool) throws {
        guard proj.clipLocation(of: id) != nil else { throw EditError.clipNotFound }
        proj.setClipMute(id: id, mute)
    }

    public static func crossfade(_ proj: inout AudioProject, clipA: UUID, clipB: UUID, duration: Double = 0.25) throws {
        proj.crossfade(clipA: clipA, clipB: clipB, duration: duration)
    }

    public static func extractSlices(from proj: AudioProject, in range: ClosedRange<Double>, trackIDs: Set<UUID>? = nil) -> [ClipboardSlice] {
        proj.extractSlices(in: range, trackIDs: trackIDs)
    }

    public static func deleteRange(_ proj: inout AudioProject, in range: ClosedRange<Double>, ripple: Bool = false) throws {
        proj.deleteRange(range, ripple: ripple)
    }

    public static func cropToRange(_ proj: inout AudioProject, in range: ClosedRange<Double>) throws {
        proj.cropToRange(range)
    }

    public static func silenceRange(_ proj: inout AudioProject, in range: ClosedRange<Double>) throws {
        proj.silenceRange(range)
    }

    public static func fadeInRange(_ proj: inout AudioProject, in range: ClosedRange<Double>, shape: FadeShape? = nil) throws {
        proj.fadeInRange(range, shape: shape)
    }

    public static func fadeOutRange(_ proj: inout AudioProject, in range: ClosedRange<Double>, shape: FadeShape? = nil) throws {
        proj.fadeOutRange(range, shape: shape)
    }

    @discardableResult
    public static func paste(
        _ proj: inout AudioProject,
        slices: [ClipboardSlice],
        at time: Double,
        targetTrackID: UUID? = nil,
        ripple: Bool = false
    ) throws -> [UUID] {
        proj.paste(slices, at: time, targetTrackID: targetTrackID, insertRipple: ripple)
    }

    @discardableResult
    public static func addMarker(_ proj: inout AudioProject, time: Double, name: String? = nil, colorIndex: Int? = nil) -> AudioMarker {
        let id = proj.addMarker(name: name, at: time, colorIndex: colorIndex)
        return proj.markers.first { $0.id == id } ?? AudioMarker(id: id, name: name ?? "M", time: time)
    }

    public static func moveMarker(_ proj: inout AudioProject, id: UUID, to time: Double) throws {
        guard proj.markers.contains(where: { $0.id == id }) else { throw EditError.markerNotFound }
        proj.setMarker(id, time: time)
    }

    public static func removeMarker(_ proj: inout AudioProject, id: UUID) throws {
        guard proj.markers.contains(where: { $0.id == id }) else { throw EditError.markerNotFound }
        proj.removeMarker(id)
    }
}
