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
        CommandGroup(replacing: .appInfo) {
            Button("À propos de SimpleAudio") {
                model.showAbout = true
            }
        }

        CommandGroup(replacing: .newItem) {
            Button("Nouveau projet") {
                model.newProject()
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button("Ouvrir Audio, MIDI ou Projet…") {
                model.openDocumentPanel()
            }
            .keyboardShortcut("o", modifiers: [.command])

            Menu("Ouvrir l’élément récent") {
                if model.recentFiles.isEmpty {
                    Text("Aucun élément récent")
                } else {
                    ForEach(model.recentFiles, id: \.path) { url in
                        Button(url.lastPathComponent) {
                            model.requestOpen(url)
                        }
                    }
                    Divider()
                    Button("Effacer le menu") {
                        model.clearRecentFiles()
                    }
                }
            }

            Button("Importer des fichiers Audio / MIDI…") {
                model.importAudioPanel()
            }
            .keyboardShortcut("i", modifiers: [.command])

            Button("Charger une banque SoundFont (.sf2 / .dls)…") {
                model.chooseSoundfontPanel()
            }

            Divider()

            Button("Charger la démo multipiste Audio") {
                model.loadDemoProject()
            }

            Button("Charger la démo hybride Audio + MIDI") {
                model.loadHybridDemoProject()
            }

            Button("Charger la démo MIDI (Piano-Roll)") {
                model.loadMIDIDemoProject()
            }

            Divider()

            Button("Enregistrer") {
                model.saveDocument()
            }
            .keyboardShortcut("s", modifiers: [.command])

            Button("Enregistrer sous…") {
                model.saveDocumentAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Divider()

            Button("Exporter Audio / MIDI…") {
                model.showExportSheet = true
            }
            .keyboardShortcut("e", modifiers: [.command])

            Button("Exporter en fichier MIDI (.mid)…") {
                model.exportMIDIFilePanel()
            }
            .disabled(!model.store.project.hasMIDITracks)
        }

        CommandGroup(replacing: .undoRedo) {
            Button(model.store.undoLabel.map { "Annuler \($0)" } ?? "Annuler") {
                model.store.undo()
            }
            .keyboardShortcut("z", modifiers: [.command])
            .disabled(!model.store.canUndo)

            Button(model.store.redoLabel.map { "Rétablir \($0)" } ?? "Rétablir") {
                model.store.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!model.store.canRedo)
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Couper") {
                model.cutSelection()
            }
            .keyboardShortcut("x", modifiers: [.command])

            Button("Copier") {
                model.copySelection()
            }
            .keyboardShortcut("c", modifiers: [.command])

            Button("Coller") {
                model.pasteAtPlayhead()
            }
            .keyboardShortcut("v", modifiers: [.command])

            Button("Dupliquer") {
                model.duplicateSelectedClips()
            }
            .keyboardShortcut("d", modifiers: [.command])

            Divider()

            Button("Rogner sur la plage (Crop)") {
                model.cropToSelection()
            }
            .keyboardShortcut("t", modifiers: [.command])
            .disabled(model.selectionRange == nil)

            Button("Silencer la plage") {
                model.silenceSelection()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(model.selectionRange == nil)

            Divider()

            Button("Supprimer") {
                model.deleteSelection(ripple: false)
            }

            Button("Supprimer et raccorder") {
                model.deleteSelection(ripple: true)
            }

            Divider()

            Button("Tout sélectionner") {
                model.selectAll()
            }
            .keyboardShortcut("a", modifiers: [.command])
        }

        CommandMenu("Audio") {
            Button("Scinder à la tête de lecture") {
                model.splitAtPlayhead()
            }
            .keyboardShortcut("k", modifiers: [.command])

            Divider()

            Button("Fondu d'entrée (0.5 s)") {
                model.applyFadeIn(duration: 0.5)
            }

            Button("Fondu de sortie (0.5 s)") {
                model.applyFadeOut(duration: 0.5)
            }

            Menu("Courbe de fondu") {
                ForEach(FadeShape.allCases, id: \.self) { shape in
                    Button(shape.label) {
                        let ids = model.selectedClips
                        model.store.perform("Courbe de fondu") { proj in
                            for id in ids {
                                try? Operations.setFade(&proj, id: id, shape: shape)
                            }
                        }
                    }
                }
            }

            Divider()

            Button("Normaliser à -0.1 dBFS") {
                model.normalizeSelectedClips(targetDB: -0.1)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Supprimer les silences aux extrémités") {
                model.stripSilenceOnSelected()
            }

            Button("Inverser le sens (Reverse)") {
                model.reverseSelectedClips()
            }
            .keyboardShortcut("r", modifiers: [.command])
        }

        CommandMenu("Piste & MIDI") {
            Button("Nouvelle piste audio") {
                model.addTrack()
            }
            .keyboardShortcut("n", modifiers: [.command, .option])

            Button("Nouvelle piste MIDI (Piano-Roll)") {
                model.addMIDITrack()
            }
            .keyboardShortcut("n", modifiers: [.command, .control])

            Button("Ouvrir / Réduire le Piano-Roll  P") {
                model.toggleSelectedTrackPianoRoll()
            }

            Divider()

            Button("Quantifier les notes (1/16)  Q") {
                model.quantizeSelection(subdivisionBeats: 0.25)
            }

            Button("Transposer +1 demi-ton  ↑") {
                model.transposeSelection(semitones: 1)
            }

            Button("Transposer -1 demi-ton  ↓") {
                model.transposeSelection(semitones: -1)
            }

            Button("Transposer +1 octave  ⇧↑") {
                model.transposeSelection(semitones: 12)
            }

            Button("Transposer -1 octave  ⇧↓") {
                model.transposeSelection(semitones: -12)
            }

            Divider()

            Button("Rendre la piste MIDI en piste Audio (WAV)") {
                if let id = model.selectedTrackID {
                    model.bounceMIDITrackToAudio(id, replaceMIDITrack: false)
                }
            }
            .disabled(model.activeTrack?.isMIDI != true)

            Button("Convertir la piste MIDI en piste Audio") {
                if let id = model.selectedTrackID {
                    model.bounceMIDITrackToAudio(id, replaceMIDITrack: true)
                }
            }
            .disabled(model.activeTrack?.isMIDI != true)

            Divider()

            Button("Monter la piste  ⌥↑") {
                model.moveSelectedTrackUp()
            }
            .disabled(model.store.project.tracks.count <= 1)

            Button("Descendre la piste  ⌥↓") {
                model.moveSelectedTrackDown()
            }
            .disabled(model.store.project.tracks.count <= 1)

            Button("Dupliquer la piste") {
                model.duplicateSelectedTrack()
            }

            Button("Supprimer la piste") {
                model.removeSelectedTrack()
            }
            .disabled(model.store.project.tracks.count <= 1)

            Divider()

            Button("Muet sur la piste active") {
                if let id = model.selectedTrackID {
                    model.toggleTrackMute(id)
                }
            }

            Button("Solo sur la piste active") {
                if let id = model.selectedTrackID {
                    model.toggleTrackSolo(id)
                }
            }

            Button("Afficher/Masquer les canaux L/R") {
                if let id = model.selectedTrackID {
                    model.toggleTrackStereoSplit(id)
                }
            }
        }

        CommandMenu("Transport") {
            Button(model.transportPlaying ? "Pause" : "Lecture") {
                model.togglePlay()
            }

            Button("Retour au début") {
                model.seek(to: 0)
            }

            Button("Lecture en boucle") {
                model.toggleLoop()
            }
            .keyboardShortcut("l", modifiers: [.command])

            Divider()

            Button("Ajouter un marqueur") {
                model.addMarkerAtPlayhead()
            }
        }

        CommandGroup(after: .toolbar) {
            Button(model.showSidebar ? "Masquer la barre latérale" : "Afficher la barre latérale") {
                model.showSidebar.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])

            Button(model.showInspector ? "Masquer l’inspecteur" : "Afficher l’inspecteur") {
                model.showInspector.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])

            Divider()

            Button("Basculer le zoom (Tout voir ↔ Curseur)  Z") {
                model.perform(.toggleZoom)
            }
            .keyboardShortcut("0", modifiers: [.command])

            Button("Ajuster à la fenêtre  F") {
                model.perform(.zoomToFit)
            }

            Button("Zoom avant") {
                model.perform(.zoomIn)
            }
            .keyboardShortcut("=", modifiers: [.command])

            Button("Zoom arrière") {
                model.perform(.zoomOut)
            }
            .keyboardShortcut("-", modifiers: [.command])

            Divider()

            Button((model.snapping ? "✓ " : "") + "Magnétisme  N") {
                model.perform(.toggleSnapping)
            }
        }

        CommandGroup(replacing: .help) {
            Button("Aide SimpleAudio") {
                model.showHelp = true
            }
            .keyboardShortcut("?", modifiers: [.command])

            Divider()

            Button("Raccourcis clavier") {
                model.showShortcuts = true
            }
            .keyboardShortcut("/", modifiers: [.command])
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

        if args.contains("--self-test") {
            SelfTest.runAndExit()
        }

        if let snapIdx = args.firstIndex(of: "--snapshot") {
            let outPath = (snapIdx + 1 < args.count) ? args[snapIdx + 1] : "/tmp/simpleaudio-snapshot.png"
            let positional = args.enumerated().compactMap { i, a -> String? in
                if i == snapIdx || i == snapIdx + 1 || a.hasPrefix("-") { return nil }
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

        let args = Array(CommandLine.arguments.dropFirst()).filter { !$0.hasPrefix("-") }
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
