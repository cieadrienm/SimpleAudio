import Foundation
import Testing
@testable import SimpleAudioCore

@Suite("SimpleAudioCore Tests")
struct SimpleAudioCoreTests {
    @Test("FadeShape mathematical gain curves")
    func testFadeShapeMath() {
        for shape in FadeShape.allCases {
            #expect(abs(shape.gain(at: 0, isIn: true) - 0) < 1e-6)
            #expect(abs(shape.gain(at: 1, isIn: true) - 1) < 1e-6)
            #expect(abs(shape.gain(at: 0, isIn: false) - 1) < 1e-6)
            #expect(abs(shape.gain(at: 1, isIn: false) - 0) < 1e-6)
            let midIn = shape.gain(at: 0.5, isIn: true)
            #expect(midIn > 0.05 && midIn < 0.95)
        }
    }

    @Test("Clip split, trim, fade, and gain operations")
    func testClipOperations() throws {
        var proj = AudioProject()
        let trackID = proj.tracks[0].id
        let clip = AudioClip(
            name: "Voix",
            path: "/tmp/voix.wav",
            offset: 1.0,
            sourceStart: 0.0,
            duration: 4.0,
            sourceDuration: 4.0,
            gainDB: 0.0,
            fadeIn: 0.5,
            fadeOut: 0.5
        )
        try Operations.addClip(&proj, toTrack: trackID, clip: clip)
        #expect(proj.tracks[0].clips.count == 1)

        // Split at t = 3.0s
        let (leftID, rightID) = try Operations.splitClip(&proj, id: clip.id, at: 3.0)
        #expect(proj.tracks[0].clips.count == 2)
        let left = proj.tracks[0].clips[0]
        let right = proj.tracks[0].clips[1]
        #expect(left.id == leftID)
        #expect(right.id == rightID)
        #expect(abs(left.offset - 1.0) < 1e-6)
        #expect(abs(left.duration - 2.0) < 1e-6)
        #expect(abs(left.fadeIn - 0.5) < 1e-6)
        #expect(abs(left.fadeOut - 0.0) < 1e-6)
        #expect(abs(right.offset - 3.0) < 1e-6)
        #expect(abs(right.sourceStart - 2.0) < 1e-6)
        #expect(abs(right.duration - 2.0) < 1e-6)
        #expect(abs(right.fadeOut - 0.5) < 1e-6)
    }

    @Test("Time range extract, cut, paste, ripple delete, crop, and range fades")
    func testTimeRangeOperations() throws {
        var proj = AudioProject()
        let trackID = proj.tracks[0].id
        let clip = AudioClip(
            name: "Synth",
            path: "/tmp/synth.wav",
            offset: 0.0,
            sourceStart: 0.0,
            duration: 6.0,
            sourceDuration: 6.0
        )
        try Operations.addClip(&proj, toTrack: trackID, clip: clip)

        // Extract slice [1.5 ... 3.5]
        let slices = Operations.extractSlices(from: proj, in: 1.5...3.5)
        #expect(slices.count == 1)
        #expect(abs(slices[0].duration - 2.0) < 1e-6)
        #expect(abs(slices[0].sourceStart - 1.5) < 1e-6)

        // Ripple delete [1.5 ... 3.5]: total duration should drop from 6.0s to 4.0s
        try Operations.deleteRange(&proj, in: 1.5...3.5, ripple: true)
        #expect(proj.tracks[0].clips.count == 2)
        #expect(abs(proj.totalDuration - 4.0) < 1e-6)

        // Paste extracted 2.0s slice at t = 4.0s
        let pasted = try Operations.paste(&proj, slices: slices, at: 4.0, targetTrackID: trackID, ripple: false)
        #expect(pasted.count == 1)
        #expect(abs(proj.totalDuration - 6.0) < 1e-6)

        // Crop to [0.5 ... 2.5]
        try Operations.cropToRange(&proj, in: 0.5...2.5)
        #expect(abs(proj.totalDuration - 2.0) < 1e-6)
    }

    @Test("DocumentStore single write path and Undo/Redo stack")
    @MainActor
    func testDocumentStoreUndoRedo() throws {
        let store = DocumentStore()
        let trackID = store.project.tracks[0].id
        store.perform("Ajouter un clip") { proj in
            try? Operations.addClip(
                &proj,
                toTrack: trackID,
                clip: AudioClip(name: "A", path: "/tmp/a.wav", duration: 2.0, sourceDuration: 2.0)
            )
        }
        #expect(store.project.tracks[0].clips.count == 1)
        #expect(store.canUndo)
        #expect(store.undoLabel == "Ajouter un clip")

        store.undo()
        #expect(store.project.tracks[0].clips.isEmpty)
        #expect(store.canRedo)

        store.redo()
        #expect(store.project.tracks[0].clips.count == 1)

        let encoded = try DocumentStore.encode(store.project)
        let decoded = try DocumentStore.decode(encoded)
        #expect(decoded == store.project)

        // Track reordering + Undo/Redo
        let t1 = store.project.tracks[0].id
        var t2 = UUID()
        var t3 = UUID()
        store.perform("Ajouter 2 pistes") { proj in
            t2 = proj.addTrack(name: "Piste 2")
            t3 = proj.addMIDITrack(name: "Piste 3 MIDI")
        }
        #expect(store.project.tracks.map(\.id) == [t1, t2, t3])

        store.perform("Réordonner la piste") { proj in
            proj.moveTrack(t3, to: 0)
        }
        #expect(store.project.tracks.map(\.id) == [t3, t1, t2])

        store.perform("Descendre la piste") { proj in
            proj.moveTrack(t3, by: 1)
        }
        #expect(store.project.tracks.map(\.id) == [t1, t3, t2])

        store.undo()
        #expect(store.project.tracks.map(\.id) == [t3, t1, t2])
    }

    @Test("OSC 1.0/1.1 message and bundle codec round-trip")
    func testOSCCodec() throws {
        let msg = OSCMessage(
            "/simpleaudio/track/0/gain",
            [.float(-3.5), .int(1), .string("Voix"), .bool(true)]
        )
        let data = OSCCodec.encode(msg)
        let decoded = try OSCCodec.decodePacket(data)
        #expect(decoded.count == 1)
        #expect(decoded[0] == msg)
        #expect(abs((decoded[0].double(at: 0) ?? 0) - (-3.5)) < 1e-4)
        #expect(decoded[0].int(at: 1) == 1)
        #expect(decoded[0].string(at: 2) == "Voix")
        #expect(decoded[0].bool(at: 3) == true)

        let bundleData = OSCCodec.encodeBundle([
            OSCMessage("/simpleaudio/seek", [.float(2.25)]),
            OSCMessage("/simpleaudio/play"),
        ])
        let bundleDecoded = try OSCCodec.decodePacket(bundleData)
        #expect(bundleDecoded.count == 2)
        #expect(bundleDecoded[0].address == "/simpleaudio/seek")
        #expect(bundleDecoded[1].address == "/simpleaudio/play")
    }

    @Test("MIDIFileCodec Standard MIDI File (.mid) round-trip and MIDI note operations")
    func testMIDICodecAndOperations() throws {
        var proj = AudioProject(sampleRate: 48_000, bpm: 120, timeSignatureNumerator: 4, timeSignatureDenominator: 4)
        let midiTrackID = proj.addMIDITrack(name: "Synth Lead", program: 80, channel: 0, isDrum: false)
        proj.addNote(MIDINote(pitch: 60, start: 0.03, duration: 0.48, velocity: 100), toTrack: midiTrackID)
        proj.addNote(MIDINote(pitch: 64, start: 0.5, duration: 1.0, velocity: 110), toTrack: midiTrackID)
        #expect(proj.noteCount == 2)

        // Quantize notes to 1/16 beat (0.125s at 120 BPM) including duration
        proj.quantizeNotes(nil, subdivisionBeats: 0.25, quantizeDuration: true)
        let firstNote = proj.tracks.first(where: { $0.id == midiTrackID })!.notes[0]
        #expect(abs(firstNote.start - 0.0) < 1e-6)
        #expect(abs(firstNote.duration - 0.5) < 1e-6)

        // Transpose +12 semitones
        proj.transposeNotes(Set(proj.allNotes.map(\.note.id)), semitones: 12)
        let transposedPitches = proj.tracks.first(where: { $0.id == midiTrackID })!.notes.map(\.pitch).sorted()
        #expect(transposedPitches == [72, 76])

        // Split second note at t = 1.0s
        let splitCreated = proj.splitNotes(at: 1.0)
        #expect(splitCreated.count == 1)
        #expect(proj.noteCount == 3)

        // Encode to binary .mid and decode back
        let midData = MIDIFileCodec.encode(proj)
        #expect(midData.count > 32)
        let decoded = try MIDIFileCodec.decode(midData, defaultTitle: "RoundTrip")
        #expect(abs(decoded.bpm - 120.0) < 0.5)
        #expect(decoded.noteCount == 3)
        #expect(decoded.tracks.first?.program == 80)
    }
}
