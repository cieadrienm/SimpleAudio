import SwiftUI
import SimpleAudioCore
import SimpleAudioEngine

struct TransportView: View {
    @Bindable var model: AppModel
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onZoomFit: () -> Void

    var body: some View {
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
                helpText: "Afficher/Masquer la barre latérale",
                active: model.showSidebar
            ) {
                model.showSidebar.toggle()
            }

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 2)

            IconButton(symbol: "backward.end.fill", helpText: "Retour au début (Entrée)") {
                model.seek(to: 0)
            }
            IconButton(
                symbol: model.transportPlaying ? "pause.fill" : "play.fill",
                helpText: "Lecture / Pause (Espace)",
                active: model.transportPlaying
            ) {
                model.togglePlay()
            }
            IconButton(symbol: "stop.fill", helpText: "Stop") {
                model.stop()
            }
            IconButton(
                symbol: "repeat",
                helpText: "Lecture en boucle (⌘L)",
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
            TextButton(title: "Scinder", symbol: "scissors", compact: true) {
                model.splitAtPlayhead()
            }
            .help("Scinder à la tête de lecture ou aux bornes de la plage (B)")

            if model.activeTrack?.isMIDI == true || !model.selectedNotes.isEmpty {
                TextButton(
                    title: "Piano-Roll",
                    symbol: "pianokeys",
                    prominent: model.activeTrack?.pianoRollExpanded == true,
                    compact: true
                ) {
                    model.toggleSelectedTrackPianoRoll()
                }
                .help("Ouvrir/Réduire le Piano-Roll de la piste MIDI (P)")

                TextButton(title: "Quantifier", symbol: "waveform.path.ecg", compact: true) {
                    model.quantizeSelection(subdivisionBeats: 0.25)
                }
                .help("Quantifier les notes sur la double-croche 1/16 (Q)")
            } else {
                TextButton(title: "Fondu ↗", compact: true) {
                    model.applyFadeIn(duration: 0.5)
                }
                .help("Appliquer un fondu d'entrée sur la plage ou le clip sélectionné")

                TextButton(title: "Fondu ↘", compact: true) {
                    model.applyFadeOut(duration: 0.5)
                }
                .help("Appliquer un fondu de sortie sur la plage ou le clip sélectionné")
            }

            TextButton(
                title: "Rogner",
                symbol: "crop",
                compact: true,
                disabled: model.selectionRange == nil
            ) {
                model.cropToSelection()
            }
            .help("Garder uniquement la plage sélectionnée (⌘T)")

            TextButton(
                title: "Silence",
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
            .help("Silencer la plage sélectionnée ou couper le son du clip / des notes")

            if model.activeTrack?.isMIDI == true {
                soundbankMenu
            } else {
                TextButton(
                    title: "Normaliser",
                    symbol: "waveform",
                    compact: true,
                    disabled: model.selectedClips.isEmpty && model.store.project.allClips.isEmpty
                ) {
                    model.normalizeSelectedClips(targetDB: -0.1)
                }
                .help("Normaliser le niveau crête à -0.1 dBFS")
            }

            IconButton(symbol: "bookmark", helpText: "Ajouter un marqueur (K)") {
                model.addMarkerAtPlayhead()
            }
        }
    }

    private var soundbankMenu: some View {
        Menu {
            Section("Banques General MIDI / Synth") {
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
                Section("SoundFonts récentes (.sf2 / .dls)") {
                    ForEach(recents) { entry in
                        Button(entry.name) {
                            _ = model.loadSoundfont(url: entry.url)
                        }
                    }
                }
            }
            Divider()
            Button("Charger une SoundFont (.sf2 / .dls)…") {
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
        .help("Choisir la banque de sons MIDI (General MIDI ou SoundFont .sf2)")
    }

    private var rightControls: some View {
        HStack(spacing: 6) {
            TransportMeterWrapper(engine: model.engine)
                .help("Niveau crête stéréo L / R en temps réel")

            IconButton(
                symbol: "dot.scope",
                helpText: "Magnétisme (N)",
                active: model.snapping,
                tint: Color(nsColor: Theme.snapGuide)
            ) {
                model.snapping.toggle()
            }

            HStack(spacing: 2) {
                IconButton(symbol: "minus.magnifyingglass", helpText: "Zoom arrière (-)") {
                    onZoomOut()
                }
                IconButton(symbol: "arrow.left.and.right.square", helpText: "Basculer le zoom intelligent (Z)") {
                    onZoomFit()
                }
                IconButton(symbol: "plus.magnifyingglass", helpText: "Zoom avant (+)") {
                    onZoomIn()
                }
            }

            IconButton(
                symbol: "sidebar.right",
                helpText: "Afficher/Masquer l'inspecteur",
                active: model.showInspector
            ) {
                model.showInspector.toggle()
            }

            TextButton(
                title: "Exporter…",
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
