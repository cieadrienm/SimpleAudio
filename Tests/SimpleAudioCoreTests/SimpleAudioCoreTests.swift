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
}
