import AppKit
import AudioToolbox
import AVFoundation
import Foundation
import Observation
import SimpleAudioCore
import SimpleAudioEngine
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
    enum Action {
        case togglePlay
        case rewind
        case stop
        case toggleLoop
        case stepBackward
        case stepForward
        case split
        case duplicateSelection
        case deleteSelection
        case rippleDeleteSelection
        case copy
        case cut
        case paste
        case cropToSelection
        case silenceSelection
        case fadeInQuick
        case fadeOutQuick
        case crossfadeSelection
        case normalizeSelection
        case reverseSelection
        case toggleMute
        case setIn
        case setOut
        case clearSelectionRange
        case trimStartToPlayhead
        case trimEndToPlayhead
        case addTrack
        case duplicateTrack
        case deleteTrack
        case addMarker
        case selectAll
        case deselectAll
        case zoomToFit
        case zoomToSelection
        case zoomIn
        case zoomOut
        case toggleSnapping
    }

    let store: DocumentStore
    let engine = PlaybackEngine()
    var playback: PlaybackEngine { engine }
    let waveforms = WaveformCache.shared

    var selectedClips: Set<UUID> = []
    var selectedTrackID: UUID?
    var selectedMarkerID: UUID?
    /// Active time range (`In...Out`) for range-based editing (copy, cut, delete, crop, fade, silence, loop).
    var selectionRange: ClosedRange<Double>?
    var clipboard: [ClipboardSlice] = []
    var snapping = true
    var inspectorVisible = true
    var sidebarVisible = true
    var showExport = false
    var errorMessage: String?
    var statusFlash: String?
    var statusMessage: String = "Prêt"

    var apiPort: UInt16 = 17910
    var apiListening: Bool = false
    var oscInputPort: UInt16 = 9110
    var oscListening: Bool = false
    var oscFeedbackEnabled: Bool = false
    var oscOutputHost: String = "127.0.0.1"
    var oscOutputPort: UInt16 = 9111

    var showSidebar: Bool {
        get { sidebarVisible }
        set { sidebarVisible = newValue }
    }
    var showInspector: Bool {
        get { inspectorVisible }
        set { inspectorVisible = newValue }
    }
    var showExportSheet: Bool {
        get { showExport }
        set { showExport = newValue }
    }
    var peakLeft: Float { engine.meterLeft }
    var peakRight: Float { engine.meterRight }
    var primarySelectedClip: AudioClip? { selectedClipObjects.first }
    var selectedTrack: AudioTrack? { activeTrack }

    @ObservationIgnored weak var mainWindow: NSWindow?
    @ObservationIgnored weak var timelineView: TimelineView?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var flashTask: Task<Void, Never>?
    @ObservationIgnored private(set) var lastVisualUpdate = Date()

    static let audioExtensions: Set<String> = [
        "wav", "aif", "aiff", "caf", "flac", "m4a", "mp3", "aac", "alac", "ogg", "opus", "mp4", "mov", "wma",
    ]
    static let projectExtensions: Set<String> = ["simpleaudio", "saudio", "json"]

    init(store: DocumentStore? = nil) {
        let resolvedStore = store ?? DocumentStore()
        self.store = resolvedStore
        self.selectedTrackID = resolvedStore.project.tracks.first?.id
        waveforms.onUpdate = { [weak self] in
            guard let self else { return }
            self.lastVisualUpdate = Date()
            self.syncDecodedDurations()
            self.engine.update(project: self.store.project, projectURL: self.store.url)
            self.timelineView?.needsDisplay = true
        }
        engine.onTime = { [weak self] t in
            guard let self else { return }
            self.timelineView?.updatePlayhead(t)
        }
        observeStore()
    }

    var project: AudioProject { store.project }
    var hasDocument: Bool { !project.tracks.isEmpty || store.url != nil }
    var playhead: Double { engine.currentTime }
    var transportPlaying: Bool { engine.isPlaying }
    var totalDuration: Double { project.totalDuration }

    var documentName: String {
        guard let url = store.url else { return "SimpleAudio" }
        return url.deletingPathExtension().lastPathComponent
    }

    var documentTitle: String {
        guard let url = store.url else { return "SimpleAudio" }
        let suffix = store.isDirty ? " — modifié" : ""
        return url.lastPathComponent + suffix
    }

    var selectedClipObjects: [AudioClip] {
        project.allClips.map(\.clip).filter { selectedClips.contains($0.id) }
    }

    var activeTrack: AudioTrack? {
        if let id = selectedTrackID, let i = project.trackIndex(of: id) {
            return project.tracks[i]
        }
        if let firstClipID = selectedClips.first, let (ti, _) = project.clipLocation(of: firstClipID) {
            return project.tracks[ti]
        }
        return project.tracks.first
    }

    private func observeStore() {
        withObservationTracking {
            _ = store.changeCount
            _ = store.url
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.engine.loopRange = self.store.project.loopRange
                self.engine.update(project: self.store.project, projectURL: self.store.url)
                self.preloadProjectWaveforms()
                self.timelineView?.modelChanged()
                self.observeStore()
            }
        }
    }

    // MARK: Document Lifecycle

    func newProject() {
        guard confirmDiscardIfDirty() else { return }
        engine.stop()
        var p = AudioProject()
        let tID = p.addTrack(name: "Piste 1")
        store.replace(project: p, url: nil, isProjectFile: true)
        selectedClips.removeAll()
        selectedTrackID = tID
        selectedMarkerID = nil
        selectionRange = nil
        engine.seek(to: 0)
        timelineView?.fit()
    }

    func chooseOpen() {
        guard confirmDiscardIfDirty() else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Ouvrir un fichier audio ou un projet SimpleAudio"
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            openURLs(panel.urls)
        }
    }

    func chooseImport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Importer des fichiers audio dans le projet"
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            for url in panel.urls {
                _ = try? importAudio(url: url, toTrackIndex: nil, at: 0)
            }
        }
    }

    func requestOpen(_ url: URL) {
        guard confirmDiscardIfDirty() else { return }
        open(url)
    }

    func openURLs(_ urls: [URL]) {
        guard let first = urls.first else { return }
        if urls.count == 1 {
            open(first)
            return
        }
        guard confirmDiscardIfDirty() else { return }
        open(first)
        for extra in urls.dropFirst() {
            _ = try? importAudio(url: extra, toTrackIndex: nil, at: 0)
        }
        timelineView?.fit()
    }

    func open(_ url: URL) {
        let standardized = url.standardizedFileURL
        let ext = standardized.pathExtension.lowercased()
        engine.stop()
        errorMessage = nil

        if Self.projectExtensions.contains(ext) {
            do {
                let data = try Data(contentsOf: standardized)
                let decoded = try DocumentStore.decode(data)
                store.replace(project: decoded, url: standardized, isProjectFile: true)
                selectedClips.removeAll()
                selectedTrackID = decoded.tracks.first?.id
                selectedMarkerID = nil
                selectionRange = nil
                preloadProjectWaveforms(sync: true)
                engine.loopRange = decoded.loopRange
                engine.update(project: store.project, projectURL: store.url)
                engine.seek(to: 0)
                timelineView?.fit()
            } catch {
                errorMessage = "Impossible d'ouvrir \(standardized.lastPathComponent) : \(error.localizedDescription)"
            }
            return
        }

        // Open an audio file directly as a single-track project ready to edit
        guard let wave = waveforms.preloadSync(standardized), wave.duration > 0 else {
            errorMessage = "Impossible de décoder le fichier audio \(standardized.lastPathComponent)"
            return
        }
        let clip = AudioClip(
            name: standardized.deletingPathExtension().lastPathComponent,
            path: standardized.path,
            offset: 0,
            sourceStart: 0,
            duration: wave.duration,
            sourceDuration: wave.duration
        )
        let track = AudioTrack(
            name: standardized.deletingPathExtension().lastPathComponent,
            colorIndex: 0,
            stereoSplit: wave.channelCount >= 2,
            clips: [clip]
        )
        let proj = AudioProject(
            sampleRate: wave.sampleRate > 0 ? wave.sampleRate : 48_000,
            tracks: [track]
        )
        store.replace(project: proj, url: standardized, isProjectFile: false)
        selectedClips = [clip.id]
        selectedTrackID = track.id
        selectedMarkerID = nil
        selectionRange = nil
        engine.loopRange = nil
        engine.update(project: store.project, projectURL: store.url)
        engine.seek(to: 0)
        timelineView?.fit()
    }

    /// Imports an audio file onto track `toTrackIndex` (or a new track when nil) starting at `offset`.
    @discardableResult
    func importAudio(url: URL, toTrackIndex: Int? = nil, at offset: Double = 0) throws -> UUID {
        let standardized = url.standardizedFileURL
        guard let wave = waveforms.preloadSync(standardized), wave.duration > 0 else {
            throw WaveformCache.DecodeError.unreadable(standardized)
        }
        let storedPath = store.isProjectFile ? AudioProject.storedPath(for: standardized, relativeTo: store.url) : standardized.path
        let clip = AudioClip(
            name: standardized.deletingPathExtension().lastPathComponent,
            path: storedPath,
            offset: max(0, offset),
            sourceStart: 0,
            duration: wave.duration,
            sourceDuration: wave.duration
        )
        store.perform("Importer \(clip.name)") { proj in
            let targetTrackID: UUID
            if let idx = toTrackIndex, proj.tracks.indices.contains(idx) {
                targetTrackID = proj.tracks[idx].id
            } else {
                targetTrackID = proj.addTrack(name: clip.name)
                if let ti = proj.trackIndex(of: targetTrackID) {
                    proj.tracks[ti].stereoSplit = wave.channelCount >= 2 && proj.tracks.count == 1
                }
            }
            proj.addClip(clip, toTrack: targetTrackID)
        }
        selectedClips = [clip.id]
        if let (ti, _) = project.clipLocation(of: clip.id) {
            selectedTrackID = project.tracks[ti].id
        }
        engine.update(project: store.project, projectURL: store.url)
        return clip.id
    }

    func save() {
        if let url = store.url, store.isProjectFile {
            saveProject(to: url)
        } else if let url = store.url, !store.isProjectFile, project.tracks.count == 1 {
            // Opened a single audio file directly: if it's a native format, export directly back or save project
            let ext = url.pathExtension.lowercased()
            if let format = AudioExportFormat.allCases.first(where: { $0.fileExtension == ext || (ext == "aif" && $0 == .aiff) }) {
                do {
                    let opts = AudioExportOptions(format: format, sampleRate: project.sampleRate, bitDepth: 24, channels: 2)
                    _ = try AudioExporter.export(project: project, projectURL: store.url, to: url, options: opts)
                    waveforms.invalidate(url)
                    _ = waveforms.preloadSync(url)
                    store.markSaved(at: url, isProjectFile: false)
                    flash("enregistré")
                    return
                } catch {
                    // Fall through to Save As project if in-place overwrite fails
                }
            }
            saveAs()
        } else {
            saveAs()
        }
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "simpleaudio") ?? .json]
        panel.nameFieldStringValue = (store.url?.deletingPathExtension().lastPathComponent ?? "Projet") + ".simpleaudio"
        if panel.runModal() == .OK, let url = panel.url {
            saveProject(to: url)
        }
    }

    func saveProject(to url: URL) {
        do {
            // Relativize clip paths against the new project location
            var proj = store.project
            for ti in proj.tracks.indices {
                for ci in proj.tracks[ti].clips.indices {
                    let resolved = AudioProject.resolve(proj.tracks[ti].clips[ci].path, relativeTo: store.url)
                    proj.tracks[ti].clips[ci].path = AudioProject.storedPath(for: resolved, relativeTo: url)
                }
            }
            let data = try DocumentStore.encode(proj)
            try data.write(to: url, options: .atomic)
            store.markSaved(at: url, isProjectFile: true)
            flash("enregistré")
        } catch {
            errorMessage = "Impossible d'enregistrer : \(error.localizedDescription)"
        }
    }

    func revert() {
        guard let url = store.url else { return }
        open(url)
        flash("rétabli")
    }

    func confirmDiscardIfDirty() -> Bool {
        let isAutomated = CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--snapshot")
        guard store.isDirty, !isAutomated else { return true }
        let alert = NSAlert()
        alert.messageText = "Enregistrer les modifications apportées à « \(documentName) » ?"
        alert.informativeText = "Les modifications non enregistrées seront perdues."
        alert.addButton(withTitle: "Enregistrer")
        alert.addButton(withTitle: "Ne pas enregistrer")
        alert.addButton(withTitle: "Annuler")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            save()
            return !store.isDirty
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    // MARK: Undo / Redo

    func undo() {
        store.undo()
        pruneSelection()
    }

    func redo() {
        store.redo()
        pruneSelection()
    }

    private func pruneSelection() {
        let validClips = Set(project.allClips.map(\.clip.id))
        selectedClips = selectedClips.intersection(validClips)
        if let tID = selectedTrackID, project.trackIndex(of: tID) == nil {
            selectedTrackID = project.tracks.first?.id
        }
    }

    // MARK: Actions

    func perform(_ action: Action) {
        switch action {
        case .togglePlay:
            engine.togglePlay()
        case .rewind:
            engine.rewind()
        case .stop:
            engine.stop()
        case .toggleLoop:
            if project.loopRange != nil {
                store.perform("Désactiver la boucle") { $0.loopRange = nil }
            } else if let range = selectionRange, range.upperBound > range.lowerBound + 0.02 {
                store.perform("Boucle sur la plage") { $0.loopRange = range }
            } else if let clip = selectedClipObjects.first {
                store.perform("Boucle sur le clip") { $0.loopRange = clip.offset...clip.end }
            } else if totalDuration > 0.05 {
                store.perform("Boucle") { $0.loopRange = 0...totalDuration }
            }
        case .stepBackward:
            engine.seek(to: max(0, playhead - 0.05))
        case .stepForward:
            engine.seek(to: min(totalDuration, playhead + 0.05))
        case .split:
            if let range = selectionRange, range.upperBound > range.lowerBound + 0.01 {
                store.perform("Couper aux bornes") {
                    _ = $0.splitAt(time: range.lowerBound, trackIDs: targetTrackIDs)
                    _ = $0.splitAt(time: range.upperBound, trackIDs: targetTrackIDs)
                }
            } else {
                let t = playhead
                var created: [UUID] = []
                store.perform("Couper le clip") {
                    created = $0.splitAt(time: t, clipIDs: selectedClips.isEmpty ? nil : selectedClips, trackIDs: targetTrackIDs)
                }
                if !created.isEmpty { selectedClips = Set(created) }
                else { flash("aucun clip sous la tête de lecture") }
            }
        case .duplicateSelection:
            if let range = selectionRange, range.upperBound > range.lowerBound + 0.01 {
                let slices = project.extractSlices(in: range, trackIDs: targetTrackIDs)
                guard !slices.isEmpty else { return }
                var pasted: [UUID] = []
                store.perform("Dupliquer la plage") {
                    pasted = $0.paste(slices, at: range.upperBound, targetTrackID: selectedTrackID, insertRipple: true)
                }
                selectedClips = Set(pasted)
            } else if !selectedClips.isEmpty {
                var newIDs: [UUID] = []
                store.perform("Dupliquer") { newIDs = $0.duplicateClips(selectedClips) }
                if !newIDs.isEmpty { selectedClips = Set(newIDs) }
            }
        case .deleteSelection:
            if let range = selectionRange, range.upperBound > range.lowerBound + 0.005 {
                store.perform("Supprimer la plage") {
                    $0.deleteRange(range, trackIDs: targetTrackIDs, ripple: false)
                }
                selectionRange = nil
            } else if !selectedClips.isEmpty {
                let ids = selectedClips
                store.perform("Supprimer") { $0.removeClips(ids, ripple: false) }
                selectedClips.removeAll()
            } else if let mID = selectedMarkerID {
                store.perform("Supprimer le marqueur") { $0.removeMarker(mID) }
                selectedMarkerID = nil
            }
        case .rippleDeleteSelection:
            if let range = selectionRange, range.upperBound > range.lowerBound + 0.005 {
                let start = range.lowerBound
                store.perform("Supprimer et raccorder") {
                    $0.deleteRange(range, trackIDs: targetTrackIDs, ripple: true)
                }
                selectionRange = nil
                engine.seek(to: start)
            } else if !selectedClips.isEmpty {
                let ids = selectedClips
                store.perform("Supprimer et raccorder") { $0.removeClips(ids, ripple: true) }
                selectedClips.removeAll()
            }
        case .copy:
            copySelection()
        case .cut:
            cutSelection()
        case .paste:
            pasteClipboard()
        case .cropToSelection:
            guard let range = selectionRange, range.upperBound > range.lowerBound + 0.005 else {
                flash("sélectionner une plage (I / O)")
                return
            }
            store.perform("Rogner sur la plage") {
                $0.cropToRange(range, trackIDs: nil)
            }
            selectionRange = nil
            engine.seek(to: 0)
            timelineView?.fit()
        case .silenceSelection:
            guard let range = selectionRange, range.upperBound > range.lowerBound + 0.005 else {
                flash("sélectionner une plage")
                return
            }
            store.perform("Silence sur la plage") {
                $0.silenceRange(range, trackIDs: targetTrackIDs)
            }
        case .fadeInQuick:
            if let range = selectionRange, range.upperBound > range.lowerBound + 0.005 {
                store.perform("Fondu d'entrée") {
                    $0.fadeInRange(range, trackIDs: targetTrackIDs)
                }
            } else {
                let ids = targetClipIDs
                guard !ids.isEmpty else { flash("sélectionner un clip ou une plage"); return }
                store.perform("Fondu d'entrée") { proj in
                    for id in ids {
                        if let c = proj.clip(id: id) {
                            let dur = c.fadeIn > 0.01 ? 0 : min(0.5, c.duration * 0.35)
                            proj.setClipFades(id: id, fadeIn: dur)
                        }
                    }
                }
            }
        case .fadeOutQuick:
            if let range = selectionRange, range.upperBound > range.lowerBound + 0.005 {
                store.perform("Fondu de sortie") {
                    $0.fadeOutRange(range, trackIDs: targetTrackIDs)
                }
            } else {
                let ids = targetClipIDs
                guard !ids.isEmpty else { flash("sélectionner un clip ou une plage"); return }
                store.perform("Fondu de sortie") { proj in
                    for id in ids {
                        if let c = proj.clip(id: id) {
                            let dur = c.fadeOut > 0.01 ? 0 : min(0.5, c.duration * 0.35)
                            proj.setClipFades(id: id, fadeOut: dur)
                        }
                    }
                }
            }
        case .crossfadeSelection:
            let clips = selectedClipObjects.sorted { $0.offset < $1.offset }
            if clips.count >= 2 {
                store.perform("Fondu enchaîné") { proj in
                    for i in 0..<(clips.count - 1) {
                        proj.crossfade(clipA: clips[i].id, clipB: clips[i + 1].id, duration: 0.25)
                    }
                }
            } else {
                flash("sélectionner 2 clips consécutifs")
            }
        case .normalizeSelection:
            let ids = targetClipIDs
            guard !ids.isEmpty else { flash("sélectionner un clip"); return }
            store.perform("Normaliser") { proj in
                for id in ids {
                    guard let c = proj.clip(id: id) else { continue }
                    let url = AudioProject.resolve(c.path, relativeTo: store.url)
                    if let pcm = try? PCMStore.shared.loadSync(url) {
                        let db = AudioAnalysis.normalizedGainDB(in: pcm, sourceStart: c.sourceStart, duration: c.duration)
                        proj.setClipGain(id: id, db: db)
                    }
                }
            }
        case .reverseSelection:
            let ids = targetClipIDs
            guard !ids.isEmpty else { flash("sélectionner un clip"); return }
            store.perform("Inverser le sens") { proj in
                for id in ids {
                    if let c = proj.clip(id: id) {
                        proj.setClipReversed(id: id, !c.reversed)
                    }
                }
            }
        case .toggleMute:
            let ids = targetClipIDs
            if !ids.isEmpty {
                let allMuted = ids.compactMap { project.clip(id: $0) }.allSatisfy(\.mute)
                store.perform("Muet") { proj in
                    for id in ids { proj.setClipMute(id: id, !allMuted) }
                }
            } else if let t = activeTrack {
                store.perform("Muet piste") { $0.setTrack(t.id, mute: !t.mute) }
            }
        case .setIn:
            let t = playhead
            let hi = max(selectionRange?.upperBound ?? max(totalDuration, t + 1.0), t + 0.05)
            selectionRange = t...hi
            timelineView?.needsDisplay = true
        case .setOut:
            let t = playhead
            let lo = min(selectionRange?.lowerBound ?? 0, max(0, t - 0.05))
            if t > lo + 0.01 {
                selectionRange = lo...t
                timelineView?.needsDisplay = true
            }
        case .clearSelectionRange:
            selectionRange = nil
            timelineView?.needsDisplay = true
        case .trimStartToPlayhead:
            let t = playhead
            let ids = targetClipIDs
            store.perform("Début au point de lecture") { proj in
                for id in ids { proj.trimClipStart(id: id, to: t) }
            }
        case .trimEndToPlayhead:
            let t = playhead
            let ids = targetClipIDs
            store.perform("Fin au point de lecture") { proj in
                for id in ids { proj.trimClipEnd(id: id, to: t) }
            }
        case .addTrack:
            var newID: UUID?
            store.perform("Ajouter une piste") { newID = $0.addTrack() }
            if let newID { selectedTrackID = newID }
        case .duplicateTrack:
            guard let t = activeTrack else { return }
            var newID: UUID?
            store.perform("Dupliquer la piste") { newID = $0.duplicateTrack(t.id) }
            if let newID { selectedTrackID = newID }
        case .deleteTrack:
            guard let t = activeTrack else { return }
            store.perform("Supprimer la piste") { $0.removeTrack(t.id) }
            selectedTrackID = project.tracks.first?.id
        case .addMarker:
            let t = playhead
            var mID: UUID?
            store.perform("Ajouter un marqueur") { mID = $0.addMarker(at: t) }
            selectedMarkerID = mID
        case .selectAll:
            selectedClips = Set(project.allClips.map(\.clip.id))
            if totalDuration > 0 { selectionRange = 0...totalDuration }
            timelineView?.needsDisplay = true
        case .deselectAll:
            selectedClips.removeAll()
            selectionRange = nil
            selectedMarkerID = nil
            timelineView?.needsDisplay = true
        case .zoomToFit:
            timelineView?.fit()
        case .zoomToSelection:
            if let range = selectionRange, range.upperBound > range.lowerBound + 0.01 {
                timelineView?.zoom(toRange: range)
            } else if let c = selectedClipObjects.first {
                timelineView?.zoom(toRange: c.offset...c.end)
            } else {
                timelineView?.fit()
            }
        case .zoomIn:
            timelineView?.zoom(by: 1.4, at: timelineView?.x(for: playhead) ?? 300)
        case .zoomOut:
            timelineView?.zoom(by: 1.0 / 1.4, at: timelineView?.x(for: playhead) ?? 300)
        case .toggleSnapping:
            snapping.toggle()
            timelineView?.needsDisplay = true
        }
    }

    private var targetTrackIDs: Set<UUID>? {
        if let id = selectedTrackID { return [id] }
        return nil
    }

    private var targetClipIDs: Set<UUID> {
        if !selectedClips.isEmpty { return selectedClips }
        // Fall back to clip under playhead
        let t = playhead
        let under = project.allClips.filter { $0.clip.offset <= t && $0.clip.end >= t }.map(\.clip.id)
        if !under.isEmpty { return Set(under) }
        if project.clipCount == 1, let only = project.allClips.first?.clip.id { return [only] }
        return []
    }

    // MARK: Copy / Cut / Paste

    static let pasteboardType = NSPasteboard.PasteboardType("net.cieadrienm.simpleaudio.slices")

    func copySelection() {
        let slices: [ClipboardSlice]
        if let range = selectionRange, range.upperBound > range.lowerBound + 0.005 {
            slices = project.extractSlices(in: range, trackIDs: targetTrackIDs)
        } else if !selectedClips.isEmpty {
            slices = project.extractClips(selectedClips)
        } else if project.clipCount == 1, let only = project.allClips.first?.clip.id {
            slices = project.extractClips([only])
        } else {
            flash("rien à copier")
            return
        }
        guard !slices.isEmpty else { flash("plage vide"); return }
        clipboard = slices
        if let data = try? JSONEncoder().encode(slices) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(data, forType: Self.pasteboardType)
        }
        flash("\(slices.count) extrait\(slices.count > 1 ? "s" : "") copié\(slices.count > 1 ? "s" : "")")
    }

    func cutSelection() {
        copySelection()
        guard !clipboard.isEmpty else { return }
        if let range = selectionRange, range.upperBound > range.lowerBound + 0.005 {
            let start = range.lowerBound
            store.perform("Couper la plage") {
                $0.deleteRange(range, trackIDs: targetTrackIDs, ripple: true)
            }
            selectionRange = nil
            engine.seek(to: start)
        } else if !selectedClips.isEmpty {
            let ids = selectedClips
            store.perform("Couper") { $0.removeClips(ids, ripple: true) }
            selectedClips.removeAll()
        }
    }

    func pasteClipboard() {
        var slices = clipboard
        if slices.isEmpty,
           let data = NSPasteboard.general.data(forType: Self.pasteboardType),
           let decoded = try? JSONDecoder().decode([ClipboardSlice].self, from: data) {
            slices = decoded
            clipboard = decoded
        }
        guard !slices.isEmpty else {
            flash("presse-papiers vide")
            return
        }
        let targetTime = selectionRange?.lowerBound ?? playhead
        var pasted: [UUID] = []
        store.perform("Coller") { proj in
            if let range = selectionRange, range.upperBound > range.lowerBound + 0.005 {
                proj.deleteRange(range, trackIDs: targetTrackIDs, ripple: true)
            }
            pasted = proj.paste(slices, at: targetTime, targetTrackID: selectedTrackID, insertRipple: true)
        }
        selectionRange = nil
        if !pasted.isEmpty {
            selectedClips = Set(pasted)
            let span = slices.map { $0.relativeOffset + $0.clip.duration }.max() ?? 0
            engine.seek(to: targetTime + span)
        }
    }

    // MARK: Direct Inspector Setters

    func setClipOffset(_ id: UUID, _ v: Double) {
        store.perform("Début du clip") { $0.setClipTiming(id: id, offset: v) }
    }

    func setClipSourceStart(_ id: UUID, _ v: Double) {
        store.perform("Point d'entrée") { $0.setClipTiming(id: id, sourceStart: v) }
    }

    func setClipDuration(_ id: UUID, _ v: Double) {
        store.perform("Durée du clip") { $0.setClipTiming(id: id, duration: v) }
    }

    func setClipGain(_ id: UUID, _ db: Double) {
        store.perform("Gain du clip") { $0.setClipGain(id: id, db: db) }
    }

    func setClipFades(_ id: UUID, fadeInMS: Double? = nil, fadeOutMS: Double? = nil, shape: FadeShape? = nil) {
        store.perform("Fondu") {
            $0.setClipFades(id: id, fadeIn: fadeInMS.map { $0 / 1000.0 }, fadeOut: fadeOutMS.map { $0 / 1000.0 }, shape: shape)
        }
    }

    func setClipReversed(_ id: UUID, _ reversed: Bool) {
        store.perform("Sens de lecture") { $0.setClipReversed(id: id, reversed) }
    }

    func setClipMute(_ id: UUID, _ mute: Bool) {
        store.perform("Muet") { $0.setClipMute(id: id, mute) }
    }

    func setTrackName(_ id: UUID, _ name: String) {
        store.perform("Nom de piste") { $0.setTrack(id, name: name) }
    }

    func setTrackGain(_ id: UUID, _ db: Double) {
        store.perform("Gain de piste") { $0.setTrack(id, gainDB: db) }
    }

    func setTrackPan(_ id: UUID, _ pan: Double) {
        store.perform("Panoramique") { $0.setTrack(id, pan: pan) }
    }

    func setTrackMute(_ id: UUID, _ mute: Bool) {
        store.perform("Muet piste") { $0.setTrack(id, mute: mute) }
    }

    func setTrackSolo(_ id: UUID, _ solo: Bool) {
        store.perform("Solo piste") { $0.setTrack(id, solo: solo) }
    }

    func setTrackStereoSplit(_ id: UUID, _ split: Bool) {
        store.perform("Affichage L/R") { $0.setTrack(id, stereoSplit: split) }
    }

    func setTrackLocked(_ id: UUID, _ locked: Bool) {
        store.perform("Verrouiller piste") { $0.setTrack(id, locked: locked) }
    }

    func setMasterGain(_ db: Double) {
        store.perform("Gain master") { $0.masterGainDB = min(max(db, -60), 24) }
    }

    func setSampleRate(_ rate: Double) {
        store.perform("Fréquence d'échantillonnage") { $0.sampleRate = rate }
    }

    // MARK: Waveforms & Helpers

    func resolvedURL(for path: String) -> URL {
        AudioProject.resolve(path, relativeTo: store.url)
    }

    func preloadProjectWaveforms(sync: Bool = false) {
        for path in project.sourcePaths {
            let url = resolvedURL(for: path)
            if sync {
                _ = waveforms.preloadSync(url)
            } else {
                _ = waveforms.envelope(for: url)
            }
        }
    }

    private func syncDecodedDurations() {
        // Waveforms are cached in WaveformCache; engine is refreshed by onUpdate.
    }

    func flash(_ message: String) {
        statusFlash = message
        statusMessage = message
        flashTask?.cancel()
        flashTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if !Task.isCancelled {
                self?.statusFlash = nil
                self?.statusMessage = "Prêt"
            }
        }
    }

    // MARK: Convenience Methods for Views, Menu, API & OSC

    func play() { engine.play() }
    func pause() { engine.pause() }
    func togglePlay() { perform(.togglePlay) }
    func stop() { perform(.stop) }
    func seek(to time: Double) { engine.seek(to: time) }
    func toggleLoop() { perform(.toggleLoop) }
    func splitAtPlayhead() { perform(.split) }
    func pasteAtPlayhead() { pasteClipboard() }
    func cropToSelection() { perform(.cropToSelection) }
    func silenceSelection() { perform(.silenceSelection) }
    func duplicateSelectedClips() { perform(.duplicateSelection) }
    func reverseSelectedClips() { perform(.reverseSelection) }
    func toggleMuteSelectedClips() { perform(.toggleMute) }
    func addTrack() { perform(.addTrack) }
    func duplicateSelectedTrack() { perform(.duplicateTrack) }
    func removeSelectedTrack() { perform(.deleteTrack) }
    func selectAll() { perform(.selectAll) }
    func openDocumentPanel() { chooseOpen() }
    func importAudioPanel() { chooseImport() }
    func openDocument(url: URL) { open(url) }
    func openAudioAsNewProject(url: URL) { open(url) }
    func saveDocument() { save() }
    func saveDocumentAs() { saveAs() }
    func loadWaveformsForCurrentProject() { preloadProjectWaveforms(sync: true) }

    func deleteSelection(ripple: Bool) {
        perform(ripple ? .rippleDeleteSelection : .deleteSelection)
    }

    func applyFadeIn(duration: Double = 0.5, shape: FadeShape? = nil) {
        if let range = selectionRange, range.upperBound > range.lowerBound + 0.005 {
            store.perform("Fondu d'entrée") {
                $0.fadeInRange(range, shape: shape, trackIDs: targetTrackIDs)
            }
        } else {
            let ids = targetClipIDs
            guard !ids.isEmpty else { return }
            store.perform("Fondu d'entrée") { proj in
                for id in ids {
                    if let c = proj.clip(id: id) {
                        proj.setClipFades(id: id, fadeIn: min(duration, c.duration * 0.5), shape: shape)
                    }
                }
            }
        }
    }

    func applyFadeOut(duration: Double = 0.5, shape: FadeShape? = nil) {
        if let range = selectionRange, range.upperBound > range.lowerBound + 0.005 {
            store.perform("Fondu de sortie") {
                $0.fadeOutRange(range, shape: shape, trackIDs: targetTrackIDs)
            }
        } else {
            let ids = targetClipIDs
            guard !ids.isEmpty else { return }
            store.perform("Fondu de sortie") { proj in
                for id in ids {
                    if let c = proj.clip(id: id) {
                        proj.setClipFades(id: id, fadeOut: min(duration, c.duration * 0.5), shape: shape)
                    }
                }
            }
        }
    }

    func normalizeSelectedClips(targetDB: Double = -0.1) {
        let ids = targetClipIDs
        guard !ids.isEmpty else { return }
        store.perform("Normaliser") { proj in
            for id in ids {
                guard let c = proj.clip(id: id) else { continue }
                let url = AudioProject.resolve(c.path, relativeTo: store.url)
                if let pcm = try? PCMStore.shared.loadSync(url) {
                    let db = AudioAnalysis.normalizedGainDB(in: pcm, sourceStart: c.sourceStart, duration: c.duration, targetPeakDB: targetDB)
                    proj.setClipGain(id: id, db: db)
                }
            }
        }
    }

    func stripSilenceOnSelected(thresholdDB: Double = -42) {
        let ids = targetClipIDs
        guard !ids.isEmpty else { return }
        store.perform("Élaguer les silences") { proj in
            for id in ids {
                guard let c = proj.clip(id: id) else { continue }
                let url = AudioProject.resolve(c.path, relativeTo: store.url)
                guard let pcm = try? PCMStore.shared.loadSync(url) else { continue }
                let silences = AudioAnalysis.detectSilences(in: pcm, thresholdDB: thresholdDB, minDuration: 0.05)
                var newSourceStart = c.sourceStart
                var newEnd = c.end
                if let leading = silences.first(where: { $0.start <= c.sourceStart + 0.02 && $0.end > c.sourceStart }) {
                    let delta = min(leading.end - c.sourceStart, c.duration - AudioClip.minDuration)
                    if delta > 0.01 {
                        newSourceStart += delta
                    }
                }
                if let trailing = silences.last(where: { $0.end >= c.sourceEnd - 0.02 && $0.start < c.sourceEnd }) {
                    let cut = min(c.sourceEnd - trailing.start, (c.duration - (newSourceStart - c.sourceStart)) - AudioClip.minDuration)
                    if cut > 0.01 {
                        newEnd -= cut
                    }
                }
                let newDuration = max(AudioClip.minDuration, newEnd - c.offset - (newSourceStart - c.sourceStart))
                proj.setClipTiming(id: id, offset: c.offset + (newSourceStart - c.sourceStart), sourceStart: newSourceStart, duration: newDuration)
            }
        }
    }

    func toggleTrackMute(_ id: UUID) {
        guard let ti = project.trackIndex(of: id) else { return }
        setTrackMute(id, !project.tracks[ti].mute)
    }

    func toggleTrackSolo(_ id: UUID) {
        guard let ti = project.trackIndex(of: id) else { return }
        setTrackSolo(id, !project.tracks[ti].solo)
    }

    func toggleTrackStereoSplit(_ id: UUID) {
        guard let ti = project.trackIndex(of: id) else { return }
        setTrackStereoSplit(id, !project.tracks[ti].stereoSplit)
    }

    func setTrackGain(_ id: UUID, gainDB: Double) {
        setTrackGain(id, gainDB)
    }

    func setTrackPan(_ id: UUID, pan: Double) {
        setTrackPan(id, pan)
    }

    func addMarkerAtPlayhead(name: String? = nil) {
        let t = playhead
        var mID: UUID?
        store.perform("Ajouter un marqueur") { mID = $0.addMarker(name: name, at: t) }
        selectedMarkerID = mID
    }

    func removeMarker(_ id: UUID) {
        store.perform("Supprimer le marqueur") { $0.removeMarker(id) }
        if selectedMarkerID == id { selectedMarkerID = nil }
    }

    func importAudioFiles(urls: [URL], at offset: Double = 0, onNewTracks: Bool = true) {
        for (i, url) in urls.enumerated() {
            let trackIdx: Int? = (!onNewTracks && !project.tracks.isEmpty) ? (selectedTrackID.flatMap { project.trackIndex(of: $0) } ?? 0) : (project.allClips.isEmpty && i == 0 && !project.tracks.isEmpty ? 0 : nil)
            _ = try? importAudio(url: url, toTrackIndex: trackIdx, at: offset)
        }
        timelineView?.fit()
    }

    func loadDemoProject() {
        let demoDir = FileManager.default.temporaryDirectory.appendingPathComponent("SimpleAudioDemo", isDirectory: true)
        if let (projURL, _) = try? SyntheticAudio.createDemoFixtures(in: demoDir) {
            open(projURL)
        }
    }

    func settle() async {
        for path in project.sourcePaths {
            let url = resolvedURL(for: path)
            _ = await waveforms.waveform(for: url)
        }
        engine.update(project: store.project, projectURL: store.url)
        timelineView?.needsDisplay = true
    }

    // MARK: Keyboard Handling

    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if let responder = event.window?.firstResponder, responder is NSTextView {
                return event
            }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        // Space -> Play / Pause
        if event.keyCode == 49, flags.isEmpty {
            perform(.togglePlay)
            return true
        }
        // Delete / Backspace (51 or 117)
        if event.keyCode == 51 || event.keyCode == 117 {
            if flags == .shift {
                perform(.rippleDeleteSelection)
                return true
            } else if flags.isEmpty {
                perform(.deleteSelection)
                return true
            }
        }
        // Escape -> clear range selection
        if event.keyCode == 53, flags.isEmpty {
            perform(.clearSelectionRange)
            return true
        }
        // Left / Right arrows
        if event.keyCode == 123, flags.isEmpty {
            perform(.stepBackward)
            return true
        }
        if event.keyCode == 124, flags.isEmpty {
            perform(.stepForward)
            return true
        }
        // Home -> Rewind
        if event.keyCode == 115, flags.isEmpty {
            perform(.rewind)
            return true
        }

        // Control+I / Control+O -> Quick Fade In / Fade Out
        if flags == .control, chars == "i" {
            perform(.fadeInQuick)
            return true
        }
        if flags == .control, chars == "o" {
            perform(.fadeOutQuick)
            return true
        }

        // Option+I / Option+O -> Clear range
        if flags == .option, chars == "i" || chars == "o" {
            perform(.clearSelectionRange)
            return true
        }

        guard flags.isEmpty else { return false }

        switch chars {
        case "b", "s":
            perform(.split)
            return true
        case "i":
            perform(.setIn)
            return true
        case "o":
            perform(.setOut)
            return true
        case "l":
            perform(.toggleLoop)
            return true
        case "m":
            perform(.toggleMute)
            return true
        case "k":
            perform(.addMarker)
            return true
        case "x":
            perform(.crossfadeSelection)
            return true
        case "f":
            perform(.zoomToFit)
            return true
        case "z":
            perform(.zoomToSelection)
            return true
        case "n":
            perform(.toggleSnapping)
            return true
        case "[":
            perform(.trimStartToPlayhead)
            return true
        case "]":
            perform(.trimEndToPlayhead)
            return true
        case "=", "+":
            perform(.zoomIn)
            return true
        case "-":
            perform(.zoomOut)
            return true
        default:
            return false
        }
    }
}
