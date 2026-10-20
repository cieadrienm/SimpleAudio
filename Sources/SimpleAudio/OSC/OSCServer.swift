import Foundation
import SimpleAudioCore
import SimpleAudioEngine

@MainActor
final class OSCServer {
    private unowned let model: AppModel
    private let listener = UDPListener()

    init(model: AppModel) {
        self.model = model
    }

    @discardableResult
    func start(port: UInt16) -> Bool {
        stop()
        let ok = listener.start(port: port) { [weak self] data in
            guard let messages = try? OSCCodec.decodePacket(data) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                for msg in messages {
                    self.handle(msg)
                }
            }
        }
        if ok {
            model.oscInputPort = listener.port
            model.oscListening = true
        } else {
            model.oscListening = false
        }
        return ok
    }

    func stop() {
        listener.stop()
        model.oscListening = false
    }

    func sendFeedbackIfEnabled() {
        guard model.oscFeedbackEnabled else { return }
        let host = model.oscOutputHost
        let port = model.oscOutputPort
        let timeMsg = OSCMessage(
            "/simpleaudio/state/time",
            [.float(Float(model.playhead)), .float(Float(model.store.project.totalDuration))]
        )
        let peakMsg = OSCMessage(
            "/simpleaudio/state/peaks",
            [.float(model.peakLeft), .float(model.peakRight)]
        )
        UDPSender.send(OSCCodec.encode(timeMsg), host: host, port: port)
        UDPSender.send(OSCCodec.encode(peakMsg), host: host, port: port)
    }

    func handle(_ msg: OSCMessage) {
        let parts = msg.address
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !parts.isEmpty else { return }

        // Strip optional leading "simpleaudio" namespace so both `/simpleaudio/play` and `/play` work
        let route = parts.first == "simpleaudio" ? Array(parts.dropFirst()) : parts
        guard let head = route.first else { return }

        switch head {
        case "play":
            model.play()

        case "pause":
            model.pause()

        case "toggle":
            model.togglePlay()

        case "stop":
            model.stop()

        case "rewind":
            model.seek(to: 0)

        case "seek":
            if let t = msg.double(at: 0) {
                model.seek(to: t)
            }

        case "loop":
            if let a = msg.double(at: 0), let b = msg.double(at: 1), b > a {
                model.store.perform("Boucle OSC") { proj in
                    proj.loopRange = a...b
                }
            } else if let on = msg.bool(at: 0), !on {
                model.store.perform("Boucle OSC") { proj in
                    proj.loopRange = nil
                }
            } else {
                model.toggleLoop()
            }

        case "select":
            if route.count >= 2 && route[1] == "range",
               let a = msg.double(at: 0), let b = msg.double(at: 1), b > a {
                model.selectionRange = max(0, a)...b
            } else {
                model.selectionRange = nil
            }

        case "split":
            let at = msg.double(at: 0) ?? model.playhead
            model.seek(to: at)
            model.splitAtPlayhead()

        case "fadein":
            let d = msg.double(at: 0) ?? 0.5
            model.applyFadeIn(duration: d)

        case "fadeout":
            let d = msg.double(at: 0) ?? 0.5
            model.applyFadeOut(duration: d)

        case "master":
            if route.count >= 2 && route[1] == "gain", let db = msg.double(at: 0) {
                model.store.perform("Gain Master OSC") { proj in
                    proj.masterGainDB = min(max(db, -60), 24)
                }
            }

        case "track":
            // `/simpleaudio/track/<index>/gain|pan|mute|solo` (supports 0-based or 1-based index)
            guard route.count >= 3, let rawIdx = Int(route[1]) else { return }
            let tracks = model.store.project.tracks
            let idx = (rawIdx >= 1 && rawIdx <= tracks.count && rawIdx == tracks.count) ? (rawIdx - 1) : min(max(0, rawIdx), max(0, tracks.count - 1))
            guard idx < tracks.count else { return }
            let trackID = tracks[idx].id

            switch route[2] {
            case "gain":
                if let db = msg.double(at: 0) {
                    model.setTrackGain(trackID, gainDB: db)
                }
            case "pan":
                if let pan = msg.double(at: 0) {
                    model.setTrackPan(trackID, pan: pan)
                }
            case "mute":
                if let b = msg.bool(at: 0) {
                    model.store.perform("Muet piste OSC") { proj in
                        try? Operations.setTrackMute(&proj, id: trackID, mute: b)
                    }
                } else {
                    model.toggleTrackMute(trackID)
                }
            case "solo":
                if let b = msg.bool(at: 0) {
                    model.store.perform("Solo piste OSC") { proj in
                        try? Operations.setTrackSolo(&proj, id: trackID, solo: b)
                    }
                } else {
                    model.toggleTrackSolo(trackID)
                }
            default:
                break
            }

        case "clip":
            // `/simpleaudio/clip/<index>/gain|fadein|fadeout`
            guard route.count >= 3, let rawIdx = Int(route[1]) else { return }
            let all = model.store.project.allClips
            let idx = min(max(0, rawIdx), max(0, all.count - 1))
            guard idx < all.count else { return }
            let clipID = all[idx].clip.id

            switch route[2] {
            case "gain":
                if let db = msg.double(at: 0) {
                    model.store.perform("Gain clip OSC") { proj in
                        try? Operations.setClipGain(&proj, id: clipID, gainDB: db)
                    }
                }
            case "fadein":
                if let d = msg.double(at: 0) {
                    model.store.perform("Fondu entrée OSC") { proj in
                        try? Operations.setFade(&proj, id: clipID, fadeIn: d)
                    }
                }
            case "fadeout":
                if let d = msg.double(at: 0) {
                    model.store.perform("Fondu sortie OSC") { proj in
                        try? Operations.setFade(&proj, id: clipID, fadeOut: d)
                    }
                }
            default:
                break
            }

        case "marker":
            if route.count >= 2 && route[1] == "jump" {
                if let name = msg.string(at: 0),
                   let marker = model.store.project.markers.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                    model.seek(to: marker.time)
                } else if let idx = msg.int(at: 0),
                          idx >= 0, idx < model.store.project.markers.count {
                    model.seek(to: model.store.project.markers[idx].time)
                }
            } else if route.count >= 2 && route[1] == "add" {
                let name = msg.string(at: 0)
                model.addMarkerAtPlayhead(name: name)
            }

        case "export":
            if let path = msg.string(at: 0), !path.isEmpty {
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                let fmt = ExportFormat(rawValue: url.pathExtension.lowercased()) ?? .wav
                _ = try? AudioExporter.export(
                    project: model.store.project,
                    waveforms: model.waveforms,
                    to: url,
                    options: ExportOptions(format: fmt),
                    baseURL: model.store.url
                )
            }

        default:
            break
        }
    }
}
