import Foundation

extension AudioProject {
    // MARK: Track operations

    @discardableResult
    public mutating func addTrack(
        name: String? = nil,
        kind: TrackKind = .audio,
        program: Int = 0,
        channel: Int? = nil,
        isDrum: Bool = false,
        at index: Int? = nil
    ) -> UUID {
        let idx = index.map { min(max($0, 0), tracks.count) } ?? tracks.count
        let usedChannels = Set(tracks.filter(\.isMIDI).map(\.channel))
        let resolvedChannel: Int
        if isDrum {
            resolvedChannel = 9
        } else if let ch = channel {
            resolvedChannel = min(max(ch, 0), 15)
        } else if kind == .midi {
            resolvedChannel = (0..<16).first { $0 != 9 && !usedChannels.contains($0) } ?? (tracks.count % 16)
        } else {
            resolvedChannel = 0
        }
        let defaultName: String
        if let n = name?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            defaultName = n
        } else if kind == .midi {
            defaultName = isDrum ? "Batterie GM" : GeneralMIDI.programName(program)
        } else {
            defaultName = "Piste \(tracks.count + 1)"
        }
        let track = AudioTrack(
            name: defaultName,
            colorIndex: tracks.count % 8,
            height: kind == .midi ? 94 : 88,
            kind: kind,
            channel: resolvedChannel,
            program: min(max(program, 0), 127),
            isDrum: isDrum || resolvedChannel == 9
        )
        tracks.insert(track, at: idx)
        return track.id
    }

    @discardableResult
    public mutating func addMIDITrack(
        name: String? = nil,
        program: Int = 0,
        channel: Int? = nil,
        isDrum: Bool = false,
        at index: Int? = nil
    ) -> UUID {
        addTrack(name: name, kind: .midi, program: program, channel: channel, isDrum: isDrum, at: index)
    }

    public mutating func removeTrack(_ id: UUID) {
        guard let i = trackIndex(of: id), !tracks[i].locked else { return }
        tracks.remove(at: i)
    }

    /// Moves track `id` to `destination` (0-based index, clamped to valid track bounds).
    public mutating func moveTrack(_ id: UUID, to destination: Int) {
        guard let from = trackIndex(of: id) else { return }
        let track = tracks.remove(at: from)
        let clamped = min(max(destination, 0), tracks.count)
        tracks.insert(track, at: clamped)
    }

    /// Shifts track `id` up (`delta < 0`) or down (`delta > 0`) in the track list.
    public mutating func moveTrack(_ id: UUID, by delta: Int) {
        guard let from = trackIndex(of: id) else { return }
        let target = min(max(from + delta, 0), max(0, tracks.count - 1))
        guard target != from else { return }
        moveTrack(id, to: target)
    }

    @discardableResult
    public mutating func duplicateTrack(_ id: UUID) -> UUID? {
        guard let i = trackIndex(of: id) else { return nil }
        var copy = tracks[i]
        copy.id = UUID()
        copy.name = copy.name + " (copie)"
        copy.colorIndex = (copy.colorIndex + 1) % 8
        copy.locked = false
        copy.clips = copy.clips.map { c in
            var cc = c
            cc.id = UUID()
            return cc
        }
        copy.notes = copy.notes.map { n in
            var nc = n
            nc.id = UUID()
            return nc
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
        colorIndex: Int? = nil,
        program: Int? = nil,
        channel: Int? = nil,
        isDrum: Bool? = nil,
        transpose: Int? = nil,
        pianoRollExpanded: Bool? = nil
    ) {
        guard let i = trackIndex(of: id) else { return }
        if let name, !name.isEmpty { tracks[i].name = name }
        if let gainDB { tracks[i].gainDB = min(max(gainDB, -60), 24) }
        if let pan { tracks[i].pan = min(max(pan, -1), 1) }
        if let mute { tracks[i].mute = mute }
        if let solo { tracks[i].solo = solo }
        if let locked { tracks[i].locked = locked }
        if let stereoSplit { tracks[i].stereoSplit = stereoSplit }
        if let height { tracks[i].height = min(max(height, 48), 340) }
        if let colorIndex { tracks[i].colorIndex = ((colorIndex % 8) + 8) % 8 }
        if let program { tracks[i].program = min(max(program, 0), 127) }
        if let channel {
            let ch = min(max(channel, 0), 15)
            tracks[i].channel = ch
            tracks[i].isDrum = (ch == 9)
            for ni in tracks[i].notes.indices {
                tracks[i].notes[ni].channel = ch
            }
        }
        if let isDrum {
            tracks[i].isDrum = isDrum
            if isDrum {
                tracks[i].channel = 9
            } else if tracks[i].channel == 9 {
                tracks[i].channel = i % 8
            }
        }
        if let transpose { tracks[i].transpose = min(max(transpose, -36), 36) }
        if let pianoRollExpanded {
            tracks[i].pianoRollExpanded = pianoRollExpanded
            tracks[i].height = pianoRollExpanded ? 236 : 94
        }
    }

    public mutating func setTrackProgram(_ id: UUID, program: Int, isDrum: Bool? = nil) {
        setTrack(id, program: program, isDrum: isDrum)
    }

    public mutating func setTrackChannel(_ id: UUID, channel: Int, isDrum: Bool? = nil) {
        setTrack(id, channel: channel, isDrum: isDrum)
    }

    public mutating func setTrackTranspose(_ id: UUID, semitones: Int) {
        setTrack(id, transpose: semitones)
    }

    public mutating func setTrackPianoRollExpanded(_ id: UUID, _ expanded: Bool) {
        setTrack(id, pianoRollExpanded: expanded)
    }

    // MARK: Clip operations

    @discardableResult
    public mutating func addClip(_ clip: AudioClip, toTrack trackID: UUID? = nil) -> UUID {
        let ti: Int
        if let trackID, let idx = trackIndex(of: trackID) {
            ti = idx
        } else if let firstAudioIdx = tracks.firstIndex(where: { !$0.isMIDI }) {
            ti = firstAudioIdx
        } else {
            let newID = addTrack(kind: .audio)
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
        if let targetTrackID, let destTI = trackIndex(of: targetTrackID), destTI != ti, !tracks[destTI].isMIDI {
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

    // MARK: MIDI Note operations

    @discardableResult
    public mutating func addNote(_ note: MIDINote, toTrack trackID: UUID? = nil) -> UUID {
        let ti: Int
        if let trackID, let idx = trackIndex(of: trackID) {
            ti = idx
        } else if let firstMIDIIdx = tracks.firstIndex(where: \.isMIDI) {
            ti = firstMIDIIdx
        } else {
            let newID = addMIDITrack()
            ti = trackIndex(of: newID) ?? 0
        }
        guard !tracks[ti].locked else { return note.id }
        tracks[ti].kind = .midi
        var n = note
        n.channel = tracks[ti].channel
        tracks[ti].notes.append(n)
        tracks[ti].sortNotes()
        return n.id
    }

    @discardableResult
    public mutating func addNote(
        toTrack trackID: UUID,
        pitch: Int,
        start: Double,
        duration: Double,
        velocity: Int = 100
    ) -> UUID? {
        guard let ti = trackIndex(of: trackID), !tracks[ti].locked else { return nil }
        tracks[ti].kind = .midi
        let note = MIDINote(
            pitch: pitch,
            start: max(0, start),
            duration: max(MIDINote.minDuration, duration),
            velocity: velocity,
            channel: tracks[ti].channel
        )
        tracks[ti].notes.append(note)
        tracks[ti].sortNotes()
        return note.id
    }

    public mutating func moveNote(
        id: UUID,
        toTrack targetTrackID: UUID? = nil,
        start: Double,
        pitch: Int? = nil
    ) {
        guard let (ti, ni) = noteLocation(of: id), !tracks[ti].locked else { return }
        var note = tracks[ti].notes[ni]
        note.start = max(0, start)
        if let pitch {
            note.pitch = min(max(pitch, 0), 127)
        }
        if let targetTrackID, targetTrackID != tracks[ti].id,
           let destIndex = trackIndex(of: targetTrackID),
           tracks[destIndex].isMIDI,
           !tracks[destIndex].locked {
            tracks[ti].notes.remove(at: ni)
            note.channel = tracks[destIndex].channel
            tracks[destIndex].notes.append(note)
            tracks[destIndex].sortNotes()
        } else {
            tracks[ti].notes[ni] = note
            tracks[ti].sortNotes()
        }
    }

    public mutating func moveNote(
        _ id: UUID,
        toTrack targetTrackID: UUID? = nil,
        toStart start: Double,
        pitch: Int? = nil
    ) {
        moveNote(id: id, toTrack: targetTrackID, start: start, pitch: pitch)
    }

    public mutating func trimNote(id: UUID, start: Double, duration: Double) {
        guard let (ti, ni) = noteLocation(of: id), !tracks[ti].locked else { return }
        tracks[ti].notes[ni].start = max(0, start)
        tracks[ti].notes[ni].duration = max(MIDINote.minDuration, duration)
        tracks[ti].sortNotes()
    }

    public mutating func trimNote(_ id: UUID, start: Double, duration: Double) {
        trimNote(id: id, start: start, duration: duration)
    }

    public mutating func setNoteVelocity(id: UUID, velocity: Int) {
        guard let (ti, ni) = noteLocation(of: id), !tracks[ti].locked else { return }
        tracks[ti].notes[ni].velocity = min(max(velocity, 1), 127)
    }

    public mutating func setNoteVelocity(_ id: UUID, velocity: Int) {
        setNoteVelocity(id: id, velocity: velocity)
    }

    public mutating func setNotePitch(id: UUID, pitch: Int) {
        guard let (ti, ni) = noteLocation(of: id), !tracks[ti].locked else { return }
        tracks[ti].notes[ni].pitch = min(max(pitch, 0), 127)
        tracks[ti].sortNotes()
    }

    public mutating func setNotePitch(_ id: UUID, pitch: Int) {
        setNotePitch(id: id, pitch: pitch)
    }

    public mutating func setNoteMute(id: UUID, _ mute: Bool) {
        guard let (ti, ni) = noteLocation(of: id), !tracks[ti].locked else { return }
        tracks[ti].notes[ni].mute = mute
    }

    public mutating func setNoteMute(_ id: UUID, _ mute: Bool) {
        setNoteMute(id: id, mute)
    }

    @discardableResult
    public mutating func splitNotes(at time: Double, noteIDs: Set<UUID>? = nil, trackIDs: Set<UUID>? = nil) -> [UUID] {
        var created: [UUID] = []
        let eps = MIDINote.minDuration
        for ti in tracks.indices where !tracks[ti].locked {
            if let trackIDs, !trackIDs.isEmpty, !trackIDs.contains(tracks[ti].id) { continue }
            var nextNotes: [MIDINote] = []
            for note in tracks[ti].notes {
                let eligible = noteIDs?.contains(note.id) ?? true
                if eligible && time > note.start + eps && time < note.end - eps {
                    var left = note
                    left.duration = time - note.start
                    var right = note
                    right.id = UUID()
                    right.start = time
                    right.duration = note.end - time
                    nextNotes.append(left)
                    nextNotes.append(right)
                    created.append(right.id)
                } else {
                    nextNotes.append(note)
                }
            }
            tracks[ti].notes = nextNotes
            tracks[ti].sortNotes()
        }
        return created
    }

    @discardableResult
    public mutating func duplicateNotes(_ ids: Set<UUID>, offsetDelta: Double? = nil) -> [UUID] {
        guard !ids.isEmpty else { return [] }
        let selected = allNotes.filter { ids.contains($0.note.id) }
        guard let minStart = selected.map(\.note.start).min(),
              let maxEnd = selected.map(\.note.end).max() else { return [] }
        let span = offsetDelta ?? max(maxEnd - minStart, MIDINote.minDuration)
        var newIDs: [UUID] = []
        for (ti, _, note) in selected where !tracks[ti].locked {
            var copy = note
            copy.id = UUID()
            copy.start = note.start + span
            tracks[ti].notes.append(copy)
            newIDs.append(copy.id)
        }
        for ti in tracks.indices {
            tracks[ti].sortNotes()
        }
        return newIDs
    }

    public mutating func removeNotes(_ ids: Set<UUID>, ripple: Bool = false) {
        guard !ids.isEmpty else { return }
        let selected = allNotes.filter { ids.contains($0.note.id) }
        let minStart = selected.map(\.note.start).min() ?? 0
        let maxEnd = selected.map(\.note.end).max() ?? minStart
        let span = max(0, maxEnd - minStart)
        let affectedTracks = Set(selected.map(\.trackID))

        for ti in tracks.indices where !tracks[ti].locked {
            tracks[ti].notes.removeAll { ids.contains($0.id) }
            if ripple && span > 0 && affectedTracks.contains(tracks[ti].id) {
                for ni in tracks[ti].notes.indices {
                    if tracks[ti].notes[ni].start >= maxEnd - 1e-6 {
                        tracks[ti].notes[ni].start = max(0, tracks[ti].notes[ni].start - span)
                    }
                }
            }
            tracks[ti].sortNotes()
        }
    }

    public mutating func transposeNotes(_ ids: Set<UUID>, semitones: Int) {
        guard semitones != 0, !ids.isEmpty else { return }
        for ti in tracks.indices where !tracks[ti].locked {
            for ni in tracks[ti].notes.indices where ids.contains(tracks[ti].notes[ni].id) {
                let p = tracks[ti].notes[ni].pitch + semitones
                tracks[ti].notes[ni].pitch = min(max(p, 0), 127)
            }
            tracks[ti].sortNotes()
        }
    }

    public mutating func quantizeNotes(
        _ ids: Set<UUID>? = nil,
        range: ClosedRange<Double>? = nil,
        subdivisionBeats: Double = 0.25,
        quantizeDuration: Bool = false,
        trackIDs: Set<UUID>? = nil
    ) {
        let gridSeconds = max(0.01, secondsPerBeat * max(0.0625, subdivisionBeats))
        for ti in tracks.indices where !tracks[ti].locked {
            if let trackIDs, !trackIDs.isEmpty, !trackIDs.contains(tracks[ti].id) { continue }
            for ni in tracks[ti].notes.indices {
                let n = tracks[ti].notes[ni]
                let matchID = ids?.contains(n.id) ?? false
                let matchRange = range.map { n.start >= $0.lowerBound - 1e-5 && n.start <= $0.upperBound + 1e-5 } ?? false
                let matchAll = (ids == nil && range == nil)
                guard matchID || matchRange || matchAll else { continue }

                let qStart = (n.start / gridSeconds).rounded() * gridSeconds
                tracks[ti].notes[ni].start = max(0, qStart)
                if quantizeDuration {
                    let qDur = max(gridSeconds, (n.duration / gridSeconds).rounded() * gridSeconds)
                    tracks[ti].notes[ni].duration = qDur
                }
            }
            tracks[ti].sortNotes()
        }
    }

    public mutating func quantizeNotes(
        ids: Set<UUID>?,
        range: ClosedRange<Double>? = nil,
        subdivisionBeats: Double = 0.25,
        quantizeDuration: Bool = false,
        trackIDs: Set<UUID>? = nil
    ) {
        quantizeNotes(ids, range: range, subdivisionBeats: subdivisionBeats, quantizeDuration: quantizeDuration, trackIDs: trackIDs)
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

    /// Extracts MIDI note slices overlapping `range` on `trackIDs` (nil = all tracks).
    public func extractNoteSlices(in range: ClosedRange<Double>, trackIDs: Set<UUID>? = nil) -> [NoteClipboardSlice] {
        guard range.upperBound > range.lowerBound + 1e-5 else { return [] }
        let eligibleTracks = tracks.enumerated().filter { _, t in
            trackIDs == nil || trackIDs!.isEmpty || trackIDs!.contains(t.id)
        }
        guard let baseTrackIdx = eligibleTracks.first?.offset else { return [] }
        var slices: [NoteClipboardSlice] = []

        for (ti, track) in eligibleTracks {
            for note in track.notes {
                guard note.end > range.lowerBound + 1e-5, note.start < range.upperBound - 1e-5 else { continue }
                let clippedStart = max(note.start, range.lowerBound)
                let clippedEnd = min(note.end, range.upperBound)
                guard clippedEnd - clippedStart >= MIDINote.minDuration else { continue }
                var sliced = note
                sliced.id = UUID()
                sliced.start = clippedStart
                sliced.duration = clippedEnd - clippedStart
                slices.append(
                    NoteClipboardSlice(
                        trackOffset: ti - baseTrackIdx,
                        relativeStart: clippedStart - range.lowerBound,
                        note: sliced
                    )
                )
            }
        }
        return slices
    }

    public func extractNotes(_ ids: Set<UUID>) -> [NoteClipboardSlice] {
        let matched = allNotes.filter { ids.contains($0.note.id) }
        guard let minTrack = matched.map(\.trackIndex).min(),
              let minStart = matched.map(\.note.start).min() else { return [] }
        return matched.map { ti, _, note in
            var copy = note
            copy.id = UUID()
            return NoteClipboardSlice(
                trackOffset: ti - minTrack,
                relativeStart: note.start - minStart,
                note: copy
            )
        }
    }

    @discardableResult
    public mutating func pasteNotes(
        _ slices: [NoteClipboardSlice],
        at time: Double,
        targetTrackID: UUID? = nil,
        insertRipple: Bool = false
    ) -> [UUID] {
        guard !slices.isEmpty else { return [] }
        let baseTrackIndex: Int
        if let targetTrackID, let idx = trackIndex(of: targetTrackID) {
            baseTrackIndex = idx
        } else if let firstMIDI = tracks.firstIndex(where: \.isMIDI) {
            baseTrackIndex = firstMIDI
        } else {
            let newID = addMIDITrack()
            baseTrackIndex = trackIndex(of: newID) ?? 0
        }

        let span = slices.map { $0.relativeStart + $0.note.duration }.max() ?? 0
        if insertRipple && span > 0 {
            let touchedOffsets = Set(slices.map(\.trackOffset))
            for offset in touchedOffsets {
                let ti = min(max(0, baseTrackIndex + offset), tracks.count - 1)
                guard !tracks[ti].locked else { continue }
                for ni in tracks[ti].notes.indices where tracks[ti].notes[ni].start >= time - 1e-6 {
                    tracks[ti].notes[ni].start += span
                }
            }
        }

        var pastedIDs: [UUID] = []
        for slice in slices {
            let ti = min(max(0, baseTrackIndex + slice.trackOffset), tracks.count - 1)
            guard !tracks[ti].locked else { continue }
            var newNote = slice.note
            newNote.id = UUID()
            newNote.start = max(0, time + slice.relativeStart)
            newNote.channel = tracks[ti].channel
            tracks[ti].notes.append(newNote)
            pastedIDs.append(newNote.id)
        }
        for ti in tracks.indices {
            tracks[ti].sortNotes()
        }
        return pastedIDs
    }

    /// Deletes the audio clips and MIDI notes inside `range` on `trackIDs` (nil = all unlocked tracks).
    /// When `ripple == true`, events starting at or after `range.upperBound` shift left by `range`'s length.
    public mutating func deleteRange(_ range: ClosedRange<Double>, trackIDs: Set<UUID>? = nil, ripple: Bool = false) {
        let a = range.lowerBound
        let b = range.upperBound
        let span = b - a
        guard span >= AudioClip.minDuration else { return }
        for ti in tracks.indices where !tracks[ti].locked {
            if let trackIDs, !trackIDs.isEmpty, !trackIDs.contains(tracks[ti].id) { continue }
            // 1. Audio clips
            for c in tracks[ti].clips where a > c.offset + AudioClip.minDuration && a < c.end - AudioClip.minDuration {
                _ = splitClip(id: c.id, at: a)
            }
            for c in tracks[ti].clips where b > c.offset + AudioClip.minDuration && b < c.end - AudioClip.minDuration {
                _ = splitClip(id: c.id, at: b)
            }
            tracks[ti].clips.removeAll { c in
                c.offset >= a - 1e-5 && c.end <= b + 1e-5
            }
            for ci in tracks[ti].clips.indices {
                let c = tracks[ti].clips[ci]
                if c.offset < a, c.end > a, c.end <= b {
                    trimClipEnd(id: c.id, to: a)
                } else if c.offset >= a, c.offset < b, c.end > b {
                    trimClipStart(id: c.id, to: b)
                }
            }
            if ripple {
                for ci in tracks[ti].clips.indices where tracks[ti].clips[ci].offset >= b - 1e-5 {
                    tracks[ti].clips[ci].offset = max(a, tracks[ti].clips[ci].offset - span)
                }
            }
            sortClips(inTrackAt: ti)

            // 2. MIDI notes
            if !tracks[ti].notes.isEmpty {
                var kept: [MIDINote] = []
                for note in tracks[ti].notes {
                    if note.end <= a + 1e-6 || note.start >= b - 1e-6 {
                        var updated = note
                        if ripple && updated.start >= b - 1e-6 {
                            updated.start = max(a, updated.start - span)
                        }
                        kept.append(updated)
                    } else {
                        if note.start < a - MIDINote.minDuration {
                            var left = note
                            left.duration = a - note.start
                            kept.append(left)
                        }
                        if note.end > b + MIDINote.minDuration {
                            var right = note
                            right.id = UUID()
                            right.start = ripple ? a : b
                            right.duration = note.end - b
                            kept.append(right)
                        }
                    }
                }
                tracks[ti].notes = kept
                tracks[ti].sortNotes()
            }
        }
    }

    /// Crops (`Rogner`) to `range`: keeps only the audio and MIDI notes inside `range` and shifts them to `t = 0`.
    public mutating func cropToRange(_ range: ClosedRange<Double>, trackIDs: Set<UUID>? = nil) {
        let a = range.lowerBound
        let b = range.upperBound
        guard b > a + AudioClip.minDuration else { return }
        let slices = extractSlices(in: range, trackIDs: trackIDs)
        for ti in tracks.indices where !tracks[ti].locked {
            if let trackIDs, !trackIDs.isEmpty, !trackIDs.contains(tracks[ti].id) { continue }
            tracks[ti].clips.removeAll()
            if !tracks[ti].notes.isEmpty {
                var croppedNotes: [MIDINote] = []
                for note in tracks[ti].notes {
                    guard note.end > a + 1e-5, note.start < b - 1e-5 else { continue }
                    let s = max(note.start, a)
                    let e = min(note.end, b)
                    guard e - s >= MIDINote.minDuration else { continue }
                    var c = note
                    c.start = s - a
                    c.duration = e - s
                    croppedNotes.append(c)
                }
                tracks[ti].notes = croppedNotes
                tracks[ti].sortNotes()
            }
        }
        for s in slices where tracks.indices.contains(s.trackIndex) && !tracks[s.trackIndex].locked {
            var c = s.clip
            c.offset = max(0, s.relativeOffset)
            tracks[s.trackIndex].clips.append(c)
        }
        for ti in tracks.indices { sortClips(inTrackAt: ti) }
        markers = markers.compactMap { m in
            guard m.time >= a && m.time <= b else { return nil }
            var shifted = m
            shifted.time = m.time - a
            return shifted
        }
        if let loop = loopRange {
            let lo = max(0, loop.lowerBound - a)
            let hi = min(b - a, loop.upperBound - a)
            loopRange = hi > lo + 1e-4 ? lo...hi : nil
        }
    }

    /// Silences (`Muet`) the audio and MIDI notes inside `range`.
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
            if !tracks[ti].notes.isEmpty {
                // For MIDI tracks, silencing a range removes/trims notes in that range without ripple
                var kept: [MIDINote] = []
                let a = range.lowerBound
                let b = range.upperBound
                for note in tracks[ti].notes {
                    if note.end <= a + 1e-6 || note.start >= b - 1e-6 {
                        kept.append(note)
                    } else {
                        if note.start < a - MIDINote.minDuration {
                            var left = note
                            left.duration = a - note.start
                            kept.append(left)
                        }
                        if note.end > b + MIDINote.minDuration {
                            var right = note
                            right.id = UUID()
                            right.start = b
                            right.duration = note.end - b
                            kept.append(right)
                        }
                    }
                }
                tracks[ti].notes = kept
                tracks[ti].sortNotes()
            }
        }
    }

    /// Applies a fade-in across `range`.
    public mutating func fadeInRange(_ range: ClosedRange<Double>, shape: FadeShape? = nil, trackIDs: Set<UUID>? = nil) {
        guard range.upperBound > range.lowerBound + AudioClip.minDuration else { return }
        for ti in tracks.indices where !tracks[ti].locked {
            if let trackIDs, !trackIDs.isEmpty, !trackIDs.contains(tracks[ti].id) { continue }
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

    /// Applies a fade-out across `range`.
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

    /// Pastes `slices` at `time`.
    @discardableResult
    public mutating func paste(_ slices: [ClipboardSlice], at time: Double, targetTrackID: UUID? = nil, insertRipple: Bool = true) -> [UUID] {
        guard !slices.isEmpty else { return [] }
        if tracks.isEmpty { addTrack() }
        let baseTrackIndex = slices.map(\.trackIndex).min() ?? 0
        let targetBaseIndex = targetTrackID.flatMap(trackIndex(of:)) ?? baseTrackIndex
        var pastedIDs: [UUID] = []

        var byTrack: [Int: [ClipboardSlice]] = [:]
        for s in slices {
            let dest = min(max(targetBaseIndex + (s.trackIndex - baseTrackIndex), 0), max(tracks.count - 1, 0))
            byTrack[dest, default: []].append(s)
        }

        for (ti, trackSlices) in byTrack where tracks.indices.contains(ti) && !tracks[ti].locked {
            let span = trackSlices.map { $0.relativeOffset + $0.clip.duration }.max() ?? 0
            if insertRipple, span > 0 {
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

    // MARK: Tempo & Time Signature

    public mutating func setTempo(_ newBPM: Double, scaleNoteTimes: Bool = true) {
        setTempo(bpm: newBPM, scaleNoteTimes: scaleNoteTimes)
    }

    public mutating func setTempo(bpm newBPM: Double, scaleNoteTimes: Bool = true) {
        let clamped = min(max(newBPM, 20.0), 300.0)
        let oldBPM = max(20.0, bpm)
        bpm = clamped
        guard scaleNoteTimes, abs(clamped - oldBPM) > 1e-6 else { return }
        let scale = oldBPM / clamped
        for ti in tracks.indices {
            for ni in tracks[ti].notes.indices {
                tracks[ti].notes[ni].start *= scale
                tracks[ti].notes[ni].duration = max(MIDINote.minDuration, tracks[ti].notes[ni].duration * scale)
            }
        }
    }

    public mutating func setTimeSignature(numerator: Int, denominator: Int) {
        timeSignatureNumerator = min(max(numerator, 1), 32)
        timeSignatureDenominator = [1, 2, 4, 8, 16].contains(denominator) ? denominator : 4
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
    case noteNotFound
    case markerNotFound
    case trackLocked
    case invalidSplitPoint
    case emptyRange
    case invalidArg(String)
}

public enum Operations {
    @discardableResult
    public static func addTrack(
        _ proj: inout AudioProject,
        name: String? = nil,
        kind: TrackKind = .audio,
        program: Int = 0,
        channel: Int? = nil,
        isDrum: Bool = false,
        at index: Int? = nil
    ) -> AudioTrack {
        let id = proj.addTrack(name: name, kind: kind, program: program, channel: channel, isDrum: isDrum, at: index)
        let idx = proj.trackIndex(of: id) ?? 0
        return proj.tracks[idx]
    }

    @discardableResult
    public static func addMIDITrack(
        _ proj: inout AudioProject,
        name: String? = nil,
        program: Int = 0,
        channel: Int? = nil,
        isDrum: Bool = false,
        at index: Int? = nil
    ) -> AudioTrack {
        addTrack(&proj, name: name, kind: .midi, program: program, channel: channel, isDrum: isDrum, at: index)
    }

    public static func removeTrack(_ proj: inout AudioProject, id: UUID) throws {
        guard proj.trackIndex(of: id) != nil else { throw EditError.trackNotFound }
        proj.removeTrack(id)
    }

    public static func moveTrack(_ proj: inout AudioProject, id: UUID, to destination: Int) throws {
        guard proj.trackIndex(of: id) != nil else { throw EditError.trackNotFound }
        proj.moveTrack(id, to: destination)
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

    public static func setTrackProgram(_ proj: inout AudioProject, id: UUID, program: Int, isDrum: Bool? = nil) throws {
        guard proj.trackIndex(of: id) != nil else { throw EditError.trackNotFound }
        proj.setTrack(id, program: program, isDrum: isDrum)
    }

    public static func setTrackChannel(_ proj: inout AudioProject, id: UUID, channel: Int) throws {
        guard proj.trackIndex(of: id) != nil else { throw EditError.trackNotFound }
        proj.setTrack(id, channel: channel)
    }

    public static func setTrackTranspose(_ proj: inout AudioProject, id: UUID, transpose: Int) throws {
        guard proj.trackIndex(of: id) != nil else { throw EditError.trackNotFound }
        proj.setTrack(id, transpose: transpose)
    }

    public static func setTrackPianoRollExpanded(_ proj: inout AudioProject, id: UUID, expanded: Bool) throws {
        guard proj.trackIndex(of: id) != nil else { throw EditError.trackNotFound }
        proj.setTrack(id, pianoRollExpanded: expanded)
    }

    // MARK: Clips

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

    // MARK: MIDI Notes

    @discardableResult
    public static func addNote(
        _ proj: inout AudioProject,
        toTrack trackID: UUID,
        pitch: Int,
        start: Double,
        duration: Double,
        velocity: Int = 100
    ) throws -> UUID {
        guard let ti = proj.trackIndex(of: trackID) else { throw EditError.trackNotFound }
        guard !proj.tracks[ti].locked else { throw EditError.trackLocked }
        guard let noteID = proj.addNote(toTrack: trackID, pitch: pitch, start: start, duration: duration, velocity: velocity) else {
            throw EditError.trackNotFound
        }
        return noteID
    }

    public static func moveNote(
        _ proj: inout AudioProject,
        id: UUID,
        toTrack targetTrackID: UUID? = nil,
        start: Double,
        pitch: Int? = nil
    ) throws {
        guard proj.noteLocation(of: id) != nil else { throw EditError.noteNotFound }
        proj.moveNote(id: id, toTrack: targetTrackID, start: start, pitch: pitch)
    }

    public static func trimNote(
        _ proj: inout AudioProject,
        id: UUID,
        start: Double,
        duration: Double
    ) throws {
        guard proj.noteLocation(of: id) != nil else { throw EditError.noteNotFound }
        proj.trimNote(id: id, start: start, duration: duration)
    }

    public static func setNoteVelocity(_ proj: inout AudioProject, id: UUID, velocity: Int) throws {
        guard proj.noteLocation(of: id) != nil else { throw EditError.noteNotFound }
        proj.setNoteVelocity(id: id, velocity: velocity)
    }

    public static func setNotePitch(_ proj: inout AudioProject, id: UUID, pitch: Int) throws {
        guard proj.noteLocation(of: id) != nil else { throw EditError.noteNotFound }
        proj.setNotePitch(id: id, pitch: pitch)
    }

    public static func setNoteMute(_ proj: inout AudioProject, id: UUID, mute: Bool) throws {
        guard proj.noteLocation(of: id) != nil else { throw EditError.noteNotFound }
        proj.setNoteMute(id: id, mute)
    }

    @discardableResult
    public static func splitNotes(
        _ proj: inout AudioProject,
        at time: Double,
        noteIDs: Set<UUID>? = nil,
        trackIDs: Set<UUID>? = nil
    ) -> [UUID] {
        proj.splitNotes(at: time, noteIDs: noteIDs, trackIDs: trackIDs)
    }

    @discardableResult
    public static func duplicateNotes(_ proj: inout AudioProject, ids: Set<UUID>) -> [UUID] {
        proj.duplicateNotes(ids)
    }

    public static func removeNotes(_ proj: inout AudioProject, ids: Set<UUID>, ripple: Bool = false) {
        proj.removeNotes(ids, ripple: ripple)
    }

    public static func transposeNotes(_ proj: inout AudioProject, ids: Set<UUID>, semitones: Int) {
        proj.transposeNotes(ids, semitones: semitones)
    }

    public static func quantizeNotes(
        _ proj: inout AudioProject,
        ids: Set<UUID>? = nil,
        range: ClosedRange<Double>? = nil,
        subdivisionBeats: Double = 0.25,
        quantizeDuration: Bool = false
    ) {
        proj.quantizeNotes(ids: ids, range: range, subdivisionBeats: subdivisionBeats, quantizeDuration: quantizeDuration)
    }

    public static func setTempo(_ proj: inout AudioProject, bpm: Double, scaleNoteTimes: Bool = true) {
        proj.setTempo(bpm: bpm, scaleNoteTimes: scaleNoteTimes)
    }

    public static func setTimeSignature(_ proj: inout AudioProject, numerator: Int, denominator: Int) {
        proj.setTimeSignature(numerator: numerator, denominator: denominator)
    }

    // MARK: Range Operations

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
