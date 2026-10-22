import AppKit
import SwiftUI

struct HelpManualSheet: View {
    let openShortcuts: () -> Void
    let close: () -> Void

    enum SectionID: String, CaseIterable, Identifiable {
        case quickStart = "Démarrage rapide"
        case editingAndFades = "Édition & Fondus"
        case multitrackAndDSP = "Multipiste & Traitement"
        case exportFormats = "Export multi-format"
        case oscAndMCP = "OSC, API HTTP & MCP"

        var id: String { rawValue }

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
                Text("Guide d’utilisation — SimpleAudio")
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
                    Label("Raccourcis clavier (⌘/)", systemImage: "command")
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
                        Text(section.rawValue)
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
                title: "Démarrage rapide",
                subtitle: "Éditer un fichier audio ou assembler un multipiste en quatre étapes."
            )

            numberedStep(
                number: "1",
                title: "Ouvrir ou combiner des pistes Audio et MIDI",
                body: "Glissez-déposez des fichiers audio (WAV, AIFF, M4A, MP3, FLAC, CAF), des fichiers MIDI (.mid) ou des banques SoundFont (.sf2 / .dls) directement depuis le Finder. Ajoutez à tout moment une piste Audio (+ Audio) ou une piste MIDI (+ MIDI)."
            )
            numberedStep(
                number: "2",
                title: "Naviguer en 120 Hz et zoomer avec Z (3 niveaux sur marqueur)",
                body: "Lancez la lecture avec Espace. Appuyez sur Z pour basculer entre la vue d’ensemble et le zoom sur le curseur — ou, lorsqu'un marqueur est sélectionné, cycler entre 3 niveaux : 15 s autour du marqueur → section jusqu'au marqueur suivant → piste entière."
            )
            numberedStep(
                number: "3",
                title: "Éditer les formes d'onde et le Piano-Roll MIDI (P)",
                body: "Scindez les clips ou notes avec B, ajustez les fondus sur les clips audio, ou dépliez le Piano-Roll d'une piste MIDI (bouton 🎹 ou touche P) pour dessiner des notes (double-clic), les déplacer, les quantifier (Q) ou les transposer (↑/↓)."
            )
            numberedStep(
                number: "4",
                title: "Convertir MIDI → Audio et exporter (⌘E)",
                body: "Convertissez n'importe quelle piste MIDI en piste Audio WAV d'un clic dans l'inspecteur ou au clic droit, ou exportez le mixage hybride Audio + MIDI en WAV, AIFF, CAF, M4A, ALAC, FLAC, MP3 ou .mid."
            )

            calloutBox(
                icon: "arrow.uturn.backward.circle",
                tint: Theme.meterSafe,
                title: "Édition 100 % non destructive",
                text: "Toutes les découpes, glissements, fondus et variations de gain opèrent en mémoire sans jamais altérer vos fichiers sources sur le disque. Chaque geste constitue une étape d’annulation unique (⌘Z / ⇧⌘Z)."
            )
        }
    }

    private var editingAndFadesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: "Édition sur la timeline & Fondus",
                subtitle: "Gestes directs à la souris, sélection de plage temporelle et courbes de fondu."
            )

            bulletList([
                ("Déplacer un clip (glisser le corps)", "Glissez horizontalement pour déplacer le clip dans le temps (avec magnétisme N sur les coupes, marqueurs et la tête de lecture) ou verticalement pour le changer de piste."),
                ("Rogner l’entrée ou la sortie (glisser les bords)", "Approchez le curseur du bord gauche ou droit d’un clip pour ajuster son point d’entrée ou de sortie sans déplacer le reste du clip (ou utilisez [ et ] au clavier)."),
                ("Glisser le contenu source — Slip (⌥-glisser)", "Maintenez Option (⌥) en glissant le corps d’un clip pour faire défiler l’audio source à l’intérieur des bornes du clip sans changer sa position sur la timeline."),
                ("Sélectionner une plage temporelle (I / O ou ⇧-glisser)", "Glissez dans une zone vide (ou en maintenant ⇧ sur un clip ou la règle) pour définir une plage [In, Out], ou double-cliquez sur un clip pour sélectionner exactement sa durée. Les actions Copier (⌘C), Couper (⌘X), Supprimer (⌫), Rogner (⌘T), Silence (⇧⌘M) et Boucle (L) agissent alors sur cette plage."),
                ("Poignées de fondu & 4 courbes", "Tirez les pastilles situées aux coins supérieurs gauche et droit d’un clip pour régler le fondu d’entrée et de sortie (ou ⌃I / ⌃O pour un fondu rapide de 0,5 s). Choisissez la forme de courbe dans l’inspecteur ou au clic droit : Cosinus (courbe en S douce), Linéaire, Exponentiel ou Logarithmique."),
                ("Fondu enchaîné (Crossfade, touche X)", "Sélectionnez deux clips consécutifs sur la même piste et appuyez sur X pour créer automatiquement un fondu enchaîné équilibré.")
            ])
        }
    }

    private var multitrackAndDSPSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: "Multipiste & Traitement audio",
                subtitle: "Contrôles de piste, affichage stéréo L/R et outils d’analyse."
            )

            bulletList([
                ("En-têtes de piste (M, S, L/R, Gain, Pan)", "Chaque piste dispose de boutons Muet (M), Solo (S), d’une bascule d’affichage stéréo séparé Haut/Bas (L/R), ainsi que de réglages glissables de Gain (-60 à +24 dB, double-clic pour 0 dB) et de Panoramique (100L à 100R, double-clic pour centrer)."),
                ("Piste unique plein écran vs Multipiste", "Lorsqu’un projet ne comporte qu’une seule piste, celle-ci occupe automatiquement toute la hauteur de la timeline pour un montage de précision façon éditeur d’onde."),
                ("Normalisation crête (-0.1 dBFS, ⇧⌘N)", "Analyse instantanément l’échantillon maximal de la portion audible du clip et ajuste son gain pour atteindre -0.1 dBFS sans écrêtage."),
                ("Élagage automatique des silences", "Détecte les silences (-42 dBFS) au début et à la fin des clips sélectionnés et resserre automatiquement leurs points d’entrée et de sortie."),
                ("Inversion du sens de lecture (⌘R)", "Lit le clip sélectionné à l’envers en temps réel (et lors de l’export) avec inversion symétrique de l’affichage de la forme d’onde.")
            ])
        }
    }

    private var exportFormatsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: "Export multi-format & Stems",
                subtitle: "Rendu hors-ligne haute précision et formats disponibles (⌘E)."
            )

            bulletList([
                ("Formats natifs CoreAudio & FFmpeg", "Exportez en WAV (16 bits, 24 bits ou 32 bits flottant), AIFF, CAF, M4A (AAC), ALAC (Apple Lossless), FLAC ou MP3 (via FFmpeg si présent)."),
                ("Fréquence d’échantillonnage & Canaux", "Choisissez 44.1 kHz, 48 kHz ou 96 kHz, en Stéréo (2 canaux) ou Mono (1 canal)."),
                ("Normalisation au rendu", "Appliquez au choix aucune normalisation, une normalisation Crête (-0.1 dBFS) ou une normalisation de sonie intégrée EBU R128 (-14 LUFS)."),
                ("Export de la plage In/Out ou Stems par piste", "Exportez soit le projet entier, soit uniquement la plage temporelle sélectionnée [In, Out], ou cochez « Exporter les pistes séparées (Stems) » pour générer un fichier audio par piste.")
            ])
        }
    }

    private var oscAndMCPSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: "OSC, API HTTP & Serveur MCP",
                subtitle: "Interfaçage temps réel avec OSCScore, Montage, scripts et agents IA."
            )

            topicBlock(
                title: "Contrôle OSC (UDP :9110 par défaut)",
                body: "SimpleAudio écoute en UDP sur le port 9110 (configurable dans Réglages ⌘, ou via SIMPLEAUDIO_OSC_IN_PORT) :"
            )

            bulletList([
                ("/simpleaudio/play · /pause · /toggle · /stop · /rewind", "Contrôle immédiat du transport."),
                ("/simpleaudio/seek <secondes>", "Déplace la tête de lecture à la position donnée en secondes."),
                ("/simpleaudio/loop <start> <end>", "Active la boucle entre deux temps (ou sans argument pour la couper)."),
                ("/simpleaudio/track/<index>/gain <dB> · /pan <-1..1> · /mute <0|1> · /solo <0|1>", "Pilote en temps réel le mixage d’une piste (index 1..N ou 0..N-1)."),
                ("/simpleaudio/clip/<index>/gain <dB> · /fadein <s> · /fadeout <s>", "Ajuste le gain ou les fondus d’un clip à distance."),
                ("/simpleaudio/marker/jump <nomOuIndex> · /export <chemin>", "Saute à un marqueur ou déclenche un export disque.")
            ])

            topicBlock(
                title: "API HTTP locale (127.0.0.1:17910/v1) & MCP",
                body: "L’API HTTP expose l’état complet (GET /v1/state), le document JSON (GET/PUT /v1/document), les lots d’édition atomiques (POST /v1/edit), les formes d’onde (GET /v1/waveform), la détection des silences (GET /v1/silences), l’export (POST /v1/export) et la capture PNG (GET /v1/snapshot.png). Le binaire compagnon simpleaudio-mcp intégré au bundle permet aux agents MCP (Claude Code, etc.) d’inspecter et d’éditer le son en direct."
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
