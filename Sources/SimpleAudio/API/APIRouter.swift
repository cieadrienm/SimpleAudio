import AppKit
import Foundation
import SimpleAudioCore
import SimpleAudioEngine

@MainActor
enum APIRouter {
    static func handle(_ req: HTTPRequest, model: AppModel) -> HTTPResponse {
        let p = req.path.hasPrefix("/v1") ? String(req.path.dropFirst(3)) : req.path

        switch (req.method, p) {
        case ("GET", "/state"), ("GET", "/"):
            return .json(stateDict(model: model))

        case ("GET", "/help"):
            return .json(APIHelp.schema)

        case ("GET", "/document"):
            guard let data = try? DocumentStore.encode(model.store.project) else {
                return .error(500, "Failed to encode document")
            }
            return HTTPResponse(status: 200, contentType: "application/json; charset=utf-8", body: data)

        case ("PUT", "/document"):
            do {
                let decoded = try DocumentStore.decode(req.body)
                model.store.perform("Remplacer le document") { proj in
                    proj = decoded
                }
                model.loadWaveformsForCurrentProject()
                if req.query["save"] == "1", let url = model.store.url {
                    try? model.store.save(to: url)
                }
                return .json(stateDict(model: model))
            } catch {
                return .error(400, "Invalid AudioProject JSON: \(error)")
            }

        case ("POST", "/edit"):
            return handleEdit(req, model: model)

        case ("POST", "/open"):
            guard let body = jsonObject(req.body),
                  let path = body["path"] as? String, !path.isEmpty else {
                return .error(400, "Missing 'path'")
            }
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return .error(404, "File not found: \(url.path)")
            }
            if url.pathExtension.lowercased() == "simpleaudio" {
                model.openDocument(url: url)
            } else {
                model.openAudioAsNewProject(url: url)
            }
            return .json(stateDict(model: model))

        case ("POST", "/import"):
            guard let body = jsonObject(req.body),
                  let path = body["path"] as? String, !path.isEmpty else {
                return .error(400, "Missing 'path'")
            }
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return .error(404, "File not found: \(url.path)")
            }
            let at = num(body["at"]) ?? 0
            if let trackIdx = int(body["track"]),
               trackIdx >= 0,
               trackIdx < model.store.project.tracks.count {
                let trackID = model.store.project.tracks[trackIdx].id
                let meta = model.waveforms.probe(url: url)
                _ = model.waveforms.load(url: url)
                let dur = max(meta.duration, 0.05)
                let clip = AudioClip(
                    name: url.deletingPathExtension().lastPathComponent,
                    path: url.path,
                    offset: max(0, at),
                    sourceStart: 0,
                    duration: dur,
                    sourceDuration: dur
                )
                model.store.perform("Importer un fichier audio") { proj in
                    try? Operations.addClip(&proj, toTrack: trackID, clip: clip)
                }
                model.selectedClips = [clip.id]
                model.selectedTrackID = trackID
            } else {
                model.importAudioFiles(urls: [url], at: at, onNewTracks: true)
            }
            return .json(stateDict(model: model))

        case ("POST", "/export"):
            return handleExport(req, model: model)

        case ("POST", "/transport"):
            return handleTransport(req, model: model)

        case ("POST", "/select"):
            return handleSelect(req, model: model)

        case ("POST", "/undo"):
            model.store.undo()
            return .json(stateDict(model: model))

        case ("POST", "/redo"):
            model.store.redo()
            return .json(stateDict(model: model))

        case ("POST", "/save"):
            let body = jsonObject(req.body) ?? [:]
            if let path = body["path"] as? String, !path.isEmpty {
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                do {
                    try model.store.save(to: url)
                } catch {
                    return .error(500, "Save failed: \(error)")
                }
            } else if let url = model.store.url {
                do {
                    try model.store.save(to: url)
                } catch {
                    return .error(500, "Save failed: \(error)")
                }
            } else {
                return .error(400, "Document has no URL; provide 'path'")
            }
            return .json(stateDict(model: model))

        case ("GET", "/snapshot.png"):
            guard let data = Snapshot.captureMainWindowPNG(model: model) else {
                return .error(500, "Failed to render window snapshot")
            }
            return .png(data)

        case ("GET", "/waveform"):
            guard let path = req.query["path"], !path.isEmpty else {
                return .error(400, "Missing 'path' query parameter")
            }
            let url = model.resolvedURL(for: (path as NSString).expandingTildeInPath)
            guard let wave = model.waveforms.load(url: url) else {
                return .error(404, "Unable to decode audio at \(url.path)")
            }
            let targetBins = max(10, min(Int(req.query["bins"] ?? "200") ?? 200, 4000))
            let downsampled = downsample(wave: wave, count: targetBins)
            return .json([
                "path": url.path,
                "duration": wave.duration,
                "sampleRate": wave.sampleRate,
                "channels": wave.channelCount,
                "bins": downsampled.peaks.count,
                "peaks": downsampled.peaks,
                "rms": downsampled.rms,
            ])

        case ("GET", "/silences"):
            guard let path = req.query["path"], !path.isEmpty else {
                return .error(400, "Missing 'path' query parameter")
            }
            let url = model.resolvedURL(for: (path as NSString).expandingTildeInPath)
            guard let pcm = model.waveforms.loadPCM(for: url) else {
                return .error(404, "Unable to decode audio at \(url.path)")
            }
            let thresholdDB = Double(req.query["thresholdDB"] ?? "-42") ?? -42.0
            let minDuration = Double(req.query["minDuration"] ?? "0.15") ?? 0.15
            let ranges = AudioAnalysis.detectSilences(in: pcm, thresholdDB: thresholdDB, minDuration: minDuration)
            let items = ranges.map { ["start": $0.start, "end": $0.end, "duration": $0.duration] }
            return .json([
                "path": url.path,
                "duration": pcm.duration,
                "thresholdDB": thresholdDB,
                "minDuration": minDuration,
                "silences": items,
            ])

        default:
            return .error(404, "Unknown route: \(req.method) \(req.path)")
        }
    }

    // MARK: State Dictionary

    static func stateDict(model: AppModel) -> [String: Any] {
        let proj = model.store.project
        var dict: [String: Any] = [
            "version": AppVersion.current.version,
            "build": AppVersion.current.build ?? NSNull(),
            "company": "cie Adrien M",
            "file": model.store.url?.path ?? NSNull(),
            "dirty": model.store.isDirty,
            "changeCount": model.store.changeCount,
            "playing": model.transportPlaying,
            "time": model.playhead,
            "duration": proj.totalDuration,
            "sampleRate": proj.sampleRate,
            "masterGainDB": proj.masterGainDB,
            "trackCount": proj.tracks.count,
            "clipCount": proj.allClips.count,
            "markerCount": proj.markers.count,
            "selectedClips": model.selectedClips.map(\.uuidString).sorted(),
            "selectedTrack": model.selectedTrackID?.uuidString ?? NSNull(),
            "peakLeft": model.peakLeft,
            "peakRight": model.peakRight,
            "apiPort": model.apiPort,
            "oscInPort": model.oscInputPort,
            "undoLabel": model.store.undoLabel ?? NSNull(),
            "redoLabel": model.store.redoLabel ?? NSNull(),
        ]
        if let loop = proj.loopRange {
            dict["loopRange"] = [loop.lowerBound, loop.upperBound]
        } else {
            dict["loopRange"] = NSNull()
        }
        if let sel = model.selectionRange {
            dict["selectionRange"] = [sel.lowerBound, sel.upperBound]
        } else {
            dict["selectionRange"] = NSNull()
        }
        return dict
    }

    // MARK: Batch Edit Handler

    private static func handleEdit(_ req: HTTPRequest, model: AppModel) -> HTTPResponse {
        guard let body = jsonObject(req.body),
              let ops = body["ops"] as? [[String: Any]] else {
            return .error(400, "Missing 'ops' array")
        }
        let label = (body["label"] as? String) ?? "Édition API (\(ops.count))"
        var copy = model.store.project
        var createdClips: [UUID] = []

        do {
            for op in ops {
                guard let kind = op["op"] as? String else {
                    throw EditError.invalidArg("Operation missing 'op' field")
                }
                try applyOp(kind, op: op, to: &copy, model: model, createdClips: &createdClips)
            }
        } catch {
            return .error(400, "\(error)")
        }

        let finalProject = copy
        model.store.perform(label) { proj in
            proj = finalProject
        }
        if !createdClips.isEmpty {
            model.selectedClips = Set(createdClips)
        }
        return .json(stateDict(model: model))
    }

    private static func applyOp(
        _ kind: String,
        op: [String: Any],
        to proj: inout AudioProject,
        model: AppModel,
        createdClips: inout [UUID]
    ) throws {
        switch kind {
        case "track.add":
            let name = op["name"] as? String
            let at = int(op["at"])
            _ = Operations.addTrack(&proj, name: name, at: at)

        case "track.remove":
            let id = try resolveTrackID(op["track"], in: proj)
            try Operations.removeTrack(&proj, id: id)

        case "track.duplicate":
            let id = try resolveTrackID(op["track"], in: proj)
            _ = try Operations.duplicateTrack(&proj, id: id)

        case "track.set":
            let id = try resolveTrackID(op["track"], in: proj)
            guard let ti = proj.trackIndex(of: id) else { throw EditError.trackNotFound }
            if let name = op["name"] as? String { try Operations.renameTrack(&proj, id: id, name: name) }
            if let db = num(op["gainDB"]) { try Operations.setTrackGain(&proj, id: id, gainDB: db) }
            if let pan = num(op["pan"]) { try Operations.setTrackPan(&proj, id: id, pan: pan) }
            if let mute = op["mute"] as? Bool { try Operations.setTrackMute(&proj, id: id, mute: mute) }
            if let solo = op["solo"] as? Bool { try Operations.setTrackSolo(&proj, id: id, solo: solo) }
            if let locked = op["locked"] as? Bool { proj.tracks[ti].locked = locked }
            if let stereo = op["stereoSplit"] as? Bool { proj.tracks[ti].stereoSplit = stereo }

        case "clip.add":
            guard let rawPath = op["path"] as? String, !rawPath.isEmpty else {
                throw EditError.invalidArg("clip.add requires 'path'")
            }
            let url = model.resolvedURL(for: (rawPath as NSString).expandingTildeInPath)
            let meta = model.waveforms.probe(url: url)
            _ = model.waveforms.load(url: url)
            let srcDur = max(meta.duration, num(op["duration"]) ?? 1.0, AudioClip.minDuration)
            let srcStart = max(0, num(op["sourceStart"]) ?? 0)
            let dur = min(max(AudioClip.minDuration, num(op["duration"]) ?? (srcDur - srcStart)), max(AudioClip.minDuration, srcDur - srcStart))
            let trackID: UUID
            if let rawTrack = op["track"] {
                trackID = try resolveTrackID(rawTrack, in: proj)
            } else if let first = proj.tracks.first {
                trackID = first.id
            } else {
                trackID = Operations.addTrack(&proj).id
            }
            let shape = (op["fadeShape"] as? String).flatMap(FadeShape.init(rawValue:)) ?? .cosine
            let clip = AudioClip(
                name: (op["name"] as? String) ?? url.deletingPathExtension().lastPathComponent,
                path: url.path,
                offset: max(0, num(op["offset"]) ?? 0),
                sourceStart: srcStart,
                duration: dur,
                sourceDuration: srcDur,
                gainDB: num(op["gainDB"]) ?? 0,
                fadeIn: num(op["fadeIn"]) ?? 0,
                fadeOut: num(op["fadeOut"]) ?? 0,
                fadeShape: shape
            )
            try Operations.addClip(&proj, toTrack: trackID, clip: clip)
            createdClips.append(clip.id)

        case "clip.trim":
            let id = try resolveClipID(op["clip"])
            guard let (ti, ci) = proj.clipLocation(of: id) else { throw EditError.clipNotFound }
            let orig = proj.tracks[ti].clips[ci]
            let newOffset = num(op["start"]) ?? orig.offset
            let newEnd = num(op["end"]) ?? orig.end
            let deltaStart = newOffset - orig.offset
            let newSourceStart = max(0, orig.sourceStart + deltaStart)
            let newDuration = max(AudioClip.minDuration, newEnd - newOffset)
            try Operations.trimClip(&proj, id: id, offset: newOffset, sourceStart: newSourceStart, duration: newDuration)

        case "clip.move":
            let id = try resolveClipID(op["clip"])
            guard let (ti, _) = proj.clipLocation(of: id) else { throw EditError.clipNotFound }
            let targetTrack = try op["track"].map { try resolveTrackID($0, in: proj) } ?? proj.tracks[ti].id
            let offset = num(op["offset"]) ?? 0
            try Operations.moveClip(&proj, id: id, toTrack: targetTrack, offset: offset)

        case "clip.slip":
            let id = try resolveClipID(op["clip"])
            guard let (ti, ci) = proj.clipLocation(of: id) else { throw EditError.clipNotFound }
            let by = num(op["by"]) ?? 0
            try Operations.slipClip(&proj, id: id, toSourceStart: proj.tracks[ti].clips[ci].sourceStart + by)

        case "clip.split":
            guard let at = num(op["at"]) else { throw EditError.invalidArg("clip.split requires 'at'") }
            if let rawClip = op["clip"] {
                let id = try resolveClipID(rawClip)
                let pair = try Operations.splitClip(&proj, id: id, at: at)
                createdClips.append(contentsOf: [pair.0, pair.1])
            } else {
                let pairs = try Operations.splitAtTime(&proj, time: at)
                for p in pairs { createdClips.append(contentsOf: [p.0, p.1]) }
            }

        case "clip.remove":
            let ids = try resolveClipIDArray(op["clips"] ?? op["clip"])
            let ripple = (op["ripple"] as? Bool) ?? false
            try Operations.removeClips(&proj, ids: Set(ids), ripple: ripple)

        case "clip.duplicate":
            let ids = try resolveClipIDArray(op["clips"] ?? op["clip"])
            let dup = try Operations.duplicateClips(&proj, ids: ids)
            createdClips.append(contentsOf: dup)

        case "clip.fades":
            let id = try resolveClipID(op["clip"])
            let shape = (op["shape"] as? String).flatMap(FadeShape.init(rawValue:))
            try Operations.setFade(
                &proj,
                id: id,
                fadeIn: num(op["fadeIn"]),
                fadeOut: num(op["fadeOut"]),
                shape: shape
            )

        case "clip.gain":
            let id = try resolveClipID(op["clip"])
            guard let db = num(op["db"] ?? op["gainDB"]) else { throw EditError.invalidArg("clip.gain requires 'db'") }
            try Operations.setClipGain(&proj, id: id, gainDB: db)

        case "clip.normalize":
            let id = try resolveClipID(op["clip"])
            guard let (ti, ci) = proj.clipLocation(of: id) else { throw EditError.clipNotFound }
            let clip = proj.tracks[ti].clips[ci]
            let targetDB = num(op["targetDB"]) ?? -0.1
            let url = model.resolvedURL(for: clip.path)
            if let pcm = model.waveforms.loadPCM(for: url) {
                let db = AudioAnalysis.normalizationGainDB(for: clip, in: pcm, targetPeakDB: targetDB)
                try Operations.setClipGain(&proj, id: id, gainDB: db)
            }

        case "clip.reverse":
            let id = try resolveClipID(op["clip"])
            guard let (ti, ci) = proj.clipLocation(of: id) else { throw EditError.clipNotFound }
            let rev = (op["reversed"] as? Bool) ?? !proj.tracks[ti].clips[ci].reversed
            try Operations.setClipReversed(&proj, id: id, reversed: rev)

        case "clip.mute":
            let id = try resolveClipID(op["clip"])
            let mute = (op["mute"] as? Bool) ?? true
            try Operations.setClipMute(&proj, id: id, mute: mute)

        case "clip.crossfade":
            let idA = try resolveClipID(op["clipA"])
            let idB = try resolveClipID(op["clipB"])
            let dur = num(op["duration"]) ?? 0.5
            try Operations.crossfade(&proj, clipA: idA, clipB: idB, duration: dur)

        case "range.copy":
            let range = try parseRange(op)
            model.clipboard = Operations.extractSlices(from: proj, in: range)

        case "range.cut":
            let range = try parseRange(op)
            let ripple = (op["ripple"] as? Bool) ?? false
            model.clipboard = Operations.extractSlices(from: proj, in: range)
            try Operations.deleteRange(&proj, in: range, ripple: ripple)

        case "range.paste":
            let at = num(op["at"]) ?? model.playhead
            let trackID = try op["track"].map { try resolveTrackID($0, in: proj) }
            let ripple = (op["ripple"] as? Bool) ?? false
            let pasted = try Operations.paste(&proj, slices: model.clipboard, at: at, targetTrackID: trackID, ripple: ripple)
            createdClips.append(contentsOf: pasted)

        case "range.delete":
            let range = try parseRange(op)
            let ripple = (op["ripple"] as? Bool) ?? false
            try Operations.deleteRange(&proj, in: range, ripple: ripple)

        case "range.crop":
            let range = try parseRange(op)
            try Operations.cropToRange(&proj, in: range)

        case "range.silence":
            let range = try parseRange(op)
            try Operations.silenceRange(&proj, in: range)

        case "range.fadeIn":
            let range = try parseRange(op)
            let shape = (op["shape"] as? String).flatMap(FadeShape.init(rawValue:)) ?? .cosine
            try Operations.fadeInRange(&proj, in: range, shape: shape)

        case "range.fadeOut":
            let range = try parseRange(op)
            let shape = (op["shape"] as? String).flatMap(FadeShape.init(rawValue:)) ?? .cosine
            try Operations.fadeOutRange(&proj, in: range, shape: shape)

        case "marker.add":
            guard let t = num(op["time"]) else { throw EditError.invalidArg("marker.add requires 'time'") }
            let name = (op["name"] as? String) ?? "M\(proj.markers.count + 1)"
            _ = Operations.addMarker(&proj, time: t, name: name)

        case "marker.remove":
            if let idx = int(op["marker"]), idx >= 0, idx < proj.markers.count {
                try Operations.removeMarker(&proj, id: proj.markers[idx].id)
            } else if let s = op["marker"] as? String, let uuid = UUID(uuidString: s) {
                try Operations.removeMarker(&proj, id: uuid)
            } else {
                throw EditError.markerNotFound
            }

        case "master.gain":
            guard let db = num(op["db"]) else { throw EditError.invalidArg("master.gain requires 'db'") }
            proj.masterGainDB = min(max(db, -60), 24)

        default:
            throw EditError.invalidArg("Unknown operation '\(kind)'")
        }
    }

    // MARK: Export, Transport, Select

    private static func handleExport(_ req: HTTPRequest, model: AppModel) -> HTTPResponse {
        guard let body = jsonObject(req.body),
              let rawPath = body["path"] as? String, !rawPath.isEmpty else {
            return .error(400, "Missing 'path'")
        }
        let dest = URL(fileURLWithPath: (rawPath as NSString).expandingTildeInPath)
        let ext = dest.pathExtension.lowercased()
        let format = (body["format"] as? String).flatMap(ExportFormat.init(rawValue:))
            ?? ExportFormat(rawValue: ext)
            ?? .wav
        let sampleRate = num(body["sampleRate"]) ?? model.store.project.sampleRate
        let bitDepth = int(body["bitDepth"]).flatMap(ExportBitDepth.init(rawValue:)) ?? .int24
        let bitRate = int(body["bitRateKbps"]) ?? 256
        let channels = int(body["channels"]) ?? 2
        let norm = (body["normalization"] as? String)?.lowercased() ?? "none"
        let stems = (body["stems"] as? Bool) ?? false

        var exportRange: ClosedRange<Double>?
        if let arr = body["range"] as? [Any], arr.count == 2,
           let a = num(arr[0]), let b = num(arr[1]), b > a {
            exportRange = a...b
        }

        do {
            if stems {
                let dir = dest.hasDirectoryPath ? dest : dest.deletingLastPathComponent()
                let urls = try AudioExporter.exportStems(
                    project: model.store.project,
                    waveforms: model.waveforms,
                    directory: dir,
                    format: format,
                    sampleRate: sampleRate,
                    bitDepth: bitDepth,
                    range: exportRange,
                    baseURL: model.store.url
                )
                return .json([
                    "ok": true,
                    "stems": urls.map(\.path),
                    "format": format.rawValue,
                ])
            } else {
                let opts = ExportOptions(
                    format: format,
                    sampleRate: sampleRate,
                    bitDepth: bitDepth,
                    bitRateKbps: bitRate,
                    channels: channels,
                    range: exportRange,
                    normalizePeak: norm == "peak",
                    targetPeakDB: -0.1,
                    normalizeLUFS: norm == "lufs",
                    targetLUFS: -14.0
                )
                let res = try AudioExporter.export(
                    project: model.store.project,
                    waveforms: model.waveforms,
                    to: dest,
                    options: opts,
                    baseURL: model.store.url
                )
                return .json([
                    "ok": true,
                    "path": res.url.path,
                    "format": res.format.rawValue,
                    "duration": res.duration,
                    "sampleRate": res.sampleRate,
                    "channels": res.channels,
                    "peakDB": res.peakDB,
                    "integratedLUFS": res.integratedLUFS,
                    "appliedGainDB": res.appliedGainDB,
                ])
            }
        } catch {
            return .error(500, "Export failed: \(error.localizedDescription)")
        }
    }

    private static func handleTransport(_ req: HTTPRequest, model: AppModel) -> HTTPResponse {
        guard let body = jsonObject(req.body),
              let action = body["action"] as? String else {
            return .error(400, "Missing 'action'")
        }
        switch action {
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
            if let t = num(body["time"]) {
                model.seek(to: t)
            }
        case "loop":
            if let arr = body["range"] as? [Any], arr.count == 2,
               let a = num(arr[0]), let b = num(arr[1]), b > a {
                model.store.perform("Définir la boucle") { proj in
                    proj.loopRange = a...b
                }
            } else {
                model.toggleLoop()
            }
        case "loopOff":
            model.store.perform("Désactiver la boucle") { proj in
                proj.loopRange = nil
            }
        default:
            return .error(400, "Unknown transport action: \(action)")
        }
        return .json(stateDict(model: model))
    }

    private static func handleSelect(_ req: HTTPRequest, model: AppModel) -> HTTPResponse {
        let body = jsonObject(req.body) ?? [:]
        if let clips = body["clips"] as? [String] {
            model.selectedClips = Set(clips.compactMap(UUID.init(uuidString:)))
        }
        if let trackIdx = int(body["track"]),
           trackIdx >= 0,
           trackIdx < model.store.project.tracks.count {
            model.selectedTrackID = model.store.project.tracks[trackIdx].id
        }
        if let arr = body["range"] as? [Any] {
            if arr.count == 2, let a = num(arr[0]), let b = num(arr[1]), b > a {
                model.selectionRange = a...b
            } else {
                model.selectionRange = nil
            }
        }
        return .json(stateDict(model: model))
    }

    // MARK: Helpers

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        guard !data.isEmpty else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func num(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }

    private static func int(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s) }
        return nil
    }

    private static func resolveTrackID(_ any: Any?, in proj: AudioProject) throws -> UUID {
        if let idx = int(any), idx >= 0, idx < proj.tracks.count {
            return proj.tracks[idx].id
        }
        if let s = any as? String, let uuid = UUID(uuidString: s), proj.trackIndex(of: uuid) != nil {
            return uuid
        }
        throw EditError.trackNotFound
    }

    private static func resolveClipID(_ any: Any?) throws -> UUID {
        if let s = any as? String, let uuid = UUID(uuidString: s) {
            return uuid
        }
        throw EditError.clipNotFound
    }

    private static func resolveClipIDArray(_ any: Any?) throws -> [UUID] {
        if let s = any as? String, let uuid = UUID(uuidString: s) {
            return [uuid]
        }
        if let arr = any as? [String] {
            return arr.compactMap(UUID.init(uuidString:))
        }
        throw EditError.clipNotFound
    }

    private static func parseRange(_ op: [String: Any]) throws -> ClosedRange<Double> {
        guard let start = num(op["start"]), let end = num(op["end"]), end > start else {
            throw EditError.emptyRange
        }
        return max(0, start)...end
    }

    private static func downsample(wave: Waveform, count: Int) -> (peaks: [Float], rms: [Float]) {
        guard !wave.peaks.isEmpty else { return ([], []) }
        let total = wave.peaks.count
        if total <= count {
            return (wave.peaks, wave.rms)
        }
        var outPeaks: [Float] = []
        var outRMS: [Float] = []
        outPeaks.reserveCapacity(count)
        outRMS.reserveCapacity(count)
        for b in 0..<count {
            let i0 = (b * total) / count
            let i1 = max(i0 + 1, min(((b + 1) * total) / count, total))
            var pMax: Float = 0
            var rSum: Float = 0
            for i in i0..<i1 {
                if wave.peaks[i] > pMax { pMax = wave.peaks[i] }
                if i < wave.rms.count { rSum += wave.rms[i] }
            }
            outPeaks.append(pMax)
            outRMS.append(rSum / Float(i1 - i0))
        }
        return (outPeaks, outRMS)
    }
}
