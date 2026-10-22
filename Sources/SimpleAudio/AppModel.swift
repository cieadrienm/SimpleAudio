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
        case addMIDITrack
        case duplicateTrack
        case deleteTrack
        case moveTrackUp
        case moveTrackDown
        case togglePianoRoll
        case quantizeSelection
        case bounceMIDIToAudio
        case addMarker
        case selectAll
        case deselectAll
        case toggleZoom
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
    var selectedNotes: Set<UUID> = []
    var selectedTrackID: UUID?
    var selectedMarkerID: UUID?
    /// Active time range (`In...Out`) for range-based editing (copy, cut, delete, crop, fade, silence, loop).
    var selectionRange: ClosedRange<Double>?
    var clipboard: [ClipboardSlice] = []
    var noteClipboard: [NoteClipboardSlice] = []
    var snapping = true
    var inspectorVisible = true
    var sidebarVisible = true
    var showExport = false
    var showAbout = false
    var showHelp = false
    var showShortcuts = false
    var errorMessage: String?
    var statusFlash: String?
    var statusMessage: String = "Prêt"
    var recentFiles: [URL] = []

    private static let recentFilesDefaultsKey = "simpleaudio.recentFiles"
    private static let maxRecentFiles = 15

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
    var primarySelectedNote: MIDINote? { selectedNoteObjects.first }
    var selectedTrack: AudioTrack? { activeTrack }

    @ObservationIgnored weak var mainWindow: NSWindow?
    @ObservationIgnored weak var timelineView: TimelineView?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var flashTask: Task<Void, Never>?
    @ObservationIgnored private(set) var lastVisualUpdate = Date()

    static let audioExtensions: Set<String> = [
        "wav", "aif", "aiff", "caf", "flac", "m4a", "mp3", "aac", "alac", "ogg", "opus", "mp4", "mov", "wma",
    ]
    static let midiExtensions: Set<String> = ["mid", "midi", "smf"]
    static let soundfontExtensions: Set<String> = ["sf2", "dls"]
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
        loadRecentFiles()
        observeStore()
    }

    // MARK: Recent Files ("Ouvrir l’élément récent")

    func loadRecentFiles() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.recentFilesDefaultsKey) ?? []
        recentFiles = paths
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func recordRecentFile(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardized.path) else { return }
        // Skip internal self-test or temporary demo fixtures
        let path = standardized.path
        if path.contains("SimpleAudioSelfTest") || path.contains("SimpleAudioDemo") || path.contains("SimpleAudioBounces") {
            return
        }
        var updated = recentFiles.filter { $0.standardizedFileURL.path != path }
        updated.insert(standardized, at: 0)
        if updated.count > Self.maxRecentFiles {
            updated = Array(updated.prefix(Self.maxRecentFiles))
        }
        recentFiles = updated
        UserDefaults.standard.set(updated.map(\.path), forKey: Self.recentFilesDefaultsKey)
        if !CommandLine.arguments.contains("--self-test") && !CommandLine.arguments.contains("--snapshot") {
            NSDocumentController.shared.noteNewRecentDocumentURL(standardized)
        }
    }

    func clearRecentFiles() {
        recentFiles.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.recentFilesDefaultsKey)
        NSDocumentController.shared.clearRecentDocuments(nil)
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

    var selectedNoteObjects: [MIDINote] {
        project.allNotes.map(\.note).filter { selectedNotes.contains($0.id) }
    }

    var activeTrack: AudioTrack? {
        if let id = selectedTrackID, let i = project.trackIndex(of: id) {
            return project.tracks[i]
        }
        if let firstClipID = selectedClips.first, let (ti, _) = project.clipLocation(of: firstClipID) {
            return project.tracks[ti]
        }
        if let firstNoteID = selectedNotes.first, let (ti, _) = project.noteLocation(of: firstNoteID) {
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
        selectedNotes.removeAll()
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
        panel.message = "Ouvrir un fichier audio, MIDI (.mid) ou un projet SimpleAudio"
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            openURLs(panel.urls)
        }
    }

    func chooseImport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Importer des fichiers audio ou MIDI (.mid) dans le projet"
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            for url in panel.urls {
                let ext = url.pathExtension.lowercased()
                if Self.midiExtensions.contains(ext) {
                    _ = try? importMIDI(url: url, at: 0)
                } else if Self.soundfontExtensions.contains(ext) {
                    _ = loadSoundfont(url: url)
                } else {
                    _ = try? importAudio(url: url, toTrackIndex: nil, at: 0)
                }
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
            let ext = extra.pathExtension.lowercased()
            if Self.midiExtensions.contains(ext) {
                _ = try? importMIDI(url: extra, at: 0)
            } else if Self.soundfontExtensions.contains(ext) {
                _ = loadSoundfont(url: extra)
            } else {
                _ = try? importAudio(url: extra, toTrackIndex: nil, at: 0)
            }
        }
        timelineView?.fit()
    }

    func open(_ url: URL) {
        let standardized = url.standardizedFileURL
        let ext = standardized.pathExtension.lowercased()

        if Self.soundfontExtensions.contains(ext) {
            _ = loadSoundfont(url: standardized)
            return
        }

        engine.stop()
        errorMessage = nil

        if Self.projectExtensions.contains(ext) {
            do {
                let data = try Data(contentsOf: standardized)
                let decoded = try DocumentStore.decode(data)
                store.replace(project: decoded, url: standardized, isProjectFile: true)
                selectedClips.removeAll()
                selectedNotes.removeAll()
                selectedTrackID = decoded.tracks.first?.id
                selectedMarkerID = nil
                selectionRange = nil
                preloadProjectWaveforms(sync: true)
                engine.loopRange = decoded.loopRange
                engine.update(project: store.project, projectURL: store.url)
                engine.seek(to: 0)
                timelineView?.fit()
                recordRecentFile(standardized)
            } catch {
                errorMessage = "Impossible d'ouvrir \(standardized.lastPathComponent) : \(error.localizedDescription)"
            }
            return
        }

        if Self.midiExtensions.contains(ext) {
            do {
                let data = try Data(contentsOf: standardized)
                var decoded = try MIDIFileCodec.decode(
                    data,
                    defaultTitle: standardized.deletingPathExtension().lastPathComponent
                )
                if !decoded.tracks.isEmpty && !decoded.tracks.contains(where: \.pianoRollExpanded) {
                    decoded.tracks[0].pianoRollExpanded = true
                }
                let companionSF = SoundfontLibrary.shared.guessSoundfont(forMIDI: standardized)
                if let sf = companionSF {
                    decoded.soundfontPath = sf.path
                }
                store.replace(project: decoded, url: standardized, isProjectFile: false)
                selectedClips.removeAll()
                selectedNotes.removeAll()
                selectedTrackID = decoded.tracks.first?.id
                selectedMarkerID = nil
                selectionRange = nil
                engine.loopRange = decoded.loopRange
                engine.update(project: store.project, projectURL: store.url, soundfontURL: companionSF)
                engine.seek(to: 0)
                timelineView?.fit()
                recordRecentFile(standardized)
                flash("MIDI ouvert · \(decoded.noteCount) notes")
            } catch {
                errorMessage = "Impossible d'ouvrir le fichier MIDI \(standardized.lastPathComponent) : \(error.localizedDescription)"
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
        selectedNotes.removeAll()
        selectedTrackID = track.id
        selectedMarkerID = nil
        selectionRange = nil
        engine.loopRange = nil
        engine.update(project: store.project, projectURL: store.url)
        engine.seek(to: 0)
        timelineView?.fit()
        recordRecentFile(standardized)
    }

    /// Imports a Standard MIDI File (`.mid`) into the current project as one or more MIDI tracks.
    @discardableResult
    func importMIDI(url: URL, at offset: Double = 0) throws -> [UUID] {
        let standardized = url.standardizedFileURL
        let data = try Data(contentsOf: standardized)
        let decoded = try MIDIFileCodec.decode(
            data,
            defaultTitle: standardized.deletingPathExtension().lastPathComponent
        )
        var addedTrackIDs: [UUID] = []
        let shift = max(0, offset)
        store.perform("Importer MIDI \(standardized.deletingPathExtension().lastPathComponent)") { proj in
            if proj.tracks.isEmpty || (proj.tracks.count == 1 && proj.tracks[0].clips.isEmpty && proj.tracks[0].notes.isEmpty) {
                proj.bpm = decoded.bpm
                proj.timeSignatureNumerator = decoded.timeSignatureNumerator
                proj.timeSignatureDenominator = decoded.timeSignatureDenominator
                if proj.tracks.count == 1 && proj.tracks[0].clips.isEmpty && proj.tracks[0].notes.isEmpty {
                    proj.tracks.removeAll()
                }
            }
            for (idx, var track) in decoded.tracks.enumerated() {
                track.id = UUID()
                track.colorIndex = (proj.tracks.count + idx) % 8
                if shift > 0 {
                    for ni in track.notes.indices {
                        track.notes[ni].start += shift
                    }
                }
                if idx == 0 && !proj.tracks.contains(where: \.pianoRollExpanded) {
                    track.pianoRollExpanded = true
                }
                proj.tracks.append(track)
                addedTrackIDs.append(track.id)
            }
        }
        if let firstID = addedTrackIDs.first {
            selectedTrackID = firstID
        }
        if let sf = SoundfontLibrary.shared.guessSoundfont(forMIDI: standardized), engine.activeSoundfontURL == nil {
            _ = loadSoundfont(url: sf)
        }
        engine.update(project: store.project, projectURL: store.url)
        recordRecentFile(standardized)
        return addedTrackIDs
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
        recordRecentFile(standardized)
        return clip.id
    }

    func save() {
        if let url = store.url, store.isProjectFile {
            saveProject(to: url)
        } else if let url = store.url, !store.isProjectFile {
            let ext = url.pathExtension.lowercased()
            if Self.midiExtensions.contains(ext), !project.hasAudioTracks {
                do {
                    let data = MIDIFileCodec.encode(project)
                    try data.write(to: url, options: .atomic)
                    store.markSaved(at: url, isProjectFile: false)
                    flash("MIDI enregistré")
                    return
                } catch {
                    // Fall through to Save As
                }
            } else if project.tracks.count == 1,
                      let format = AudioExportFormat.allCases.first(where: { $0.fileExtension == ext || (ext == "aif" && $0 == .aiff) }) {
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

    func exportMIDIFilePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "mid") ?? .data]
        panel.nameFieldStringValue = "\(documentName).mid"
        panel.message = "Exporter les pistes MIDI en fichier MIDI Standard (.mid)"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = MIDIFileCodec.encode(project)
                try data.write(to: url, options: .atomic)
                flash("exporté en .mid")
            } catch {
                errorMessage = "Impossible d'exporter le MIDI : \(error.localizedDescription)"
            }
        }
    }

    func chooseSoundfontPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choisir une banque de sons SoundFont (.sf2 ou .dls)"
        if panel.runModal() == .OK, let url = panel.url {
            _ = loadSoundfont(url: url)
        }
    }

    @discardableResult
    func loadSoundfont(url: URL) -> Bool {
        let ok = engine.loadSoundfont(url)
        if ok {
            store.perform("Banque SoundFont") { $0.soundfontPath = url.path }
            flash("SoundFont : \(url.deletingPathExtension().lastPathComponent)")
        } else {
            errorMessage = "Banque SoundFont invalide : \(url.lastPathComponent)"
        }
        return ok
    }

    func clearSoundfont() {
        _ = engine.loadSoundfont(nil)
        store.perform("Banque GM par défaut") { $0.soundfontPath = nil }
        flash("Banque : \(engine.activePreset.title)")
    }

    func selectSoundPreset(_ preset: SoundPreset) {
        _ = engine.loadSoundfont(nil)
        engine.setPreset(preset)
        if store.project.soundfontPath != nil {
            store.perform("Banque de sons") { $0.soundfontPath = nil }
        }
        flash("Son : \(preset.title)")
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
            recordRecentFile(url)
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
        let validNotes = Set(project.allNotes.map(\.note.id))
        selectedNotes = selectedNotes.intersection(validNotes)
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
            } else if !selectedNoteObjects.isEmpty {
                let lo = selectedNoteObjects.map(\.start).min() ?? 0
                let hi = selectedNoteObjects.map(\.end).max() ?? 1
                store.perform("Boucle sur les notes") { $0.loopRange = lo...max(lo + 0.1, hi) }
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
                    _ = $0.splitNotes(at: range.lowerBound, trackIDs: targetTrackIDs)
                    _ = $0.splitNotes(at: range.upperBound, trackIDs: targetTrackIDs)
                }
            } else {
                let t = playhead
                var createdClips: [UUID] = []
                var createdNotes: [UUID] = []
                store.perform("Couper") {
                    createdClips = $0.splitAt(time: t, clipIDs: selectedClips.isEmpty ? nil : selectedClips, trackIDs: targetTrackIDs)
                    createdNotes = $0.splitNotes(at: t, noteIDs: selectedNotes.isEmpty ? nil : selectedNotes, trackIDs: targetTrackIDs)
                }
                if !createdClips.isEmpty { selectedClips = Set(createdClips) }
                if !createdNotes.isEmpty { selectedNotes = Set(createdNotes) }
                if createdClips.isEmpty && createdNotes.isEmpty {
                    flash("rien sous la tête de lecture")
                }
            }
        case .duplicateSelection:
            if let range = selectionRange, range.upperBound > range.lowerBound + 0.01 {
                let slices = project.extractSlices(in: range, trackIDs: targetTrackIDs)
                let noteSlices = project.extractNoteSlices(in: range, trackIDs: targetTrackIDs)
                guard !slices.isEmpty || !noteSlices.isEmpty else { return }
                var pastedClips: [UUID] = []
                var pastedNotes: [UUID] = []
                store.perform("Dupliquer la plage") {
                    if !slices.isEmpty {
                        pastedClips = $0.paste(slices, at: range.upperBound, targetTrackID: selectedTrackID, insertRipple: true)
                    }
                    if !noteSlices.isEmpty {
                        pastedNotes = $0.pasteNotes(noteSlices, at: range.upperBound, targetTrackID: selectedTrackID, insertRipple: true)
                    }
                }
                if !pastedClips.isEmpty { selectedClips = Set(pastedClips) }
                if !pastedNotes.isEmpty { selectedNotes = Set(pastedNotes) }
            } else if !selectedClips.isEmpty || !selectedNotes.isEmpty {
                var newClips: [UUID] = []
                var newNotes: [UUID] = []
                let beatShift = max(0.25, project.secondsPerBeat)
                store.perform("Dupliquer") {
                    if !selectedClips.isEmpty {
                        newClips = $0.duplicateClips(selectedClips)
                    }
                    if !selectedNotes.isEmpty {
                        newNotes = $0.duplicateNotes(selectedNotes, offsetDelta: beatShift)
                    }
                }
                if !newClips.isEmpty { selectedClips = Set(newClips) }
                if !newNotes.isEmpty { selectedNotes = Set(newNotes) }
            }
        case .deleteSelection:
            if let range = selectionRange, range.upperBound > range.lowerBound + 0.005 {
                store.perform("Supprimer la plage") {
                    $0.deleteRange(range, trackIDs: targetTrackIDs, ripple: false)
                }
                selectionRange = nil
            } else if !selectedClips.isEmpty || !selectedNotes.isEmpty {
                let clipIDs = selectedClips
                let noteIDs = selectedNotes
                store.perform("Supprimer") {
                    if !clipIDs.isEmpty { $0.removeClips(clipIDs, ripple: false) }
                    if !noteIDs.isEmpty { $0.removeNotes(noteIDs, ripple: false) }
                }
                selectedClips.removeAll()
                selectedNotes.removeAll()
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
            } else if !selectedClips.isEmpty || !selectedNotes.isEmpty {
                let clipIDs = selectedClips
                let noteIDs = selectedNotes
                store.perform("Supprimer et raccorder") {
                    if !clipIDs.isEmpty { $0.removeClips(clipIDs, ripple: true) }
                    if !noteIDs.isEmpty { $0.removeNotes(noteIDs, ripple: true) }
                }
                selectedClips.removeAll()
                selectedNotes.removeAll()
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
            let clipIDs = targetClipIDs
            if !selectedNotes.isEmpty {
                let noteIDs = selectedNotes
                let allMuted = noteIDs.compactMap { project.note(id: $0) }.allSatisfy(\.mute)
                store.perform("Muet notes") { proj in
                    for id in noteIDs { proj.setNoteMute(id: id, !allMuted) }
                }
            } else if !clipIDs.isEmpty {
                let allMuted = clipIDs.compactMap { project.clip(id: $0) }.allSatisfy(\.mute)
                store.perform("Muet") { proj in
                    for id in clipIDs { proj.setClipMute(id: id, !allMuted) }
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
            store.perform("Ajouter une piste audio") { newID = $0.addTrack() }
            if let newID { selectedTrackID = newID }
        case .addMIDITrack:
            addMIDITrack()
        case .duplicateTrack:
            guard let t = activeTrack else { return }
            var newID: UUID?
            store.perform("Dupliquer la piste") { newID = $0.duplicateTrack(t.id) }
            if let newID { selectedTrackID = newID }
        case .deleteTrack:
            guard let t = activeTrack else { return }
            store.perform("Supprimer la piste") { $0.removeTrack(t.id) }
            selectedTrackID = project.tracks.first?.id
        case .moveTrackUp:
            moveSelectedTrackUp()
        case .moveTrackDown:
            moveSelectedTrackDown()
        case .togglePianoRoll:
            toggleSelectedTrackPianoRoll()
        case .quantizeSelection:
            quantizeSelection()
        case .bounceMIDIToAudio:
            if let t = activeTrack, t.isMIDI {
                bounceMIDITrackToAudio(t.id)
            }
        case .addMarker:
            let t = playhead
            var mID: UUID?
            store.perform("Ajouter un marqueur") { mID = $0.addMarker(at: t) }
            selectedMarkerID = mID
        case .selectAll:
            selectedClips = Set(project.allClips.map(\.clip.id))
            selectedNotes = Set(project.allNotes.map(\.note.id))
            if totalDuration > 0 { selectionRange = 0...totalDuration }
            timelineView?.needsDisplay = true
        case .deselectAll:
            selectedClips.removeAll()
            selectedNotes.removeAll()
            selectionRange = nil
            selectedMarkerID = nil
            timelineView?.needsDisplay = true
        case .toggleZoom:
            timelineView?.toggleZoomToFitOrPlayhead()
        case .zoomToFit:
            timelineView?.fit(animate: true)
        case .zoomToSelection:
            if let range = selectionRange, range.upperBound > range.lowerBound + 0.01 {
                timelineView?.zoom(toRange: range, animate: true)
            } else if let c = selectedClipObjects.first {
                timelineView?.zoom(toRange: c.offset...c.end, animate: true)
            } else if !selectedNoteObjects.isEmpty {
                let lo = selectedNoteObjects.map(\.start).min() ?? 0
                let hi = selectedNoteObjects.map(\.end).max() ?? 1
                timelineView?.zoom(toRange: lo...max(lo + 0.5, hi), animate: true)
            } else {
                timelineView?.toggleZoomToFitOrPlayhead()
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
    static let notePasteboardType = NSPasteboard.PasteboardType("net.cieadrienm.simpleaudio.notes")

    func copySelection() {
        var slices: [ClipboardSlice] = []
        var nSlices: [NoteClipboardSlice] = []
        if let range = selectionRange, range.upperBound > range.lowerBound + 0.005 {
            slices = project.extractSlices(in: range, trackIDs: targetTrackIDs)
            nSlices = project.extractNoteSlices(in: range, trackIDs: targetTrackIDs)
        } else {
            if !selectedClips.isEmpty {
                slices = project.extractClips(selectedClips)
            }
            if !selectedNotes.isEmpty {
                nSlices = project.extractNotes(selectedNotes)
            }
            if slices.isEmpty && nSlices.isEmpty && project.clipCount == 1, let only = project.allClips.first?.clip.id {
                slices = project.extractClips([only])
            }
        }
        guard !slices.isEmpty || !nSlices.isEmpty else {
            flash("rien à copier")
            return
        }
        clipboard = slices
        noteClipboard = nSlices
        NSPasteboard.general.clearContents()
        if !slices.isEmpty, let data = try? JSONEncoder().encode(slices) {
            NSPasteboard.general.setData(data, forType: Self.pasteboardType)
        }
        if !nSlices.isEmpty, let data = try? JSONEncoder().encode(nSlices) {
            NSPasteboard.general.setData(data, forType: Self.notePasteboardType)
        }
        let totalCount = slices.count + nSlices.count
        flash("\(totalCount) élément\(totalCount > 1 ? "s" : "") copié\(totalCount > 1 ? "s" : "")")
    }

    func cutSelection() {
        copySelection()
        guard !clipboard.isEmpty || !noteClipboard.isEmpty else { return }
        if let range = selectionRange, range.upperBound > range.lowerBound + 0.005 {
            let start = range.lowerBound
            store.perform("Couper la plage") {
                $0.deleteRange(range, trackIDs: targetTrackIDs, ripple: true)
            }
            selectionRange = nil
            engine.seek(to: start)
        } else if !selectedClips.isEmpty || !selectedNotes.isEmpty {
            let clipIDs = selectedClips
            let noteIDs = selectedNotes
            store.perform("Couper") {
                if !clipIDs.isEmpty { $0.removeClips(clipIDs, ripple: true) }
                if !noteIDs.isEmpty { $0.removeNotes(noteIDs, ripple: true) }
            }
            selectedClips.removeAll()
            selectedNotes.removeAll()
        }
    }

    func pasteClipboard() {
        var slices = clipboard
        var nSlices = noteClipboard
        if slices.isEmpty,
           let data = NSPasteboard.general.data(forType: Self.pasteboardType),
           let decoded = try? JSONDecoder().decode([ClipboardSlice].self, from: data) {
            slices = decoded
            clipboard = decoded
        }
        if nSlices.isEmpty,
           let data = NSPasteboard.general.data(forType: Self.notePasteboardType),
           let decoded = try? JSONDecoder().decode([NoteClipboardSlice].self, from: data) {
            nSlices = decoded
            noteClipboard = decoded
        }
        guard !slices.isEmpty || !nSlices.isEmpty else {
            flash("presse-papiers vide")
            return
        }
        let targetTime = selectionRange?.lowerBound ?? playhead
        var pastedClips: [UUID] = []
        var pastedNotes: [UUID] = []
        store.perform("Coller") { proj in
            if let range = selectionRange, range.upperBound > range.lowerBound + 0.005 {
                proj.deleteRange(range, trackIDs: targetTrackIDs, ripple: true)
            }
            if !slices.isEmpty {
                pastedClips = proj.paste(slices, at: targetTime, targetTrackID: selectedTrackID, insertRipple: true)
            }
            if !nSlices.isEmpty {
                pastedNotes = proj.pasteNotes(nSlices, at: targetTime, targetTrackID: selectedTrackID, insertRipple: true)
            }
        }
        selectionRange = nil
        if !pastedClips.isEmpty {
            selectedClips = Set(pastedClips)
            let span = slices.map { $0.relativeOffset + $0.clip.duration }.max() ?? 0
            engine.seek(to: targetTime + span)
        }
        if !pastedNotes.isEmpty {
            selectedNotes = Set(pastedNotes)
            let span = nSlices.map { $0.relativeStart + $0.note.duration }.max() ?? 0
            if pastedClips.isEmpty {
                engine.seek(to: targetTime + span)
            }
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

    func setBPM(_ bpm: Double) {
        store.perform("Tempo") { $0.setTempo(bpm) }
    }

    func setTimeSignature(numerator: Int, denominator: Int) {
        store.perform("Signature rythmique") { $0.setTimeSignature(numerator: numerator, denominator: denominator) }
    }

    func setTrackProgram(_ id: UUID, _ program: Int) {
        store.perform("Instrument GM") { $0.setTrackProgram(id, program: program) }
    }

    func setTrackChannel(_ id: UUID, _ channel: Int, isDrum: Bool? = nil) {
        store.perform("Canal MIDI") { $0.setTrackChannel(id, channel: channel, isDrum: isDrum) }
    }

    func setTrackTranspose(_ id: UUID, _ semitones: Int) {
        store.perform("Transposition piste") { $0.setTrackTranspose(id, semitones: semitones) }
    }

    func toggleTrackPianoRoll(_ id: UUID) {
        guard let ti = project.trackIndex(of: id) else { return }
        let expanded = !project.tracks[ti].pianoRollExpanded
        store.perform(expanded ? "Ouvrir le Piano-Roll" : "Réduire le Piano-Roll") {
            $0.setTrackPianoRollExpanded(id, expanded)
        }
    }

    func toggleSelectedTrackPianoRoll() {
        if let t = activeTrack, t.isMIDI {
            toggleTrackPianoRoll(t.id)
        } else if let firstMIDI = project.tracks.first(where: \.isMIDI) {
            toggleTrackPianoRoll(firstMIDI.id)
        }
    }

    @discardableResult
    func addMIDITrack(name: String? = nil, program: Int = 0, isDrum: Bool = false) -> UUID {
        var newID = UUID()
        store.perform("Ajouter une piste MIDI") { proj in
            newID = proj.addMIDITrack(
                name: name,
                program: program,
                channel: isDrum ? 9 : 0,
                isDrum: isDrum
            )
        }
        selectedTrackID = newID
        return newID
    }

    func setNotePitch(_ id: UUID, _ pitch: Int) {
        let clamped = min(max(pitch, 0), 127)
        store.perform("Hauteur de note") { $0.setNotePitch(id, pitch: clamped) }
        if let (ti, _) = project.noteLocation(of: id) {
            let tr = project.tracks[ti]
            engine.previewNote(pitch: clamped, velocity: 100, program: tr.program, isDrum: tr.isDrum || tr.channel == 9)
        }
    }

    func setNoteVelocity(_ id: UUID, _ velocity: Int) {
        store.perform("Vélocité de note") { $0.setNoteVelocity(id, velocity: velocity) }
    }

    func setNoteStart(_ id: UUID, _ start: Double) {
        guard let n = project.note(id: id) else { return }
        store.perform("Début de note") { $0.moveNote(id, toStart: start, pitch: n.pitch) }
    }

    func setNoteDuration(_ id: UUID, _ duration: Double) {
        guard let n = project.note(id: id) else { return }
        store.perform("Durée de note") { $0.trimNote(id, start: n.start, duration: duration) }
    }

    func setNoteMute(_ id: UUID, _ mute: Bool) {
        store.perform("Muet note") { $0.setNoteMute(id: id, mute) }
    }

    func quantizeSelection(subdivisionBeats: Double = 0.25) {
        let ids: Set<UUID>? = selectedNotes.isEmpty ? nil : selectedNotes
        store.perform("Quantifier") {
            $0.quantizeNotes(ids, subdivisionBeats: subdivisionBeats, trackIDs: ids == nil ? targetTrackIDs : nil)
        }
        flash("quantifié (1/16)")
    }

    func transposeSelection(semitones: Int) {
        if !selectedNotes.isEmpty {
            let ids = selectedNotes
            store.perform("Transposer (\(semitones > 0 ? "+\(semitones)" : "\(semitones)"))") {
                $0.transposeNotes(ids, semitones: semitones)
            }
            if let first = selectedNoteObjects.first,
               let (ti, _) = project.noteLocation(of: first.id) {
                let tr = project.tracks[ti]
                engine.previewNote(pitch: first.pitch, velocity: first.velocity, program: tr.program, isDrum: tr.isDrum || tr.channel == 9)
            }
            flash("transposé \(semitones > 0 ? "+\(semitones)" : "\(semitones)") demi-ton\(abs(semitones) > 1 ? "s" : "")")
        } else if let t = activeTrack, t.isMIDI {
            let next = min(max(t.transpose + semitones, -48), 48)
            setTrackTranspose(t.id, next)
            flash("piste transposée \(next > 0 ? "+\(next)" : "\(next)") st")
        }
    }

    /// Renders a MIDI track to a 24-bit stereo WAV file and adds or replaces it as an Audio track on the timeline.
    @discardableResult
    func bounceMIDITrackToAudio(_ trackID: UUID, replaceMIDITrack: Bool = false) -> UUID? {
        guard let ti = project.trackIndex(of: trackID) else { return nil }
        let track = project.tracks[ti]
        guard !track.notes.isEmpty else {
            flash("piste MIDI vide")
            return nil
        }
        let targetDir: URL
        if let url = store.url {
            targetDir = url.deletingLastPathComponent()
        } else {
            targetDir = FileManager.default.temporaryDirectory.appendingPathComponent("SimpleAudioBounces", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        let safeName = track.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let wavURL = targetDir.appendingPathComponent("\(safeName)-bounce-\(UUID().uuidString.prefix(6)).wav")

        do {
            var clip = try AudioExporter.bounceMIDITrack(track, in: project, to: wavURL, sampleRate: project.sampleRate)
            _ = waveforms.preloadSync(wavURL)
            if store.isProjectFile {
                clip.path = AudioProject.storedPath(for: wavURL, relativeTo: store.url)
            }
            var resultTrackID = track.id
            store.perform(replaceMIDITrack ? "Convertir MIDI en piste Audio" : "Rendre MIDI en piste Audio") { proj in
                guard let idx = proj.trackIndex(of: trackID) else { return }
                if replaceMIDITrack {
                    proj.tracks[idx].kind = .audio
                    proj.tracks[idx].notes.removeAll()
                    proj.tracks[idx].pianoRollExpanded = false
                    proj.tracks[idx].stereoSplit = true
                    proj.tracks[idx].clips = [clip]
                    resultTrackID = proj.tracks[idx].id
                } else {
                    let audioTrack = AudioTrack(
                        name: "\(track.name) (Audio)",
                        colorIndex: (track.colorIndex + 1) % 8,
                        gainDB: track.gainDB,
                        pan: track.pan,
                        stereoSplit: true,
                        kind: .audio,
                        clips: [clip]
                    )
                    proj.tracks.insert(audioTrack, at: min(idx + 1, proj.tracks.count))
                    resultTrackID = audioTrack.id
                }
            }
            selectedTrackID = resultTrackID
            selectedClips = [clip.id]
            selectedNotes.removeAll()
            engine.update(project: store.project, projectURL: store.url)
            flash("piste MIDI convertie en Audio")
            return resultTrackID
        } catch {
            errorMessage = "Impossible de convertir la piste MIDI en Audio : \(error.localizedDescription)"
            return nil
        }
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

    /// Moves track `id` to 0-based index `destination` with Undo/Redo support.
    func moveTrack(_ id: UUID, to destination: Int) {
        guard let from = project.trackIndex(of: id) else { return }
        let clamped = min(max(destination, 0), max(0, project.tracks.count - 1))
        guard clamped != from else { return }
        store.perform("Réordonner la piste") { proj in
            proj.moveTrack(id, to: clamped)
        }
        selectedTrackID = id
    }

    /// Shifts track `id` up (`delta = -1`) or down (`delta = 1`) in the track stack.
    func moveTrack(_ id: UUID, by delta: Int) {
        guard let from = project.trackIndex(of: id) else { return }
        moveTrack(id, to: from + delta)
    }

    func moveSelectedTrackUp() {
        guard let t = activeTrack else { return }
        moveTrack(t.id, by: -1)
    }

    func moveSelectedTrackDown() {
        guard let t = activeTrack else { return }
        moveTrack(t.id, by: 1)
    }
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
        if urls.count == 1, !project.hasContent {
            let ext = urls[0].pathExtension.lowercased()
            if Self.midiExtensions.contains(ext) || Self.projectExtensions.contains(ext) {
                open(urls[0])
                return
            }
        }
        for (i, url) in urls.enumerated() {
            let ext = url.pathExtension.lowercased()
            if Self.projectExtensions.contains(ext) {
                open(url)
            } else if Self.midiExtensions.contains(ext) {
                _ = try? importMIDI(url: url, at: offset)
            } else if Self.soundfontExtensions.contains(ext) {
                _ = loadSoundfont(url: url)
            } else {
                let trackIdx: Int? = (!onNewTracks && !project.tracks.isEmpty) ? (selectedTrackID.flatMap { project.trackIndex(of: $0) } ?? 0) : (project.allClips.isEmpty && i == 0 && !project.tracks.isEmpty && project.tracks[0].isAudio ? 0 : nil)
                _ = try? importAudio(url: url, toTrackIndex: trackIdx, at: offset)
            }
        }
        timelineView?.fit()
    }

    func loadDemoProject() {
        let demoDir = FileManager.default.temporaryDirectory.appendingPathComponent("SimpleAudioDemo", isDirectory: true)
        if let (projURL, _) = try? SyntheticAudio.createDemoFixtures(in: demoDir) {
            open(projURL)
        }
    }

    func loadMIDIDemoProject() {
        let demoDir = FileManager.default.temporaryDirectory.appendingPathComponent("SimpleAudioDemo", isDirectory: true)
        let midURL = demoDir.appendingPathComponent("demo-horizon.mid")
        if (try? SyntheticAudio.writeDemoMIDIFile(to: midURL)) != nil {
            open(midURL)
        }
    }

    func loadHybridDemoProject() {
        let demoDir = FileManager.default.temporaryDirectory.appendingPathComponent("SimpleAudioDemo", isDirectory: true)
        if let (projURL, _) = try? SyntheticAudio.createHybridDemoFixtures(in: demoDir) {
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
            return MainActor.assumeIsolated { self.handleKeyDown(event) } ? nil : event
        }
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        if showExport || showAbout || showHelp || showShortcuts { return false }
        if let w = event.window {
            if w.sheetParent != nil { return false }
            if w.firstResponder is NSText { return false }
        }
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
        // Escape -> clear range & clip selection
        if event.keyCode == 53, flags.isEmpty {
            perform(.deselectAll)
            return true
        }
        // Return / Enter / Home -> Rewind
        if (event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 115), flags.isEmpty {
            perform(.rewind)
            return true
        }
        // Left / Right arrows
        if event.keyCode == 123, flags.isEmpty || flags == .shift {
            if flags == .shift {
                seek(to: max(0, playhead - 1.0))
            } else {
                perform(.stepBackward)
            }
            return true
        }
        if event.keyCode == 124, flags.isEmpty || flags == .shift {
            if flags == .shift {
                seek(to: min(totalDuration, playhead + 1.0))
            } else {
                perform(.stepForward)
            }
            return true
        }

        // Up / Down arrows (126 / 125) -> Transpose selected MIDI notes (±1 or ±12 semitones with Shift)
        if event.keyCode == 126, (flags.isEmpty || flags == .shift), !selectedNotes.isEmpty {
            transposeSelection(semitones: flags == .shift ? 12 : 1)
            return true
        }
        if event.keyCode == 125, (flags.isEmpty || flags == .shift), !selectedNotes.isEmpty {
            transposeSelection(semitones: flags == .shift ? -12 : -1)
            return true
        }

        // Option+Up / Option+Down -> Reorder active track up or down
        if event.keyCode == 126, flags == .option, project.tracks.count > 1 {
            perform(.moveTrackUp)
            return true
        }
        if event.keyCode == 125, flags == .option, project.tracks.count > 1 {
            perform(.moveTrackDown)
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

        // Shift+Z -> Zoom to selection range or selected clip
        if flags == .shift, chars == "z" {
            perform(.zoomToSelection)
            return true
        }

        // Command+= / Command+- / Command+0 -> Zoom In / Out / Toggle Fit
        if flags == .command {
            switch chars {
            case "=", "+":
                perform(.zoomIn)
                return true
            case "-":
                perform(.zoomOut)
                return true
            case "0":
                perform(.toggleZoom)
                return true
            default:
                return false
            }
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
        case "p":
            perform(.togglePianoRoll)
            return true
        case "q":
            perform(.quantizeSelection)
            return true
        case "x":
            perform(.crossfadeSelection)
            return true
        case "f":
            perform(.zoomToFit)
            return true
        case "z", "0":
            perform(.toggleZoom)
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
