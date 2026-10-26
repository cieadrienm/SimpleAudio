import AppKit
import SwiftUI
import SimpleAudioCore

struct HelpManualSheet: View {
    let openShortcuts: () -> Void
    let close: () -> Void

    enum SectionID: String, CaseIterable, Identifiable {
        case quickStart
        case editingAndFades
        case multitrackAndDSP
        case exportFormats
        case oscAndMCP

        var id: String { rawValue }

        var title: String {
            switch self {
            case .quickStart: return L("Démarrage rapide", "Quick Start")
            case .editingAndFades: return L("Édition & Fondus", "Editing & Fades")
            case .multitrackAndDSP: return L("Multipiste & Traitement", "Multitrack & DSP")
            case .exportFormats: return L("Export multi-format", "Multi-format Export")
            case .oscAndMCP: return L("OSC, API HTTP & MCP", "OSC, HTTP API & MCP")
            }
        }

        var icon: String {
            switch self {
            case .quickStart: return "play.circle"
            case .editingAndFades: return "scissors"
            case .multitrackAndDSP: return "slider.horizontal.3"
            case .exportFormats: return "square.and.arrow.up"
            case .oscAndMCP: return "antenna.radiowaves.left.and.right"
            }
        }
    }

    @State private var selectedSection: SectionID = .quickStart

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Top Header
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "book.closed")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent.swiftUI)
                Text(L("Guide d’utilisation — SimpleAudio", "User Guide — SimpleAudio"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text.swiftUI)
                Spacer()
                Text(AppVersion.current.shortLabel)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.textFaint.swiftUI)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Theme.header.swiftUI)

            Rectangle()
                .fill(Theme.separator.swiftUI)
                .frame(height: 1)

            // MARK: Sidebar + Content
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 204)
                Rectangle()
                    .fill(Theme.separator.swiftUI)
                    .frame(width: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        sectionContent(selectedSection)
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(Theme.panel.swiftUI)
            }

            Rectangle()
                .fill(Theme.separator.swiftUI)
                .frame(height: 1)

            // MARK: Footer
            HStack {
                Button {
                    close()
                    openShortcuts()
                } label: {
                    Label(L("Raccourcis clavier (⌘/)", "Keyboard Shortcuts (⌘/)"), systemImage: "command")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textDim.swiftUI)

                Spacer()

                Button("OK", action: close)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Theme.header.swiftUI)
        }
        .frame(width: 760, height: 520)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(SectionID.allCases) { section in
                let isSelected = selectedSection == section
                Button {
                    selectedSection = section
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: section.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isSelected ? Theme.accent.swiftUI : Theme.textDim.swiftUI)
                            .frame(width: 16)
                        Text(section.title)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Theme.text.swiftUI : Theme.textDim.swiftUI)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? Theme.laneSelected.swiftUI : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(10)
        .background(Theme.background.swiftUI)
    }

    // MARK: - Section Views

    @ViewBuilder
    private func sectionContent(_ section: SectionID) -> some View {
        switch section {
        case .quickStart:
            quickStartSection
        case .editingAndFades:
            editingAndFadesSection
        case .multitrackAndDSP:
            multitrackAndDSPSection
        case .exportFormats:
            exportFormatsSection
        case .oscAndMCP:
            oscAndMCPSection
        }
    }

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: L("Démarrage rapide", "Quick Start"),
                subtitle: L(
                    "Éditer un fichier audio ou assembler un multipiste en quatre étapes.",
                    "Edit an audio file or assemble a multitrack session in four steps."
                )
            )

            numberedStep(
                number: "1",
                title: L("Ouvrir ou combiner des pistes Audio et MIDI", "Open or combine Audio and MIDI tracks"),
                body: L(
                    "Glissez-déposez des fichiers audio (WAV, AIFF, M4A, MP3, FLAC, CAF), des fichiers MIDI (.mid) ou des banques SoundFont (.sf2 / .dls) directement depuis le Finder. Ajoutez à tout moment une piste Audio (+ Audio) ou une piste MIDI (+ MIDI).",
                    "Drag and drop audio files (WAV, AIFF, M4A, MP3, FLAC, CAF), MIDI files (.mid), or SoundFont banks (.sf2 / .dls) straight from Finder. Add an Audio track (+ Audio) or MIDI track (+ MIDI) at any time."
                )
            )
            numberedStep(
                number: "2",
                title: L("Naviguer en 120 Hz et zoomer avec Z (3 niveaux sur marqueur)", "Navigate at 120 Hz and zoom with Z (3 marker levels)"),
                body: L(
                    "Lancez la lecture avec Espace. Appuyez sur Z pour basculer entre la vue d’ensemble et le zoom sur le curseur — ou, lorsqu'un marqueur est sélectionné, cycler entre 3 niveaux : 15 s autour du marqueur → section jusqu'au marqueur suivant → piste entière.",
                    "Press Space to play. Press Z to toggle between overview and playhead zoom — or, when a marker is selected, cycle through 3 zoom levels: 15 s around marker → section to next marker → full project."
                )
            )
            numberedStep(
                number: "3",
                title: L("Éditer les formes d'onde et le Piano-Roll MIDI (P)", "Edit waveforms and the MIDI Piano Roll (P)"),
                body: L(
                    "Scindez les clips ou notes avec B, ajustez les fondus sur les clips audio, ou dépliez le Piano-Roll d'une piste MIDI (bouton 🎹 ou touche P) pour dessiner des notes (double-clic), les déplacer, les quantifier (Q) ou les transposer (↑/↓).",
                    "Split clips or notes with B, adjust fades on audio clips, or expand a MIDI track's Piano Roll (🎹 button or P key) to draw notes (double-click), move them, quantize (Q) or transpose (↑/↓)."
                )
            )
            numberedStep(
                number: "4",
                title: L("Convertir MIDI → Audio et exporter (⌘E)", "Bounce MIDI → Audio and export (⌘E)"),
                body: L(
                    "Convertissez n'importe quelle piste MIDI en piste Audio WAV d'un clic dans l'inspecteur ou au clic droit, ou exportez le mixage hybride Audio + MIDI en WAV, AIFF, CAF, M4A, ALAC, FLAC, MP3 ou .mid.",
                    "Convert any MIDI track into a WAV Audio track with one click in the inspector or context menu, or export your hybrid Audio + MIDI mix to WAV, AIFF, CAF, M4A, ALAC, FLAC, MP3 or .mid."
                )
            )

            calloutBox(
                icon: "arrow.uturn.backward.circle",
                tint: Theme.meterSafe,
                title: L("Édition 100 % non destructive", "100% Non-Destructive Editing"),
                text: L(
                    "Toutes les découpes, glissements, fondus et variations de gain opèrent en mémoire sans jamais altérer vos fichiers sources sur le disque. Chaque geste constitue une étape d’annulation unique (⌘Z / ⇧⌘Z).",
                    "All cuts, slips, fades, and gain changes happen in memory without ever altering your source files on disk. Every gesture is a single undoable step (⌘Z / ⇧⌘Z)."
                )
            )
        }
    }

    private var editingAndFadesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: L("Édition sur la timeline & Fondus", "Timeline Editing & Fades"),
                subtitle: L(
                    "Gestes directs à la souris, sélection de plage temporelle et courbes de fondu.",
                    "Direct mouse gestures, time range selection, and fade curves."
                )
            )

            bulletList([
                (
                    L("Déplacer un clip (glisser le corps)", "Move a clip (drag body)"),
                    L("Glissez horizontalement pour déplacer le clip dans le temps (avec magnétisme N sur les coupes, marqueurs et la tête de lecture) ou verticalement pour le changer de piste.", "Drag horizontally to move a clip in time (with N snapping to cuts, markers, and playhead) or vertically to move it across tracks.")
                ),
                (
                    L("Rogner l’entrée ou la sortie (glisser les bords)", "Trim in or out point (drag edges)"),
                    L("Approchez le curseur du bord gauche ou droit d’un clip pour ajuster son point d’entrée ou de sortie sans déplacer le reste du clip (ou utilisez [ et ] au clavier).", "Hover near the left or right edge of a clip to trim its start or end without shifting the clip (or use [ and ] on the keyboard).")
                ),
                (
                    L("Glisser le contenu source — Slip (⌥-glisser)", "Slip source content (⌥-drag)"),
                    L("Maintenez Option (⌥) en glissant le corps d’un clip pour faire défiler l’audio source à l’intérieur des bornes du clip sans changer sa position sur la timeline.", "Hold Option (⌥) while dragging a clip body to slip the underlying source audio inside the clip boundaries without changing its timeline position.")
                ),
                (
                    L("Sélectionner une plage temporelle (I / O ou ⇧-glisser)", "Select a time range (I / O or ⇧-drag)"),
                    L("Glissez dans une zone vide (ou en maintenant ⇧ sur un clip ou la règle) pour définir une plage [In, Out], ou double-cliquez sur un clip pour sélectionner exactement sa durée. Les actions Copier (⌘C), Couper (⌘X), Supprimer (⌫), Rogner (⌘T), Silence (⇧⌘M) et Boucle (L) agissent alors sur cette plage.", "Drag in empty space (or hold ⇧ on a clip or ruler) to define an [In, Out] range, or double-click a clip to select its exact span. Copy (⌘C), Cut (⌘X), Delete (⌫), Crop (⌘T), Silence (⇧⌘M), and Loop (L) then operate on that range.")
                ),
                (
                    L("Poignées de fondu & 4 courbes", "Fade handles & 4 curve shapes"),
                    L("Tirez les pastilles situées aux coins supérieurs gauche et droit d’un clip pour régler le fondu d’entrée et de sortie (ou ⌃I / ⌃O pour un fondu rapide de 0,5 s). Choisissez la forme de courbe dans l’inspecteur ou au clic droit : Cosinus (courbe en S douce), Linéaire, Exponentiel ou Logarithmique.", "Drag the circular handles at the top-left and top-right corners of a clip to adjust fade-in and fade-out (or press ⌃I / ⌃O for a quick 0.5 s fade). Choose the curve shape in the inspector or context menu: Cosine (smooth S-curve), Linear, Exponential, or Logarithmic.")
                ),
                (
                    L("Fondu enchaîné (Crossfade, touche X)", "Crossfade (X key)"),
                    L("Sélectionnez deux clips consécutifs sur la même piste et appuyez sur X pour créer automatiquement un fondu enchaîné équilibré.", "Select two adjacent clips on the same track and press X to automatically create a balanced crossfade.")
                ),
            ])
        }
    }

    private var multitrackAndDSPSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: L("Multipiste & Traitement audio", "Multitrack & Audio Processing"),
                subtitle: L(
                    "Contrôles de piste, affichage stéréo L/R et outils d’analyse.",
                    "Track controls, stereo L/R display, and analysis tools."
                )
            )

            bulletList([
                (
                    L("En-têtes de piste (M, S, L/R, Gain, Pan)", "Track headers (M, S, L/R, Gain, Pan)"),
                    L("Chaque piste dispose de boutons Muet (M), Solo (S), d’une bascule d’affichage stéréo séparé Haut/Bas (L/R), ainsi que de réglages glissables de Gain (-60 à +24 dB, double-clic pour 0 dB) et de Panoramique (100L à 100R, double-clic pour centrer).", "Each track features Mute (M), Solo (S), top/bottom split stereo display toggle (L/R), and draggable Gain (-60 to +24 dB, double-click for 0 dB) and Pan (100L to 100R, double-click to center) controls.")
                ),
                (
                    L("Piste unique plein écran vs Multipiste", "Full-height single track vs Multitrack"),
                    L("Lorsqu’un projet ne comporte qu’une seule piste, celle-ci occupe automatiquement toute la hauteur de la timeline pour un montage de précision façon éditeur d’onde.", "When a project has a single track, it automatically expands to fill the timeline height for precision waveform editing.")
                ),
                (
                    L("Normalisation crête (-0.1 dBFS, ⇧⌘N)", "Peak normalization (-0.1 dBFS, ⇧⌘N)"),
                    L("Analyse instantanément l’échantillon maximal de la portion audible du clip et ajuste son gain pour atteindre -0.1 dBFS sans écrêtage.", "Instantly analyzes the peak sample of the audible clip region and adjusts clip gain to reach -0.1 dBFS without clipping.")
                ),
                (
                    L("Élagage automatique des silences", "Automatic silence stripping"),
                    L("Détecte les silences (-42 dBFS) au début et à la fin des clips sélectionnés et resserre automatiquement leurs points d’entrée et de sortie.", "Detects silence (-42 dBFS) at the start and end of selected clips and automatically tightens their in and out points.")
                ),
                (
                    L("Inversion du sens de lecture (⌘R)", "Reverse playback (⌘R)"),
                    L("Lit le clip sélectionné à l’envers en temps réel (et lors de l’export) avec inversion symétrique de l’affichage de la forme d’onde.", "Plays the selected clip backwards in real time (and on export) with symmetrical waveform display reversal.")
                ),
            ])
        }
    }

    private var exportFormatsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: L("Export multi-format & Stems", "Multi-format Export & Stems"),
                subtitle: L(
                    "Rendu hors-ligne haute précision et formats disponibles (⌘E).",
                    "High-precision offline rendering and available formats (⌘E)."
                )
            )

            bulletList([
                (
                    L("Formats natifs CoreAudio & FFmpeg", "Native CoreAudio & FFmpeg formats"),
                    L("Exportez en WAV (16 bits, 24 bits ou 32 bits flottant), AIFF, CAF, M4A (AAC), ALAC (Apple Lossless), FLAC ou MP3 (via FFmpeg si présent).", "Export to WAV (16-bit, 24-bit, or 32-bit float), AIFF, CAF, M4A (AAC), ALAC (Apple Lossless), FLAC, or MP3 (via FFmpeg if installed).")
                ),
                (
                    L("Fréquence d’échantillonnage & Canaux", "Sample rate & Channels"),
                    L("Choisissez 44.1 kHz, 48 kHz ou 96 kHz, en Stéréo (2 canaux) ou Mono (1 canal).", "Choose 44.1 kHz, 48 kHz, or 96 kHz, in Stereo (2 channels) or Mono (1 channel).")
                ),
                (
                    L("Normalisation au rendu", "Render normalization"),
                    L("Appliquez au choix aucune normalisation, une normalisation Crête (-0.1 dBFS) ou une normalisation de sonie intégrée EBU R128 (-14 LUFS).", "Choose between as-is level, Peak normalization (-0.1 dBFS), or EBU R128 integrated loudness normalization (-14 LUFS).")
                ),
                (
                    L("Export de la plage In/Out ou Stems par piste", "In/Out range or per-track Stems export"),
                    L("Exportez soit le projet entier, soit uniquement la plage temporelle sélectionnée [In, Out], ou cochez « Pistes séparées (Stems) » pour générer un fichier audio par piste.", "Export either the full project, only the selected [In, Out] time range, or choose “Separate Tracks (Stems)” to render one audio file per track.")
                ),
            ])
        }
    }

    private var oscAndMCPSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: L("OSC, API HTTP & Serveur MCP", "OSC, HTTP API & MCP Server"),
                subtitle: L(
                    "Interfaçage temps réel avec OSCScore, Montage, scripts et agents IA.",
                    "Real-time interfacing with OSCScore, Montage, scripts, and AI agents."
                )
            )

            topicBlock(
                title: L("Contrôle OSC (UDP :9110 par défaut)", "OSC Control (UDP :9110 by default)"),
                body: L(
                    "SimpleAudio écoute en UDP sur le port 9110 (configurable dans Réglages ⌘, ou via SIMPLEAUDIO_OSC_IN_PORT) :",
                    "SimpleAudio listens over UDP on port 9110 (configurable in Settings ⌘, or via SIMPLEAUDIO_OSC_IN_PORT):"
                )
            )

            bulletList([
                (
                    "/simpleaudio/play · /pause · /toggle · /stop · /rewind",
                    L("Contrôle immédiat du transport.", "Immediate transport control.")
                ),
                (
                    L("/simpleaudio/seek <secondes>", "/simpleaudio/seek <seconds>"),
                    L("Déplace la tête de lecture à la position donnée en secondes.", "Moves the playhead to the given position in seconds.")
                ),
                (
                    "/simpleaudio/loop <start> <end>",
                    L("Active la boucle entre deux temps (ou sans argument pour la couper).", "Enables looping between two times (or without arguments to disable).")
                ),
                (
                    "/simpleaudio/track/<index>/gain <dB> · /pan <-1..1> · /mute <0|1> · /solo <0|1>",
                    L("Pilote en temps réel le mixage d’une piste (index 1..N ou 0..N-1).", "Controls track mixing in real time (index 1..N or 0..N-1).")
                ),
                (
                    "/simpleaudio/clip/<index>/gain <dB> · /fadein <s> · /fadeout <s>",
                    L("Ajuste le gain ou les fondus d’un clip à distance.", "Adjusts clip gain or fades remotely.")
                ),
                (
                    L("/simpleaudio/marker/jump <nomOuIndex> · /export <chemin>", "/simpleaudio/marker/jump <nameOrIndex> · /export <path>"),
                    L("Saute à un marqueur ou déclenche un export disque.", "Jumps to a marker or triggers a disk export.")
                ),
            ])

            topicBlock(
                title: L("API HTTP locale (127.0.0.1:17910/v1) & MCP", "Local HTTP API (127.0.0.1:17910/v1) & MCP"),
                body: L(
                    "L’API HTTP expose l’état complet (GET /v1/state), le document JSON (GET/PUT /v1/document), les lots d’édition atomiques (POST /v1/edit), les formes d’onde (GET /v1/waveform), la détection des silences (GET /v1/silences), l’export (POST /v1/export) et la capture PNG (GET /v1/snapshot.png). Le binaire compagnon simpleaudio-mcp intégré au bundle permet aux agents MCP (Claude Code, etc.) d’inspecter et d’éditer le son en direct.",
                    "The HTTP API exposes full state (GET /v1/state), JSON document (GET/PUT /v1/document), atomic edit batches (POST /v1/edit), waveforms (GET /v1/waveform), silence detection (GET /v1/silences), export (POST /v1/export), and PNG snapshots (GET /v1/snapshot.png). The bundled simpleaudio-mcp companion binary lets MCP agents (Claude Code, etc.) inspect and edit audio live."
                )
            )
        }
    }

    // MARK: - Reusable Building Blocks

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text.swiftUI)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim.swiftUI)
            Rectangle()
                .fill(Theme.separator.swiftUI)
                .frame(height: 1)
                .padding(.top, 6)
        }
    }

    private func numberedStep(number: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.accent.swiftUI)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(Theme.accent.swiftUI.opacity(0.14))
                )
                .overlay(
                    Circle()
                        .strokeBorder(Theme.accent.swiftUI.opacity(0.35), lineWidth: 1)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text.swiftUI)
                Text(body)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textDim.swiftUI)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
        }
    }

    private func topicBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.text.swiftUI)
            Text(body)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textDim.swiftUI)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
    }

    private func bulletList(_ items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items, id: \.0) { title, detail in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(Theme.accent.swiftUI)
                        .frame(width: 5, height: 5)
                        .padding(.top, 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.text.swiftUI)
                        Text(detail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textDim.swiftUI)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(1.5)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.lane.swiftUI)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func calloutBox(icon: String, tint: NSColor, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint.swiftUI)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.text.swiftUI)
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textDim.swiftUI)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(tint.swiftUI.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(tint.swiftUI.opacity(0.25), lineWidth: 1)
        )
    }
}
