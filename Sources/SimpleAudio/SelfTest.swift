import AppKit
import Foundation
import SimpleAudioCore
import SimpleAudioEngine

@MainActor
enum SelfTest {
    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message) }
    }

    static func runAndExit() -> Never {
        do {
            try run()
            print("SELF-TEST PASSED")
            exit(0)
        } catch {
            fputs("SELF-TEST FAILED: \(error)\n", stderr)
            exit(1)
        }
    }

    static func run() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("SimpleAudioSelfTest-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        // 1. Load synthetic multitrack demo
        let model = AppModel()
        let demoURL = try SyntheticAudio.generateDemoDirectory(at: tmp)
        model.openDocument(url: demoURL)
        try check(model.store.project.tracks.count == 3, "Expected 3 tracks in demo project")
        try check(model.store.project.allClips.count == 4, "Expected 4 clips in demo project")

        // Verify waveform cache loaded peak + RMS + stereo envelopes
        let firstClip = model.store.project.tracks[0].clips[0]
        let wavURL = model.resolvedURL(for: firstClip.path)
        guard let wave = model.waveforms.envelope(for: wavURL) else {
            throw Failure("Waveform envelope missing for \(wavURL.path)")
        }
        try check(!wave.peaks.isEmpty && !wave.rms.isEmpty, "Waveform peaks/rms empty")
        try check(wave.channelCount == 2, "Expected stereo waveform")

        // 2. Verify TimelineView geometry, hit-testing, and mouse gestures
        let tv = TimelineView(model: model)
        tv.frame = CGRect(x: 0, y: 0, width: 1000, height: 500)
        tv.layout()
        let rows = tv.trackRows()
        try check(rows.count == 3, "Expected 3 track rows")
        let clipRect = tv.clipRect(firstClip, in: rows[0].rect)
        try check(clipRect.width > 100, "Clip rect should be wide enough")

        // Hit-test clip body, start edge, and fade-in handle
        let midPoint = CGPoint(x: clipRect.midX, y: clipRect.midY)
        try check(tv.hit(at: midPoint) == .clipBody(clipID: firstClip.id, trackID: rows[0].track.id), "Expected clipBody hit")
        let startEdgePoint = CGPoint(x: clipRect.minX + 2, y: clipRect.midY)
        try check(tv.hit(at: startEdgePoint) == .clipEdge(clipID: firstClip.id, edge: .start), "Expected clipEdge(.start) hit")
        let handles = tv.fadeHandleCenters(for: firstClip, in: rows[0].rect)
        try check(tv.hit(at: handles.fadeIn) == .fadeHandle(clipID: firstClip.id, isIn: true), "Expected fadeIn handle hit")

        // 3. Test range copy/paste, fade, and undo/redo
        let initialProject = model.store.project
        let initialChangeCount = model.store.changeCount
        model.selectionRange = 0.5...1.5
        model.copySelection()
        try check(!model.clipboard.isEmpty, "Expected non-empty clipboard after copySelection")
        model.applyFadeIn(duration: 0.4, shape: .cosine)
        try check(model.store.changeCount == initialChangeCount + 1, "Expected 1 undo step for fade-in")
        model.store.undo()
        try check(model.store.project == initialProject, "Expected undo to restore initial project state")
        try check(model.store.canRedo, "Expected canRedo == true after undo")

        // 4. Test multi-format audio export (WAV + M4A)
        let outWAV = tmp.appendingPathComponent("export.wav")
        let wavRes = try AudioExporter.export(
            project: model.store.project,
            waveforms: model.waveforms,
            to: outWAV,
            options: ExportOptions(format: .wav, sampleRate: 48_000, bitDepth: .int24, normalizePeak: true),
            baseURL: model.store.url
        )
        try check(fm.fileExists(atPath: wavRes.url.path), "WAV export file missing")
        try check(wavRes.duration > 3.5, "WAV export duration too short: \(wavRes.duration)")
        try check(abs(wavRes.peakDB - (-0.1)) < 0.25, "Expected peak normalized near -0.1 dBFS, got \(wavRes.peakDB)")

        let outM4A = tmp.appendingPathComponent("export.m4a")
        let m4aRes = try AudioExporter.export(
            project: model.store.project,
            waveforms: model.waveforms,
            to: outM4A,
            options: ExportOptions(format: .m4a, sampleRate: 48_000, range: 0.5...2.5),
            baseURL: model.store.url
        )
        try check(fm.fileExists(atPath: m4aRes.url.path), "M4A export file missing")
        try check(abs(m4aRes.duration - 2.0) < 0.15, "M4A range export duration mismatch: \(m4aRes.duration)")

        // 5. Test HTTP API Router & OSC Server
        let stateResp = APIRouter.handle(
            HTTPRequest(method: "GET", rawTarget: "/v1/state", path: "/v1/state", query: [:], headers: [:], body: Data()),
            model: model
        )
        try check(stateResp.status == 200, "GET /v1/state failed")

        let osc = OSCServer(model: model)
        osc.handle(OSCMessage("/simpleaudio/seek", [.float(1.75)]))
        try check(abs(model.playhead - 1.75) < 1e-4, "OSC seek failed")
        osc.handle(OSCMessage("/simpleaudio/track/0/gain", [.float(-4.5)]))
        try check(abs(model.store.project.tracks[0].gainDB - (-4.5)) < 1e-4, "OSC track gain failed")

        // 6. Test offscreen PNG snapshot rendering
        guard let png = Snapshot.renderOffscreenPNG(model: model), png.count > 2000 else {
            throw Failure("Offscreen PNG snapshot rendering failed")
        }
    }
}
