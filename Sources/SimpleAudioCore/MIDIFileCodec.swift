import Foundation

/// Pure-Swift Standard MIDI File (`.mid` / `.midi`) binary reader and writer (Format 0 & Format 1).
public enum MIDIFileCodec {
    public enum CodecError: Error, CustomStringConvertible {
        case invalidHeader
        case unexpectedEOF
        case unsupportedDivision

        public var description: String {
            switch self {
            case .invalidHeader: return "En-tête MIDI (MThd) invalide ou fichier corrompu."
            case .unexpectedEOF: return "Fin de fichier MIDI inattendue."
            case .unsupportedDivision: return "Division temporelle SMPTE non prise en charge."
            }
        }
    }

    private struct TempoChange {
        var tick: Int
        var microsecondsPerBeat: Int
    }

    private struct RawNoteEvent {
        var pitch: Int
        var velocity: Int
        var channel: Int
        var startTick: Int
        var endTick: Int
    }

    private struct RawTrackData {
        var name: String?
        var notes: [RawNoteEvent] = []
        var programByChannel: [Int: Int] = [:]
        var volumeByChannel: [Int: Int] = [:]
        var panByChannel: [Int: Int] = [:]
        var tempoChanges: [TempoChange] = []
        var timeSignature: (num: Int, den: Int)?
        var markers: [(tick: Int, text: String)] = []
    }

    // MARK: - Decode Standard MIDI File (.mid)

    public static func decode(_ data: Data, defaultTitle: String = "Morceau MIDI") throws -> AudioProject {
        let bytes = [UInt8](data)
        guard bytes.count >= 14 else { throw CodecError.invalidHeader }
        guard bytes[0] == 0x4D, bytes[1] == 0x54, bytes[2] == 0x68, bytes[3] == 0x64 else {
            throw CodecError.invalidHeader
        }

        let headerLen = Int(readUInt32(bytes, at: 4))
        guard headerLen >= 6, bytes.count >= 8 + headerLen else { throw CodecError.invalidHeader }

        let format = Int(readUInt16(bytes, at: 8))
        let numTracks = Int(readUInt16(bytes, at: 10))
        let divisionRaw = Int(readUInt16(bytes, at: 12))

        let ticksPerQuarter: Int
        if (divisionRaw & 0x8000) != 0 {
            ticksPerQuarter = 480
        } else {
            ticksPerQuarter = max(24, divisionRaw)
        }

        var cursor = 8 + headerLen
        var rawTracks: [RawTrackData] = []

        for _ in 0..<numTracks {
            guard cursor + 8 <= bytes.count else { break }
            let chunkID = String(decoding: bytes[cursor..<(cursor + 4)], as: UTF8.self)
            let chunkLen = Int(readUInt32(bytes, at: cursor + 4))
            cursor += 8
            guard cursor + chunkLen <= bytes.count else { break }
            if chunkID == "MTrk" {
                let slice = bytes[cursor..<(cursor + chunkLen)]
                let parsed = parseTrackChunk(slice)
                rawTracks.append(parsed)
            }
            cursor += chunkLen
        }

        // Gather global tempo map and time signature
        var allTempos: [TempoChange] = []
        var timeSig: (num: Int, den: Int) = (4, 4)
        var rawMarkers: [(tick: Int, text: String)] = []

        for rt in rawTracks {
            allTempos.append(contentsOf: rt.tempoChanges)
            if let ts = rt.timeSignature {
                timeSig = ts
            }
            rawMarkers.append(contentsOf: rt.markers)
        }
        allTempos.sort { $0.tick < $1.tick }
        if allTempos.isEmpty || allTempos[0].tick > 0 {
            allTempos.insert(TempoChange(tick: 0, microsecondsPerBeat: 500_000), at: 0)
        }

        let primaryMicros = allTempos.first?.microsecondsPerBeat ?? 500_000
        let primaryBPM = min(max(60_000_000.0 / Double(max(1, primaryMicros)), 20.0), 300.0)

        func seconds(forTick tick: Int) -> Double {
            guard tick > 0 else { return 0 }
            var accSeconds = 0.0
            var currentTick = 0
            var currentMicros = allTempos[0].microsecondsPerBeat

            for change in allTempos.dropFirst() {
                if change.tick >= tick { break }
                let deltaTicks = change.tick - currentTick
                if deltaTicks > 0 {
                    accSeconds += (Double(deltaTicks) / Double(ticksPerQuarter)) * (Double(currentMicros) / 1_000_000.0)
                    currentTick = change.tick
                }
                currentMicros = change.microsecondsPerBeat
            }
            let remaining = tick - currentTick
            if remaining > 0 {
                accSeconds += (Double(remaining) / Double(ticksPerQuarter)) * (Double(currentMicros) / 1_000_000.0)
            }
            return accSeconds
        }

        var tracks: [AudioTrack] = []
        var colorIdx = 0

        let nonEmptyRawTracks = rawTracks.filter { !$0.notes.isEmpty }
        if format == 0 || nonEmptyRawTracks.count == 1, let single = nonEmptyRawTracks.first {
            let channelsUsed = Set(single.notes.map(\.channel)).sorted()
            if channelsUsed.count > 1 {
                for ch in channelsUsed {
                    let chNotes = single.notes.filter { $0.channel == ch }
                    let prog = single.programByChannel[ch] ?? 0
                    let isDrum = (ch == 9)
                    let name = isDrum ? "Batterie" : GeneralMIDI.programName(prog)
                    let gainDB = ccVolumeToDB(single.volumeByChannel[ch] ?? 100)
                    let pan = ccPanToNormalized(single.panByChannel[ch] ?? 64)
                    let convertedNotes = chNotes.map { rn -> MIDINote in
                        let s = seconds(forTick: rn.startTick)
                        let e = max(s + MIDINote.minDuration, seconds(forTick: rn.endTick))
                        return MIDINote(
                            pitch: rn.pitch,
                            start: s,
                            duration: e - s,
                            velocity: rn.velocity,
                            channel: ch
                        )
                    }
                    tracks.append(
                        AudioTrack(
                            name: name,
                            colorIndex: colorIdx,
                            gainDB: gainDB,
                            pan: pan,
                            height: 94,
                            kind: .midi,
                            channel: ch,
                            program: prog,
                            isDrum: isDrum,
                            notes: convertedNotes
                        )
                    )
                    colorIdx += 1
                }
            }
        }

        if tracks.isEmpty {
            for rt in rawTracks where !rt.notes.isEmpty {
                let primaryChannel = rt.notes.first?.channel ?? 0
                let prog = rt.programByChannel[primaryChannel] ?? rt.programByChannel.values.first ?? 0
                let isDrum = (primaryChannel == 9)
                let fallbackName = isDrum ? "Batterie" : GeneralMIDI.programName(prog)
                let trackName: String
                if let n = rt.name?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                    trackName = n
                } else {
                    trackName = fallbackName
                }
                let gainDB = ccVolumeToDB(rt.volumeByChannel[primaryChannel] ?? 100)
                let pan = ccPanToNormalized(rt.panByChannel[primaryChannel] ?? 64)
                let convertedNotes = rt.notes.map { rn -> MIDINote in
                    let s = seconds(forTick: rn.startTick)
                    let e = max(s + MIDINote.minDuration, seconds(forTick: rn.endTick))
                    return MIDINote(
                        pitch: rn.pitch,
                        start: s,
                        duration: e - s,
                        velocity: rn.velocity,
                        channel: rn.channel
                    )
                }
                tracks.append(
                    AudioTrack(
                        name: trackName,
                        colorIndex: colorIdx,
                        gainDB: gainDB,
                        pan: pan,
                        height: 94,
                        kind: .midi,
                        channel: primaryChannel,
                        program: prog,
                        isDrum: isDrum,
                        notes: convertedNotes
                    )
                )
                colorIdx += 1
            }
        }

        if tracks.isEmpty {
            tracks.append(AudioTrack(name: "Piano", colorIndex: 0, height: 94, kind: .midi, channel: 0, program: 0))
        }

        let markers: [AudioMarker] = rawMarkers.enumerated().map { idx, m in
            AudioMarker(name: m.text, time: seconds(forTick: m.tick), colorIndex: idx % 8)
        }

        let docTitle = rawTracks.compactMap(\.name).first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? defaultTitle

        return AudioProject(
            title: docTitle,
            bpm: (primaryBPM * 100).rounded() / 100.0,
            timeSignatureNumerator: timeSig.num,
            timeSignatureDenominator: timeSig.den,
            ticksPerQuarterNote: ticksPerQuarter,
            tracks: tracks,
            markers: markers
        )
    }

    private static func parseTrackChunk(_ slice: ArraySlice<UInt8>) -> RawTrackData {
        var result = RawTrackData()
        var idx = slice.startIndex
        let end = slice.endIndex
        var currentTick = 0
        var runningStatus: UInt8 = 0

        var activeNotes: [Int: [(startTick: Int, velocity: Int)]] = [:]

        func closeNote(channel: Int, pitch: Int, atTick: Int) {
            let key = (channel << 8) | pitch
            guard var stack = activeNotes[key], !stack.isEmpty else { return }
            let started = stack.removeFirst()
            if stack.isEmpty {
                activeNotes.removeValue(forKey: key)
            } else {
                activeNotes[key] = stack
            }
            let endTick = max(started.startTick + 1, atTick)
            result.notes.append(
                RawNoteEvent(
                    pitch: pitch,
                    velocity: started.velocity,
                    channel: channel,
                    startTick: started.startTick,
                    endTick: endTick
                )
            )
        }

        while idx < end {
            guard let (delta, nextIdx) = readVLQ(slice, from: idx) else { break }
            idx = nextIdx
            currentTick += delta
            guard idx < end else { break }

            var status = slice[idx]
            if status < 0x80 {
                guard runningStatus >= 0x80 else { break }
                status = runningStatus
            } else {
                idx += 1
                if status < 0xF0 {
                    runningStatus = status
                }
            }

            if status == 0xFF {
                guard idx < end else { break }
                let metaType = slice[idx]
                idx += 1
                guard let (metaLen, dataStart) = readVLQ(slice, from: idx) else { break }
                idx = dataStart
                let metaEnd = min(end, idx + metaLen)
                let payload = slice[idx..<metaEnd]
                idx = metaEnd

                switch metaType {
                case 0x03:
                    if let name = decodeMIDIText(payload), result.name == nil {
                        result.name = name
                    }
                case 0x06, 0x07:
                    if let text = decodeMIDIText(payload), !text.isEmpty {
                        result.markers.append((tick: currentTick, text: text))
                    }
                case 0x51:
                    if payload.count >= 3 {
                        let p0 = Int(payload[payload.startIndex])
                        let p1 = Int(payload[payload.startIndex + 1])
                        let p2 = Int(payload[payload.startIndex + 2])
                        let us = (p0 << 16) | (p1 << 8) | p2
                        if us > 0 {
                            result.tempoChanges.append(TempoChange(tick: currentTick, microsecondsPerBeat: us))
                        }
                    }
                case 0x58:
                    if payload.count >= 2 {
                        let num = Int(payload[payload.startIndex])
                        let denPow = Int(payload[payload.startIndex + 1])
                        let den = 1 << min(max(denPow, 0), 5)
                        if result.timeSignature == nil {
                            result.timeSignature = (max(1, num), max(1, den))
                        }
                    }
                default:
                    break
                }
            } else if status == 0xF0 || status == 0xF7 {
                guard let (sysexLen, dataStart) = readVLQ(slice, from: idx) else { break }
                idx = min(end, dataStart + sysexLen)
            } else {
                let highNibble = status & 0xF0
                let channel = Int(status & 0x0F)

                switch highNibble {
                case 0x80:
                    guard idx + 2 <= end else { idx = end; break }
                    let pitch = Int(slice[idx] & 0x7F)
                    idx += 2
                    closeNote(channel: channel, pitch: pitch, atTick: currentTick)

                case 0x90:
                    guard idx + 2 <= end else { idx = end; break }
                    let pitch = Int(slice[idx] & 0x7F)
                    let vel = Int(slice[idx + 1] & 0x7F)
                    idx += 2
                    if vel == 0 {
                        closeNote(channel: channel, pitch: pitch, atTick: currentTick)
                    } else {
                        let key = (channel << 8) | pitch
                        activeNotes[key, default: []].append((startTick: currentTick, velocity: vel))
                    }

                case 0xA0, 0xE0:
                    idx = min(end, idx + 2)

                case 0xB0:
                    guard idx + 2 <= end else { idx = end; break }
                    let cc = Int(slice[idx] & 0x7F)
                    let val = Int(slice[idx + 1] & 0x7F)
                    idx += 2
                    if cc == 7 && result.volumeByChannel[channel] == nil {
                        result.volumeByChannel[channel] = val
                    } else if cc == 10 && result.panByChannel[channel] == nil {
                        result.panByChannel[channel] = val
                    }

                case 0xC0:
                    guard idx + 1 <= end else { idx = end; break }
                    let prog = Int(slice[idx] & 0x7F)
                    idx += 1
                    if result.programByChannel[channel] == nil {
                        result.programByChannel[channel] = prog
                    }

                case 0xD0:
                    idx = min(end, idx + 1)

                default:
                    idx = min(end, idx + 1)
                }
            }
        }

        for (key, stack) in activeNotes {
            let channel = (key >> 8) & 0x0F
            let pitch = key & 0x7F
            for started in stack {
                result.notes.append(
                    RawNoteEvent(
                        pitch: pitch,
                        velocity: started.velocity,
                        channel: channel,
                        startTick: started.startTick,
                        endTick: max(started.startTick + 120, currentTick)
                    )
                )
            }
        }

        result.notes.sort {
            if $0.startTick != $1.startTick { return $0.startTick < $1.startTick }
            return $0.pitch < $1.pitch
        }
        return result
    }

    // MARK: - Encode Standard MIDI File (.mid, Format 1)

    public static func encode(_ project: AudioProject, range: ClosedRange<Double>? = nil) -> Data {
        let tpq = max(24, min(project.ticksPerQuarterNote, 9600))
        let secondsPerBeat = 60.0 / max(20.0, project.bpm)
        let startOffset = range?.lowerBound ?? 0

        func tick(forSeconds s: Double) -> Int {
            max(0, Int((((s - startOffset) / secondsPerBeat) * Double(tpq)).rounded()))
        }

        var trackChunks: [[UInt8]] = []

        // 1. Conductor / Tempo & Marker Track
        var conductorEvents: [(tick: Int, order: Int, bytes: [UInt8])] = []
        let titleBytes = Array(project.title.utf8)
        conductorEvents.append((0, 0, [0xFF, 0x03] + encodeVLQ(titleBytes.count) + titleBytes))

        let num = UInt8(min(max(project.timeSignatureNumerator, 1), 32))
        var denPow: UInt8 = 2
        switch project.timeSignatureDenominator {
        case 1: denPow = 0
        case 2: denPow = 1
        case 4: denPow = 2
        case 8: denPow = 3
        case 16: denPow = 4
        default: denPow = 2
        }
        conductorEvents.append((0, 1, [0xFF, 0x58, 0x04, num, denPow, 24, 8]))

        let micros = max(20_000, Int((60_000_000.0 / max(20.0, project.bpm)).rounded()))
        conductorEvents.append((
            0,
            2,
            [
                0xFF, 0x51, 0x03,
                UInt8((micros >> 16) & 0xFF),
                UInt8((micros >> 8) & 0xFF),
                UInt8(micros & 0xFF)
            ]
        ))

        for marker in project.markers {
            if let r = range, marker.time < r.lowerBound || marker.time > r.upperBound { continue }
            let mBytes = Array(marker.name.utf8)
            conductorEvents.append((
                tick(forSeconds: marker.time),
                3,
                [0xFF, 0x06] + encodeVLQ(mBytes.count) + mBytes
            ))
        }

        trackChunks.append(serializeTrackEvents(conductorEvents))

        // 2. Musical MIDI Tracks
        let midiTracks = project.tracks.filter { $0.isMIDI || !$0.notes.isEmpty }
        for track in midiTracks {
            var events: [(tick: Int, order: Int, bytes: [UInt8])] = []
            let ch = UInt8(min(max(track.isDrum ? 9 : track.channel, 0), 15))

            let nameBytes = Array(track.name.utf8)
            events.append((0, 0, [0xFF, 0x03] + encodeVLQ(nameBytes.count) + nameBytes))

            let prog = UInt8(min(max(track.program, 0), 127))
            events.append((0, 1, [0xC0 | ch, prog]))

            let ccVol = UInt8(dbToCCVolume(track.gainDB))
            let ccPan = UInt8(normalizedToCCPan(track.pan))
            events.append((0, 2, [0xB0 | ch, 7, ccVol]))
            events.append((0, 3, [0xB0 | ch, 10, ccPan]))

            for note in track.notes where !note.mute {
                if let r = range, note.end <= r.lowerBound || note.start >= r.upperBound { continue }
                let clippedStart = range.map { max(note.start, $0.lowerBound) } ?? note.start
                let clippedEnd = range.map { min(note.end, $0.upperBound) } ?? note.end
                let startTick = tick(forSeconds: clippedStart)
                let endTick = max(startTick + 1, tick(forSeconds: clippedEnd))
                let transposedPitch = UInt8(min(max(note.pitch + track.transpose, 0), 127))
                let vel = UInt8(min(max(note.velocity, 1), 127))
                events.append((startTick, 10, [0x90 | ch, transposedPitch, vel]))
                events.append((endTick, 5, [0x80 | ch, transposedPitch, 0]))
            }

            trackChunks.append(serializeTrackEvents(events))
        }

        var out = Data()
        out.append(contentsOf: [0x4D, 0x54, 0x68, 0x64]) // "MThd"
        appendUInt32(&out, 6)
        appendUInt16(&out, 1) // Format 1
        appendUInt16(&out, UInt16(trackChunks.count))
        appendUInt16(&out, UInt16(tpq))

        for chunk in trackChunks {
            out.append(contentsOf: [0x4D, 0x54, 0x72, 0x6B]) // "MTrk"
            appendUInt32(&out, UInt32(chunk.count))
            out.append(contentsOf: chunk)
        }
        return out
    }

    private static func serializeTrackEvents(_ events: [(tick: Int, order: Int, bytes: [UInt8])]) -> [UInt8] {
        let sorted = events.sorted {
            if $0.tick != $1.tick { return $0.tick < $1.tick }
            return $0.order < $1.order
        }
        var bytes: [UInt8] = []
        var lastTick = 0
        for ev in sorted {
            let delta = max(0, ev.tick - lastTick)
            lastTick = max(lastTick, ev.tick)
            bytes.append(contentsOf: encodeVLQ(delta))
            bytes.append(contentsOf: ev.bytes)
        }
        bytes.append(contentsOf: [0x00, 0xFF, 0x2F, 0x00])
        return bytes
    }

    // MARK: - Helpers

    private static func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }

    private static func appendUInt16(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    private static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    private static func readVLQ(_ slice: ArraySlice<UInt8>, from start: Int) -> (Int, Int)? {
        var idx = start
        var value = 0
        var count = 0
        while idx < slice.endIndex && count < 4 {
            let b = slice[idx]
            idx += 1
            count += 1
            value = (value << 7) | Int(b & 0x7F)
            if (b & 0x80) == 0 {
                return (value, idx)
            }
        }
        return nil
    }

    private static func encodeVLQ(_ value: Int) -> [UInt8] {
        var v = max(0, value)
        var buffer = [UInt8(v & 0x7F)]
        v >>= 7
        while v > 0 {
            buffer.insert(UInt8((v & 0x7F) | 0x80), at: 0)
            v >>= 7
        }
        return buffer
    }

    private static func decodeMIDIText(_ bytes: ArraySlice<UInt8>) -> String? {
        guard !bytes.isEmpty else { return nil }
        if let utf8 = String(bytes: bytes, encoding: .utf8) {
            return utf8.trimmingCharacters(in: .controlCharacters)
        }
        return String(bytes: bytes, encoding: .isoLatin1)?.trimmingCharacters(in: .controlCharacters)
    }

    private static func ccVolumeToDB(_ cc: Int) -> Double {
        guard cc > 0 else { return -60.0 }
        let ratio = Double(min(max(cc, 1), 127)) / 100.0
        let db = 20.0 * log10(ratio)
        return (db * 10).rounded() / 10.0
    }

    private static func dbToCCVolume(_ db: Double) -> Int {
        if db <= -60 { return 0 }
        let linear = pow(10.0, db / 20.0)
        return min(max(Int((linear * 100.0).rounded()), 1), 127)
    }

    private static func ccPanToNormalized(_ cc: Int) -> Double {
        if cc == 64 { return 0 }
        let p = (Double(min(max(cc, 0), 127)) - 64.0) / 63.0
        return (min(max(p, -1), 1) * 100).rounded() / 100.0
    }

    private static func normalizedToCCPan(_ pan: Double) -> Int {
        min(max(Int((pan * 63.0 + 64.0).rounded()), 0), 127)
    }
}
