import AppKit
import Observation
import SwiftUI
import SimpleAudioCore

@main
struct SimpleAudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("SimpleAudio") {
            ContentView(model: appDelegate.model)
                .frame(minWidth: 920, minHeight: 540)
                .onAppear {
                    appDelegate.didAppear()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1280, height: 780)
        .commands {
            appCommands(model: appDelegate.model)
        }

        Settings {
            PreferencesView(model: appDelegate.model) {
                appDelegate.restartNetworkServers()
            }
        }
    }

    @CommandsBuilder
    private func appCommands(model: AppModel) -> some Commands {
        let _ = model.language
        CommandGroup(replacing: .appInfo) {
            Button(L("À propos de SimpleAudio", "About SimpleAudio")) {
                model.showAbout = true
            }
            Button(L("Rechercher des mises à jour…", "Check for Updates…")) {
                model.showUpdater = true
                model.updater.checkForUpdates(silent: false)
            }
        }

        CommandGroup(replacing: .newItem) {
            Button(L("Nouveau projet", "New Project")) {
                model.newProject()
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button(L("Ouvrir Audio, MIDI ou Projet…", "Open Audio, MIDI or Project…")) {
                model.openDocumentPanel()
            }
            .keyboardShortcut("o", modifiers: [.command])

            Menu(L("Ouvrir l’élément récent", "Open Recent")) {
                if model.recentFiles.isEmpty {
                    Text(L("Aucun élément récent", "No Recent Items"))
                } else {
                    ForEach(model.recentFiles, id: \.path) { url in
                        Button(url.lastPathComponent) {
                            model.requestOpen(url)
                        }
                    }
                    Divider()
                    Button(L("Effacer le menu", "Clear Menu")) {
                        model.clearRecentFiles()
                    }
                }
            }

            Button(L("Importer des fichiers Audio / MIDI…", "Import Audio / MIDI Files…")) {
                model.importAudioPanel()
            }
            .keyboardShortcut("i", modifiers: [.command])

            Button(L("Charger une banque SoundFont (.sf2 / .dls)…", "Load SoundFont Bank (.sf2 / .dls)…")) {
                model.chooseSoundfontPanel()
            }

            Divider()

            Button(L("Charger la démo multipiste Audio", "Load Multitrack Audio Demo")) {
                model.loadDemoProject()
            }

            Button(L("Charger la démo hybride Audio + MIDI", "Load Hybrid Audio + MIDI Demo")) {
                model.loadHybridDemoProject()
            }

            Button(L("Charger la démo MIDI (Piano-Roll)", "Load MIDI Demo (Piano Roll)")) {
                model.loadMIDIDemoProject()
            }

            Divider()

            Button(L("Enregistrer", "Save")) {
                model.saveDocument()
            }
            .keyboardShortcut("s", modifiers: [.command])

            Button(L("Enregistrer sous…", "Save As…")) {
                model.saveDocumentAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Divider()

            Button(L("Exporter Audio / MIDI…", "Export Audio / MIDI…")) {
                model.showExportSheet = true
            }
            .keyboardShortcut("e", modifiers: [.command])

            Button(L("Exporter en fichier MIDI (.mid)…", "Export as MIDI File (.mid)…")) {
                model.exportMIDIFilePanel()
            }
            .disabled(!model.store.project.hasMIDITracks)
        }

        CommandGroup(replacing: .undoRedo) {
            Button(model.store.undoLabel.map { L("Annuler \($0)", "Undo \($0)") } ?? L("Annuler", "Undo")) {
                model.store.undo()
            }
            .keyboardShortcut("z", modifiers: [.command])
            .disabled(!model.store.canUndo)

            Button(model.store.redoLabel.map { L("Rétablir \($0)", "Redo \($0)") } ?? L("Rétablir", "Redo")) {
                model.store.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!model.store.canRedo)
        }

        CommandGroup(replacing: .pasteboard) {
            Button(L("Couper", "Cut")) {
                model.cutSelection()
            }
            .keyboardShortcut("x", modifiers: [.command])

            Button(L("Copier", "Copy")) {
                model.copySelection()
            }
            .keyboardShortcut("c", modifiers: [.command])

            Button(L("Coller", "Paste")) {
                model.pasteAtPlayhead()
            }
            .keyboardShortcut("v", modifiers: [.command])

            Button(L("Dupliquer", "Duplicate")) {
                model.duplicateSelectedClips()
            }
            .keyboardShortcut("d", modifiers: [.command])

            Divider()

            Button(L("Rogner sur la plage (Crop)", "Crop to Range")) {
                model.cropToSelection()
            }
            .keyboardShortcut("t", modifiers: [.command])
            .disabled(model.selectionRange == nil)

            Button(L("Silencer la plage", "Silence Range")) {
                model.silenceSelection()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(model.selectionRange == nil)

            Divider()

            Button(L("Supprimer", "Delete")) {
                model.deleteSelection(ripple: false)
            }

            Button(L("Supprimer et raccorder", "Ripple Delete")) {
                model.deleteSelection(ripple: true)
            }

            Divider()

            Button(L("Tout sélectionner", "Select All")) {
                model.selectAll()
            }
            .keyboardShortcut("a", modifiers: [.command])
        }

        CommandMenu(L("Audio", "Audio")) {
            Button(L("Scinder à la tête de lecture", "Split at Playhead")) {
                model.splitAtPlayhead()
            }
            .keyboardShortcut("k", modifiers: [.command])

            Divider()

            Button(L("Fondu d'entrée (0.5 s)", "Fade In (0.5 s)")) {
                model.applyFadeIn(duration: 0.5)
            }

            Button(L("Fondu de sortie (0.5 s)", "Fade Out (0.5 s)")) {
                model.applyFadeOut(duration: 0.5)
            }

            Menu(L("Courbe de fondu", "Fade Curve")) {
                ForEach(FadeShape.allCases, id: \.self) { shape in
                    Button(shape.label) {
                        let ids = model.selectedClips
                        model.store.perform(L("Courbe de fondu", "Fade Curve")) { proj in
                            for id in ids {
                                try? Operations.setFade(&proj, id: id, shape: shape)
                            }
                        }
                    }
                }
            }

            Divider()

            Button(L("Normaliser à -0.1 dBFS", "Normalize to -0.1 dBFS")) {
                model.normalizeSelectedClips(targetDB: -0.1)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button(L("Supprimer les silences aux extrémités", "Strip Silence at Edges")) {
                model.stripSilenceOnSelected()
            }

            Button(L("Inverser le sens (Reverse)", "Reverse Clip")) {
                model.reverseSelectedClips()
            }
            .keyboardShortcut("r", modifiers: [.command])
        }

        CommandMenu(L("Piste & MIDI", "Track & MIDI")) {
            Button(L("Nouvelle piste audio", "New Audio Track")) {
                model.addTrack()
            }
            .keyboardShortcut("n", modifiers: [.command, .option])

            Button(L("Nouvelle piste MIDI (Piano-Roll)", "New MIDI Track (Piano Roll)")) {
                model.addMIDITrack()
            }
            .keyboardShortcut("n", modifiers: [.command, .control])

            Button(L("Ouvrir / Réduire le Piano-Roll  P", "Expand / Collapse Piano Roll  P")) {
                model.toggleSelectedTrackPianoRoll()
            }

            Divider()

            Button(L("Quantifier les notes (1/16)  Q", "Quantize Notes (1/16)  Q")) {
                model.quantizeSelection(subdivisionBeats: 0.25)
            }

            Button(L("Transposer +1 demi-ton  ↑", "Transpose +1 Semitone  ↑")) {
                model.transposeSelection(semitones: 1)
            }

            Button(L("Transposer -1 demi-ton  ↓", "Transpose -1 Semitone  ↓")) {
                model.transposeSelection(semitones: -1)
            }

            Button(L("Transposer +1 octave  ⇧↑", "Transpose +1 Octave  ⇧↑")) {
                model.transposeSelection(semitones: 12)
            }

            Button(L("Transposer -1 octave  ⇧↓", "Transpose -1 Octave  ⇧↓")) {
                model.transposeSelection(semitones: -12)
            }

            Divider()

            Button(L("Rendre la piste MIDI en piste Audio (WAV)", "Bounce MIDI Track to Audio Track (WAV)")) {
                if let id = model.selectedTrackID {
                    model.bounceMIDITrackToAudio(id, replaceMIDITrack: false)
                }
            }
            .disabled(model.activeTrack?.isMIDI != true)

            Button(L("Convertir la piste MIDI en piste Audio", "Convert MIDI Track to Audio Track")) {
                if let id = model.selectedTrackID {
                    model.bounceMIDITrackToAudio(id, replaceMIDITrack: true)
                }
            }
            .disabled(model.activeTrack?.isMIDI != true)

            Divider()

            Button(L("Monter la piste  ⌥↑", "Move Track Up  ⌥↑")) {
                model.moveSelectedTrackUp()
            }
            .disabled(model.store.project.tracks.count <= 1)

            Button(L("Descendre la piste  ⌥↓", "Move Track Down  ⌥↓")) {
                model.moveSelectedTrackDown()
            }
            .disabled(model.store.project.tracks.count <= 1)

            Button(L("Dupliquer la piste", "Duplicate Track")) {
                model.duplicateSelectedTrack()
            }

            Button(L("Supprimer la piste", "Delete Track")) {
                model.removeSelectedTrack()
            }
            .disabled(model.store.project.tracks.count <= 1)

            Divider()

            Button(L("Muet sur la piste active", "Mute Active Track")) {
                if let id = model.selectedTrackID {
                    model.toggleTrackMute(id)
                }
            }

            Button(L("Solo sur la piste active", "Solo Active Track")) {
                if let id = model.selectedTrackID {
                    model.toggleTrackSolo(id)
                }
            }

            Button(L("Afficher/Masquer les canaux L/R", "Show/Hide L/R Channels")) {
                if let id = model.selectedTrackID {
                    model.toggleTrackStereoSplit(id)
                }
            }
        }

        CommandMenu(L("Transport", "Transport")) {
            Button(model.transportPlaying ? L("Pause", "Pause") : L("Lecture", "Play")) {
                model.togglePlay()
            }

            Button(L("Retour au début", "Rewind to Start")) {
                model.seek(to: 0)
            }

            Button(L("Lecture en boucle", "Loop Playback")) {
                model.toggleLoop()
            }
            .keyboardShortcut("l", modifiers: [.command])

            Divider()

            Button(L("Ajouter un marqueur", "Add Marker")) {
                model.addMarkerAtPlayhead()
            }
        }

        CommandGroup(after: .toolbar) {
            Button(model.showSidebar ? L("Masquer la barre latérale", "Hide Sidebar") : L("Afficher la barre latérale", "Show Sidebar")) {
                model.showSidebar.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])

            Button(model.showInspector ? L("Masquer l’inspecteur", "Hide Inspector") : L("Afficher l’inspecteur", "Show Inspector")) {
                model.showInspector.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])

            Divider()

            Button(L("Basculer le zoom (Tout voir ↔ Curseur)  Z", "Toggle Zoom (Fit All ↔ Playhead)  Z")) {
                model.perform(.toggleZoom)
            }
            .keyboardShortcut("0", modifiers: [.command])

            Button(L("Ajuster à la fenêtre  F", "Zoom to Fit  F")) {
                model.perform(.zoomToFit)
            }

            Button(L("Zoom avant", "Zoom In")) {
                model.perform(.zoomIn)
            }
            .keyboardShortcut("=", modifiers: [.command])

            Button(L("Zoom arrière", "Zoom Out")) {
                model.perform(.zoomOut)
            }
            .keyboardShortcut("-", modifiers: [.command])

            Divider()

            Button((model.snapping ? "✓ " : "") + L("Magnétisme  N", "Snapping  N")) {
                model.perform(.toggleSnapping)
            }
        }

        CommandGroup(replacing: .help) {
            Button(L("Aide SimpleAudio", "SimpleAudio Help")) {
                model.showHelp = true
            }
            .keyboardShortcut("?", modifiers: [.command])

            Divider()

            Button(L("Raccourcis clavier", "Keyboard Shortcuts")) {
                model.showShortcuts = true
            }
            .keyboardShortcut("/", modifiers: [.command])

            Divider()

            Button(L("Site web Simple Apps (adrien-m.net/software)", "Simple Apps Website (adrien-m.net/software)")) {
                NSWorkspace.shared.open(URL(string: "https://adrien-m.net/software")!)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var apiServer: APIServer?
    private var oscServer: OSCServer?
    private var didStart = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        AppVersion.runIfRequested()
        let args = Array(CommandLine.arguments.dropFirst())
        let langIdx = args.firstIndex(of: "--lang")

        if args.contains("--self-test") {
            SelfTest.runAndExit()
        }

        if let snapIdx = args.firstIndex(of: "--snapshot") {
            let outPath = (snapIdx + 1 < args.count) ? args[snapIdx + 1] : "/tmp/simpleaudio-snapshot.png"
            let positional = args.enumerated().compactMap { i, a -> String? in
                if i == snapIdx || i == snapIdx + 1 || a.hasPrefix("-") { return nil }
                if let langIdx, (i == langIdx || i == langIdx + 1) { return nil }
                return a
            }.first
            Snapshot.runCLISnapshot(outputPath: outPath, inputPath: positional)
        }
    }

    func didAppear() {
        guard !didStart else { return }
        didStart = true

        NSApp.appearance = NSAppearance(named: .darkAqua)
        model.installKeyMonitor()

        if let envAPIPort = ProcessInfo.processInfo.environment["SIMPLEAUDIO_API_PORT"],
           let p = UInt16(envAPIPort) {
            model.apiPort = p
        }
        if let envOSCPort = ProcessInfo.processInfo.environment["SIMPLEAUDIO_OSC_IN_PORT"],
           let p = UInt16(envOSCPort) {
            model.oscInputPort = p
        }

        restartNetworkServers()
        observeStateForSSE()

        let rawArgs = Array(CommandLine.arguments.dropFirst())
        let langIdx = rawArgs.firstIndex(of: "--lang")
        let args = rawArgs.enumerated().compactMap { i, a -> String? in
            if a.hasPrefix("-") { return nil }
            if let langIdx, (i == langIdx || i == langIdx + 1) { return nil }
            return a
        }
        if let firstPath = args.first {
            let url = URL(fileURLWithPath: (firstPath as NSString).expandingTildeInPath)
            if FileManager.default.fileExists(atPath: url.path) {
                if url.pathExtension.lowercased() == "simpleaudio" {
                    model.openDocument(url: url)
                } else {
                    model.openAudioAsNewProject(url: url)
                }
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let first = urls.first else { return }
        if first.pathExtension.lowercased() == "simpleaudio" {
            model.openDocument(url: first)
        } else {
            model.importAudioFiles(urls: urls, onNewTracks: true)
        }
    }

    func restartNetworkServers() {
        apiServer?.stop()
        oscServer?.stop()

        let api = APIServer(model: model)
        if !api.start(port: model.apiPort) {
            _ = api.start(port: 0)
        }
        self.apiServer = api

        let osc = OSCServer(model: model)
        if !osc.start(port: model.oscInputPort) {
            _ = osc.start(port: 0)
        }
        self.oscServer = osc
    }

    private func observeStateForSSE() {
        withObservationTracking {
            _ = model.store.changeCount
            _ = model.transportPlaying
            _ = model.selectionRange
            _ = model.selectedClips
            _ = model.selectedNotes
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.apiServer?.notifyStateChanged()
                self?.observeStateForSSE()
            }
        }
    }
}
