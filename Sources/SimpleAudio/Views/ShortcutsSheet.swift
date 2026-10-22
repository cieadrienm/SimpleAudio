import SwiftUI

struct ShortcutsSheet: View {
    let close: () -> Void

    static let groups: [(String, [(String, String)])] = [
        ("Navigation & Zoom", [
            ("Espace", "Lecture / Pause"),
            ("↩  ou  ↖", "Retour au début (0:00)"),
            ("L  ou  ⌘L", "Activer / Désactiver la boucle"),
            ("←  /  →", "Reculer / Avancer pas à pas"),
            ("Z  ou  ⌘0", "Zoom : 15s / Zone / Tout (marqueur) ou Curseur ↔ Tout"),
            ("⇧Z", "Zoomer sur la plage, le clip ou les notes"),
            ("F", "Ajuster tout le projet à la fenêtre"),
            ("+  /  -", "Zoom avant · Zoom arrière (ou ⌘= / ⌘-)"),
            ("⌘-molette", "Zoom continu 120 Hz sous le pointeur (ou pincer)"),
            ("N", "Activer / Désactiver le magnétisme"),
            ("K", "Ajouter un marqueur à la tête de lecture"),
            ("P", "Ouvrir / Réduire le Piano-Roll MIDI"),
        ]),
        ("Édition Audio, MIDI & Plages", [
            ("B  ou  S  ou  ⌘K", "Scinder clip ou notes à la tête de lecture"),
            ("Double-clic (MIDI)", "Créer une note dans le Piano-Roll"),
            ("Q", "Quantifier les notes MIDI sur la grille (1/16)"),
            ("↑  /  ↓", "Transposer les notes MIDI (±1 demi-ton)"),
            ("⇧↑  /  ⇧↓", "Transposer les notes MIDI (±1 octave)"),
            ("I  /  O", "Définir le début (In) / la fin (Out) de la plage"),
            ("⌥I  ou  ⎋", "Effacer la sélection"),
            ("⇧-glisser", "Sélectionner une plage temporelle à la souris"),
            ("⌥-glisser", "Glisser l’audio source dans le clip (Slip)"),
            ("⌘C / ⌘X / ⌘V", "Copier / Couper / Coller (plage, clips, notes)"),
            ("⌫  /  ⇧⌫", "Supprimer / Supprimer et raccorder (Ripple)"),
            ("⌘T", "Rogner le projet sur la plage (Crop)"),
        ]),
        ("Fondus, Pistes & Fichier", [
            ("⌃I  /  ⌃O", "Fondu d’entrée / de sortie rapide (0,5 s)"),
            ("X", "Fondu enchaîné (Crossfade) entre 2 clips"),
            ("⇧⌘N", "Normaliser le niveau crête à -0.1 dBFS"),
            ("⌘R", "Inverser le sens de lecture (Reverse)"),
            ("M", "Muet sur les clips, notes ou la piste"),
            ("⌥↑  /  ⌥↓", "Monter / Descendre la piste active (ou glisser l’en-tête)"),
            ("⌥⌘N  /  ⌃⌘N", "Nouvelle piste Audio / Nouvelle piste MIDI"),
            ("⌘O  /  ⌘I", "Ouvrir / Importer Audio, MIDI (.mid) ou .sf2"),
            ("⌘S  /  ⇧⌘S", "Enregistrer / Enregistrer sous…"),
            ("⌘E", "Exporter Audio / MIDI (multi-format & stems)…"),
            ("⌘?  /  ⌘/", "Aide SimpleAudio / Cette liste de raccourcis"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Raccourcis clavier & gestes")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text.swiftUI)
                Spacer()
                Text(AppVersion.current.shortLabel)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.textFaint.swiftUI)
            }

            HStack(alignment: .top, spacing: 24) {
                ForEach(Self.groups, id: \.0) { group in
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

            Text("Astuce : double-cliquez sur un clip pour sélectionner sa plage temporelle, ou tirez les poignées rondes en haut d’un clip pour dessiner un fondu d’entrée / sortie.")
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
