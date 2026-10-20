import SwiftUI
import SimpleAudioCore

struct TransportView: View {
    @Bindable var model: AppModel
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onZoomFit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Left: Sidebar toggle & Transport controls
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

            // Timecode readout
            HStack(spacing: 4) {
                Text(TimeFormat.timecode(model.playhead))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(nsColor: Theme.text))
                    .lineLimit(1)
                Text("/")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(nsColor: Theme.textFaint))
                Text(TimeFormat.timecode(model.store.project.totalDuration))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Color(nsColor: Theme.textDim))
                    .lineLimit(1)
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

            // Active Range Selection pill
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

            Spacer(minLength: 4)

            // Center: Direct Audio Editing Actions
            HStack(spacing: 4) {
                TextButton(title: "Scinder", symbol: "scissors", compact: true) {
                    model.splitAtPlayhead()
                }
                .help("Scinder à la tête de lecture ou aux bornes de la plage (B)")

                TextButton(title: "Fondu ↗", compact: true) {
                    model.applyFadeIn(duration: 0.5)
                }
                .help("Appliquer un fondu d'entrée sur la plage ou le clip sélectionné")

                TextButton(title: "Fondu ↘", compact: true) {
                    model.applyFadeOut(duration: 0.5)
                }
                .help("Appliquer un fondu de sortie sur la plage ou le clip sélectionné")

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
                    disabled: model.selectionRange == nil && model.selectedClips.isEmpty
                ) {
                    if model.selectionRange != nil {
                        model.silenceSelection()
                    } else {
                        model.toggleMuteSelectedClips()
                    }
                }
                .help("Silencer la plage sélectionnée ou couper le son du clip")

                TextButton(
                    title: "Normaliser",
                    symbol: "waveform",
                    compact: true,
                    disabled: model.selectedClips.isEmpty && model.store.project.allClips.isEmpty
                ) {
                    model.normalizeSelectedClips(targetDB: -0.1)
                }
                .help("Normaliser le niveau crête à -0.1 dBFS")

                IconButton(symbol: "bookmark", helpText: "Ajouter un marqueur (M)") {
                    model.addMarkerAtPlayhead()
                }
            }

            Spacer(minLength: 4)

            // Right: Live Stereo Meter, Zoom, Inspector, Export
            HStack(spacing: 6) {
                StereoMeterView(peakLeft: model.peakLeft, peakRight: model.peakRight)
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
                    IconButton(symbol: "arrow.left.and.right.square", helpText: "Basculer Tout voir ↔ Zoom sur le curseur (Z)") {
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
                    disabled: model.store.project.allClips.isEmpty
                ) {
                    model.showExportSheet = true
                }
            }
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
}
