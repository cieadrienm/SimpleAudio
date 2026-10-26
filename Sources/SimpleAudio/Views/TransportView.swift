import SwiftUI
import SimpleAudioCore
import SimpleAudioEngine

struct TransportView: View {
    @Bindable var model: AppModel
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onZoomFit: () -> Void

    var body: some View {
        let _ = model.language
        HStack(spacing: 10) {
            leftControls
            timecodeBadge
            rangePill
            Spacer(minLength: 4)
            centerActions
            Spacer(minLength: 4)
            rightControls
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Color(nsColor: Theme.panel))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: Theme.separator))
                .frame(height: 1)
        }
    }

    private var leftControls: some View {
        HStack(spacing: 5) {
            IconButton(
                symbol: "sidebar.left",
                helpText: L("Afficher/Masquer la barre latérale (⌥⌘S)", "Show/Hide Sidebar (⌥⌘S)"),
                active: model.showSidebar
            ) {
                model.showSidebar.toggle()
            }

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 2)

            IconButton(symbol: "backward.end.fill", helpText: L("Retour au début (Entrée)", "Rewind to Start (Return)")) {
                model.seek(to: 0)
            }
            IconButton(
                symbol: model.transportPlaying ? "pause.fill" : "play.fill",
                helpText: L("Lecture / Pause (Espace)", "Play / Pause (Space)"),
                active: model.transportPlaying
            ) {
                model.togglePlay()
            }
            IconButton(symbol: "stop.fill", helpText: L("Stop", "Stop")) {
                model.stop()
            }
            IconButton(
                symbol: "repeat",
                helpText: L("Lecture en boucle (⌘L)", "Loop Playback (⌘L)"),
                active: model.store.project.loopRange != nil
            ) {
                model.toggleLoop()
            }
        }
    }

    private var timecodeBadge: some View {
        TransportTimecodeBadge(
            engine: model.engine,
            totalDuration: model.store.project.totalDuration,
            hasMIDITracks: model.store.project.hasMIDITracks,
            bpm: model.store.project.bpm
        )
    }

    @ViewBuilder
    private var rangePill: some View {
        if let range = model.selectionRange, range.upperBound > range.lowerBound + 1e-4 {
            HStack(spacing: 5) {
                Image(systemName: "selection.pin.in.out")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(nsColor: Theme.rangeSelection))
                Text("\(TimeFormat.shortDuration(range.upperBound - range.lowerBound))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(nsColor: Theme.text))
                    .lineLimit(1)
                Button {
                    model.selectionRange = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color(nsColor: Theme.textDim))
                }
                .buttonStyle(.plain)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: Theme.rangeSelection).opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color(nsColor: Theme.rangeSelection).opacity(0.45), lineWidth: 1)
                    )
            )
        }
    }

    private var centerActions: some View {
        HStack(spacing: 4) {
            TextButton(title: L("Scinder", "Split"), symbol: "scissors", compact: true) {
                model.splitAtPlayhead()
            }
            .help(L("Scinder à la tête de lecture ou aux bornes de la plage (B)", "Split at playhead or selection range bounds (B)"))

            if model.activeTrack?.isMIDI == true || !model.selectedNotes.isEmpty {
                TextButton(
                    title: L("Piano-Roll", "Piano Roll"),
                    symbol: "pianokeys",
                    prominent: model.activeTrack?.pianoRollExpanded == true,
                    compact: true
                ) {
                    model.toggleSelectedTrackPianoRoll()
                }
                .help(L("Ouvrir/Réduire le Piano-Roll de la piste MIDI (P)", "Expand/Collapse MIDI Track Piano Roll (P)"))

                TextButton(title: L("Quantifier", "Quantize"), symbol: "waveform.path.ecg", compact: true) {
                    model.quantizeSelection(subdivisionBeats: 0.25)
                }
                .help(L("Quantifier les notes sur la double-croche 1/16 (Q)", "Quantize notes to 1/16th grid (Q)"))
            } else {
                TextButton(title: L("Fondu ↗", "Fade ↗"), compact: true) {
                    model.applyFadeIn(duration: 0.5)
                }
                .help(L("Appliquer un fondu d'entrée sur la plage ou le clip sélectionné", "Apply fade-in to selection range or selected clip"))

                TextButton(title: L("Fondu ↘", "Fade ↘"), compact: true) {
                    model.applyFadeOut(duration: 0.5)
                }
                .help(L("Appliquer un fondu de sortie sur la plage ou le clip sélectionné", "Apply fade-out to selection range or selected clip"))
            }

            TextButton(
                title: L("Rogner", "Crop"),
                symbol: "crop",
                compact: true,
                disabled: model.selectionRange == nil
            ) {
                model.cropToSelection()
            }
            .help(L("Garder uniquement la plage sélectionnée (⌘T)", "Keep only the selected time range (⌘T)"))

            TextButton(
                title: L("Silence", "Silence"),
                symbol: "speaker.slash",
                compact: true,
                disabled: model.selectionRange == nil && model.selectedClips.isEmpty && model.selectedNotes.isEmpty
            ) {
                if model.selectionRange != nil {
                    model.silenceSelection()
                } else {
                    model.toggleMuteSelectedClips()
                }
            }
            .help(L("Silencer la plage sélectionnée ou couper le son du clip / des notes", "Silence selected range or mute selected clip / notes"))

            if model.activeTrack?.isMIDI == true {
                soundbankMenu
            } else {
                TextButton(
                    title: L("Normaliser", "Normalize"),
                    symbol: "waveform",
                    compact: true,
                    disabled: model.selectedClips.isEmpty && model.store.project.allClips.isEmpty
                ) {
                    model.normalizeSelectedClips(targetDB: -0.1)
                }
                .help(L("Normaliser le niveau crête à -0.1 dBFS", "Normalize peak level to -0.1 dBFS"))
            }

            IconButton(symbol: "bookmark", helpText: L("Ajouter un marqueur (K)", "Add Marker (K)")) {
                model.addMarkerAtPlayhead()
            }
        }
    }

    private var soundbankMenu: some View {
        Menu {
            Section(L("Banques General MIDI / Synth", "General MIDI / Synth Banks")) {
                ForEach(SoundPreset.allCases) { preset in
                    Button {
                        model.selectSoundPreset(preset)
                    } label: {
                        if model.engine.activeSoundfontURL == nil && model.engine.activePreset == preset {
                            Label(preset.title, systemImage: "checkmark")
                        } else {
                            Text(preset.title)
                        }
                    }
                }
            }
            let recents = SoundfontLibrary.shared.recentEntries()
            if !recents.isEmpty {
                Section(L("SoundFonts récentes (.sf2 / .dls)", "Recent SoundFonts (.sf2 / .dls)")) {
                    ForEach(recents) { entry in
                        Button(entry.name) {
                            _ = model.loadSoundfont(url: entry.url)
                        }
                    }
                }
            }
            Divider()
            Button(L("Charger une SoundFont (.sf2 / .dls)…", "Load SoundFont (.sf2 / .dls)…")) {
                model.chooseSoundfontPanel()
            }
        } label: {
            Label(model.engine.activeSoundfontName, systemImage: "pianokeys")
                .font(.system(size: 11, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06)))
        .help(L("Choisir la banque de sons MIDI (General MIDI ou SoundFont .sf2)", "Select MIDI soundbank (General MIDI or .sf2 SoundFont)"))
    }

    private var rightControls: some View {
        HStack(spacing: 6) {
            TransportMeterWrapper(engine: model.engine)
                .help(L("Niveau crête stéréo L / R en temps réel", "Real-time stereo L / R peak meter"))

            IconButton(
                symbol: "dot.scope",
                helpText: L("Magnétisme (N)", "Snapping (N)"),
                active: model.snapping,
                tint: Color(nsColor: Theme.snapGuide)
            ) {
                model.snapping.toggle()
            }

            HStack(spacing: 2) {
                IconButton(symbol: "minus.magnifyingglass", helpText: L("Zoom arrière (-)", "Zoom Out (-)")) {
                    onZoomOut()
                }
                IconButton(symbol: "arrow.left.and.right.square", helpText: L("Basculer le zoom intelligent (Z)", "Toggle Smart Zoom (Z)")) {
                    onZoomFit()
                }
                IconButton(symbol: "plus.magnifyingglass", helpText: L("Zoom avant (+)", "Zoom In (+)")) {
                    onZoomIn()
                }
            }

            IconButton(
                symbol: "sidebar.right",
                helpText: L("Afficher/Masquer l'inspecteur (⌥⌘I)", "Show/Hide Inspector (⌥⌘I)"),
                active: model.showInspector
            ) {
                model.showInspector.toggle()
            }

            TextButton(
                title: L("Exporter…", "Export…"),
                symbol: "square.and.arrow.up",
                prominent: true,
                disabled: !model.store.project.hasContent
            ) {
                model.showExportSheet = true
            }
        }
    }
}

/// Isolated leaf view for the live 60/120 Hz timecode readout so `TransportView` does not re-render on every frame.
private struct TransportTimecodeBadge: View {
    let engine: PlaybackEngine
    let totalDuration: Double
    let hasMIDITracks: Bool
    let bpm: Double

    var body: some View {
        HStack(spacing: 5) {
            Text(TimeFormat.timecode(engine.currentTime))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(nsColor: Theme.text))
                .lineLimit(1)
            Text("/")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(nsColor: Theme.textFaint))
            Text(TimeFormat.timecode(totalDuration))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Color(nsColor: Theme.textDim))
                .lineLimit(1)
            if hasMIDITracks {
                Text("· \(Int(bpm)) BPM")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(nsColor: Theme.accent))
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.black.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

/// Isolated leaf view for the live stereo level meter so `TransportView` does not re-render on every meter tick.
private struct TransportMeterWrapper: View {
    let engine: PlaybackEngine

    var body: some View {
        StereoMeterView(peakLeft: engine.meterLeft, peakRight: engine.meterRight)
    }
}
