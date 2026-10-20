import SwiftUI

struct ShortcutsSheet: View {
    let close: () -> Void

    static let groups: [(String, [(String, String)])] = [
        ("Navigation & Zoom", [
            ("Espace", "Lecture / Pause"),
            ("↩  ou  ↖", "Retour au début (0:00)"),
            ("L  ou  ⌘L", "Activer / Désactiver la boucle"),
            ("←  /  →", "Reculer / Avancer pas à pas"),
            ("Z  ou  ⌘0", "Basculer Tout voir ↔ Zoom sur le curseur"),
            ("⇧Z", "Zoomer sur la plage ou le clip sélectionné"),
            ("F", "Ajuster tout le projet à la fenêtre"),
            ("+  /  -", "Zoom avant · Zoom arrière (ou ⌘= / ⌘-)"),
            ("⌘-molette", "Zoom continu sous le pointeur (ou pincer)"),
            ("N", "Activer / Désactiver le magnétisme"),
            ("K", "Ajouter un marqueur à la tête de lecture"),
        ]),
        ("Édition & Plages", [
            ("B  ou  S  ou  ⌘K", "Scinder le clip à la tête de lecture"),
            ("I  /  O", "Définir le début (In) / la fin (Out) de la plage"),
            ("⌥I  ou  ⎋", "Effacer la sélection de plage"),
            ("⇧-glisser", "Sélectionner une plage temporelle à la souris"),
            ("⌥-glisser", "Glisser l’audio source dans le clip (Slip)"),
            ("[  /  ]", "Rogner le début / la fin au point de lecture"),
            ("⌘C / ⌘X / ⌘V", "Copier / Couper / Coller (plage ou clips)"),
            ("⌘D", "Dupliquer la sélection"),
            ("⌫  /  ⇧⌫", "Supprimer / Supprimer et raccorder (Ripple)"),
            ("⌘T", "Rogner le projet sur la plage (Crop)"),
            ("⇧⌘M", "Silencer la plage sélectionnée"),
        ]),
        ("Fondus, Pistes & Fichier", [
            ("⌃I  /  ⌃O", "Fondu d’entrée / de sortie rapide (0,5 s)"),
            ("X", "Fondu enchaîné (Crossfade) entre 2 clips"),
            ("⇧⌘N", "Normaliser le niveau crête à -0.1 dBFS"),
            ("⌘R", "Inverser le sens de lecture (Reverse)"),
            ("M", "Muet sur les clips sélectionnés ou la piste"),
            ("⌥⌘N", "Ajouter une nouvelle piste audio"),
            ("⌘O  /  ⌘I", "Ouvrir un projet / Importer des fichiers audio"),
            ("⌘S  /  ⇧⌘S", "Enregistrer / Enregistrer sous…"),
            ("⌘E", "Exporter l’audio (multi-format & stems)…"),
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
