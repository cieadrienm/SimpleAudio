import SwiftUI
import SimpleAudioCore

struct ShortcutsSheet: View {
    let close: () -> Void

    private var groups: [(String, [(String, String)])] {
        [
            (L("Navigation & Zoom", "Navigation & Zoom"), [
                (L("Espace", "Space"), L("Lecture / Pause", "Play / Pause")),
                (L("↩  ou  ↖", "↩  or  ↖"), L("Retour au début (0:00)", "Rewind to Start (0:00)")),
                (L("L  ou  ⌘L", "L  or  ⌘L"), L("Activer / Désactiver la boucle", "Toggle Loop Playback")),
                ("←  /  →", L("Reculer / Avancer pas à pas", "Step Backward / Forward")),
                (L("Z  ou  ⌘0", "Z  or  ⌘0"), L("Zoom : 15s / Zone / Tout (marqueur) ou Curseur ↔ Tout", "Zoom: 15s / Section / All (marker) or Playhead ↔ Fit")),
                ("⇧Z", L("Zoomer sur la plage, le clip ou les notes", "Zoom to range, clip or notes")),
                ("F", L("Ajuster tout le projet à la fenêtre", "Zoom entire project to fit window")),
                ("+  /  -", L("Zoom avant · Zoom arrière (ou ⌘= / ⌘-)", "Zoom In · Zoom Out (or ⌘= / ⌘-)")),
                (L("⌘-molette", "⌘-scroll"), L("Zoom continu 120 Hz sous le pointeur (ou pincer)", "Continuous 120 Hz zoom under pointer (or pinch)")),
                ("N", L("Activer / Désactiver le magnétisme", "Toggle Snapping")),
                ("K", L("Ajouter un marqueur à la tête de lecture", "Add Marker at Playhead")),
                ("P", L("Ouvrir / Réduire le Piano-Roll MIDI", "Expand / Collapse MIDI Piano Roll")),
            ]),
            (L("Édition Audio, MIDI & Plages", "Audio, MIDI & Range Editing"), [
                (L("B  ou  S  ou  ⌘K", "B  or  S  or  ⌘K"), L("Scinder clip ou notes à la tête de lecture", "Split clip or notes at playhead")),
                (L("Double-clic (MIDI)", "Double-click (MIDI)"), L("Créer une note dans le Piano-Roll", "Create note in Piano Roll")),
                ("Q", L("Quantifier les notes MIDI sur la grille (1/16)", "Quantize MIDI notes to 1/16th grid")),
                ("↑  /  ↓", L("Transposer les notes MIDI (±1 demi-ton)", "Transpose MIDI notes (±1 semitone)")),
                ("⇧↑  /  ⇧↓", L("Transposer les notes MIDI (±1 octave)", "Transpose MIDI notes (±1 octave)")),
                ("I  /  O", L("Définir le début (In) / la fin (Out) de la plage", "Set Range In / Out point")),
                (L("⌥I  ou  ⎋", "⌥I  or  ⎋"), L("Effacer la sélection", "Clear selection")),
                (L("⇧-glisser", "⇧-drag"), L("Sélectionner une plage temporelle à la souris", "Select time range with mouse")),
                (L("⌥-glisser", "⌥-drag"), L("Glisser l’audio source dans le clip (Slip)", "Slip source audio inside clip")),
                ("⌘C / ⌘X / ⌘V", L("Copier / Couper / Coller (plage, clips, notes)", "Copy / Cut / Paste (range, clips, notes)")),
                ("⌫  /  ⇧⌫", L("Supprimer / Supprimer et raccorder (Ripple)", "Delete / Ripple Delete")),
                ("⌘T", L("Rogner le projet sur la plage (Crop)", "Crop project to range")),
            ]),
            (L("Fondus, Pistes & Fichier", "Fades, Tracks & File"), [
                ("⌃I  /  ⌃O", L("Fondu d’entrée / de sortie rapide (0,5 s)", "Quick Fade In / Out (0.5 s)")),
                ("X", L("Fondu enchaîné (Crossfade) entre 2 clips", "Crossfade between 2 adjacent clips")),
                ("⇧⌘N", L("Normaliser le niveau crête à -0.1 dBFS", "Normalize peak level to -0.1 dBFS")),
                ("⌘R", L("Inverser le sens de lecture (Reverse)", "Reverse clip playback")),
                ("M", L("Muet sur les clips, notes ou la piste", "Mute selected clips, notes or track")),
                ("⌥↑  /  ⌥↓", L("Monter / Descendre la piste active (ou glisser l’en-tête)", "Move active track Up / Down (or drag header)")),
                ("⌥⌘N  /  ⌃⌘N", L("Nouvelle piste Audio / Nouvelle piste MIDI", "New Audio Track / New MIDI Track")),
                ("⌘O  /  ⌘I", L("Ouvrir / Importer Audio, MIDI (.mid) ou .sf2", "Open / Import Audio, MIDI (.mid) or .sf2")),
                ("⌘S  /  ⇧⌘S", L("Enregistrer / Enregistrer sous…", "Save / Save As…")),
                ("⌘E", L("Exporter Audio / MIDI (multi-format & stems)…", "Export Audio / MIDI (multi-format & stems)…")),
                ("⌘?  /  ⌘/", L("Aide SimpleAudio / Cette liste de raccourcis", "SimpleAudio Help / This shortcuts sheet")),
            ]),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Raccourcis clavier & gestes", "Keyboard Shortcuts & Gestures"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text.swiftUI)
                Spacer()
                Text(AppVersion.current.shortLabel)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.textFaint.swiftUI)
            }

            HStack(alignment: .top, spacing: 24) {
                ForEach(groups, id: \.0) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.0.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .kerning(0.8)
                            .foregroundStyle(Theme.textFaint.swiftUI)
                            .padding(.bottom, 2)
                        ForEach(group.1, id: \.0) { key, text in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(key)
                                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(Theme.accent.swiftUI)
                                    .frame(width: 96, alignment: .leading)
                                Text(text)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Theme.textDim.swiftUI)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(width: 265, alignment: .topLeading)
                }
            }

            Text(L(
                "Astuce : double-cliquez sur un clip pour sélectionner sa plage temporelle, ou tirez les poignées rondes en haut d’un clip pour dessiner un fondu d’entrée / sortie.",
                "Tip: double-click a clip to select its time range, or drag the top corner handles of a clip to shape fade-in / fade-out curves."
            ))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textFaint.swiftUI)

            HStack {
                Spacer()
                Button("OK", action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
    }
}
