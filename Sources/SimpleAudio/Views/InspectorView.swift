import SwiftUI
import SimpleAudioCore
import SimpleAudioEngine

struct InspectorView: View {
    @Bindable var model: AppModel

    private var project: AudioProject { model.store.project }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let range = model.selectionRange, range.upperBound > range.lowerBound + 1e-4 {
                    rangeSection(range)
                    Divider().overlay(Color(nsColor: Theme.separator))
                }

                if let note = model.primarySelectedNote {
                    noteSection(note)
                    Divider().overlay(Color(nsColor: Theme.separator))
                } else if model.selectedNotes.count > 1 {
                    multiNoteSection()
                    Divider().overlay(Color(nsColor: Theme.separator))
                }

                if let clip = model.primarySelectedClip {
                    clipSection(clip)
                    Divider().overlay(Color(nsColor: Theme.separator))
                } else if model.selectedClips.count > 1 {
                    multiClipSection()
                    Divider().overlay(Color(nsColor: Theme.separator))
                }

                if let track = model.selectedTrack {
                    trackSection(track)
                    Divider().overlay(Color(nsColor: Theme.separator))
                }

                projectSection()
            }
            .padding(12)
        }
        .frame(width: 256)
        .background(Color(nsColor: Theme.panel))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color(nsColor: Theme.separator))
                .frame(width: 1)
        }
    }

    // MARK: 1. Time Range Section

    @ViewBuilder
    private func rangeSection(_ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Plage sélectionnée") {
                Button("Effacer") {
                    model.selectionRange = nil
                }
                .font(.system(size: 10.5))
                .foregroundStyle(Color(nsColor: Theme.textDim))
                .buttonStyle(.plain)
            }

            FieldRow("Début") {
                NumberField(value: range.lowerBound, unit: "s", step: 0.05, range: 0...range.upperBound, decimals: 3) { newStart in
                    model.selectionRange = min(newStart, range.upperBound)...range.upperBound
                }
            }
            FieldRow("Fin") {
                NumberField(value: range.upperBound, unit: "s", step: 0.05, range: range.lowerBound...36000, decimals: 3) { newEnd in
                    model.selectionRange = range.lowerBound...max(newEnd, range.lowerBound)
                }
            }
            FieldRow("Durée") {
                Text(TimeFormat.shortDuration(range.upperBound - range.lowerBound))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Color(nsColor: Theme.rangeSelection))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                TextButton(title: "Copier", symbol: "doc.on.doc", compact: true) {
                    model.copySelection()
                }
                TextButton(title: "Couper", symbol: "scissors", compact: true) {
                    model.cutSelection()
                }
                TextButton(title: "Rogner", symbol: "crop", compact: true) {
                    model.cropToSelection()
                }
                TextButton(title: "Silencer", symbol: "speaker.slash", compact: true) {
                    model.silenceSelection()
                }
                TextButton(title: "Fondu ↗", compact: true) {
                    model.applyFadeIn(duration: 0.5)
                }
                TextButton(title: "Fondu ↘", compact: true) {
                    model.applyFadeOut(duration: 0.5)
                }
            }
        }
    }

    // MARK: 2. Clip Section

    @ViewBuilder
    private func clipSection(_ clip: AudioClip) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader("Clip audio")

            FieldRow("Nom") {
                CommitField(value: clip.name) { newName in
                    model.store.perform("Renommer le clip") { proj in
                        try? Operations.renameClip(&proj, id: clip.id, name: newName)
                    }
                }
            }

            FieldRow("Position") {
                NumberField(value: clip.offset, unit: "s", step: 0.05, range: 0...36000, decimals: 3) { val in
                    model.store.perform("Déplacer le clip") { proj in
                        if let (ti, _) = proj.clipLocation(of: clip.id) {
                            try? Operations.moveClip(&proj, id: clip.id, toTrack: proj.tracks[ti].id, offset: val)
                        }
                    }
                }
            }

            FieldRow("Durée") {
                NumberField(
                    value: clip.duration,
                    unit: "s",
                    step: 0.05,
                    range: AudioClip.minDuration...max(AudioClip.minDuration, clip.sourceDuration - clip.sourceStart),
                    decimals: 3
                ) { val in
                    model.store.perform("Durée du clip") { proj in
                        try? Operations.trimClip(
                            &proj,
                            id: clip.id,
                            offset: clip.offset,
                            sourceStart: clip.sourceStart,
                            duration: val
                        )
                    }
                }
            }

            FieldRow("Entrée src.") {
                NumberField(
                    value: clip.sourceStart,
                    unit: "s",
                    step: 0.05,
                    range: 0...max(0, clip.sourceDuration - clip.duration),
                    decimals: 3
                ) { val in
                    model.store.perform("Glisser la source") { proj in
                        try? Operations.slipClip(&proj, id: clip.id, toSourceStart: val)
                    }
                }
            }

            Divider().overlay(Color(nsColor: Theme.separator)).padding(.vertical, 2)
            SectionHeader("Gain & Fondus")

            FieldRow("Gain") {
                NumberField(value: clip.gainDB, unit: "dB", step: 0.5, range: -60...24, decimals: 1) { val in
                    model.store.perform("Gain du clip") { proj in
                        try? Operations.setClipGain(&proj, id: clip.id, gainDB: val)
                    }
                }
                if abs(clip.gainDB) > 0.05 {
                    Button("0") {
                        model.store.perform("Réinitialiser le gain") { proj in
                            try? Operations.setClipGain(&proj, id: clip.id, gainDB: 0)
                        }
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(nsColor: Theme.accent))
                }
            }

            FieldRow("Pan") {
                NumberField(value: clip.pan, unit: "", step: 0.05, range: -1...1, decimals: 2) { val in
                    model.store.perform("Panoramique du clip") { proj in
                        try? Operations.setClipPan(&proj, id: clip.id, pan: val)
                    }
                }
            }

            FieldRow("Fondu ↗") {
                NumberField(
                    value: clip.fadeIn,
                    unit: "s",
                    step: 0.05,
                    range: 0...max(0, clip.duration - clip.fadeOut),
                    decimals: 2
                ) { val in
                    model.store.perform("Fondu d'entrée") { proj in
                        try? Operations.setFade(&proj, id: clip.id, fadeIn: val)
                    }
                }
            }

            FieldRow("Fondu ↘") {
                NumberField(
                    value: clip.fadeOut,
                    unit: "s",
                    step: 0.05,
                    range: 0...max(0, clip.duration - clip.fadeIn),
                    decimals: 2
                ) { val in
                    model.store.perform("Fondu de sortie") { proj in
                        try? Operations.setFade(&proj, id: clip.id, fadeOut: val)
                    }
                }
            }

            FieldRow("Courbe") {
                Picker("", selection: Binding(
                    get: { clip.fadeShape },
                    set: { shape in
                        model.store.perform("Courbe de fondu") { proj in
                            try? Operations.setFade(&proj, id: clip.id, shape: shape)
                        }
                    }
                )) {
                    ForEach(FadeShape.allCases, id: \.self) { shape in
                        Text(shape.label).tag(shape)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
            }

            HStack(spacing: 6) {
                TextButton(
                    title: clip.mute ? "Muet ✓" : "Muet",
                    symbol: "speaker.slash",
                    prominent: clip.mute,
                    compact: true
                ) {
                    model.toggleMuteSelectedClips()
                }
                TextButton(
                    title: clip.reversed ? "Inversé ✓" : "Inverser",
                    symbol: "arrow.left.arrow.right",
                    prominent: clip.reversed,
                    compact: true
                ) {
                    model.reverseSelectedClips()
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                TextButton(title: "Normaliser", compact: true) {
                    model.normalizeSelectedClips(targetDB: -0.1)
                }
                TextButton(title: "Élaguer silence", compact: true) {
                    model.stripSilenceOnSelected()
                }
                TextButton(title: "Dupliquer", compact: true) {
                    model.duplicateSelectedClips()
                }
                TextButton(title: "Supprimer", compact: true) {
                    model.deleteSelection(ripple: false)
                }
            }
        }
    }

    @ViewBuilder
    private func multiClipSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("\(model.selectedClips.count) clips sélectionnés")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                TextButton(title: "Fondu ↗ 0.5s", compact: true) {
                    model.applyFadeIn(duration: 0.5)
                }
                TextButton(title: "Fondu ↘ 0.5s", compact: true) {
                    model.applyFadeOut(duration: 0.5)
                }
                TextButton(title: "Normaliser", compact: true) {
                    model.normalizeSelectedClips(targetDB: -0.1)
                }
                TextButton(title: "Inverser", compact: true) {
                    model.reverseSelectedClips()
                }
            }
        }
    }

    // MARK: 2b. MIDI Note Section

    @ViewBuilder
    private func noteSection(_ note: MIDINote) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader("Note MIDI (\(GeneralMIDI.noteName(note.pitch)))")

            FieldRow("Hauteur") {
                NumberField(value: Double(note.pitch), unit: "", step: 1, range: 0...127, decimals: 0) { val in
                    model.setNotePitch(note.id, Int(val.rounded()))
                }
            }

            FieldRow("Position") {
                NumberField(value: note.start, unit: "s", step: 0.05, range: 0...36000, decimals: 3) { val in
                    model.setNoteStart(note.id, val)
                }
            }

            FieldRow("Durée") {
                NumberField(value: note.duration, unit: "s", step: 0.05, range: MIDINote.minDuration...60, decimals: 3) { val in
                    model.setNoteDuration(note.id, val)
                }
            }

            FieldRow("Vélocité") {
                NumberField(value: Double(note.velocity), unit: "", step: 4, range: 1...127, decimals: 0) { val in
                    model.setNoteVelocity(note.id, Int(val.rounded()))
                }
            }

            HStack(spacing: 6) {
                TextButton(
                    title: note.mute ? "Muette ✓" : "Muette",
                    symbol: "speaker.slash",
                    prominent: note.mute,
                    compact: true
                ) {
                    model.setNoteMute(note.id, !note.mute)
                }
                TextButton(title: "Quantifier", symbol: "pianokeys", compact: true) {
                    model.quantizeSelection(subdivisionBeats: 0.25)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 5) {
                TextButton(title: "-12", compact: true) { model.transposeSelection(semitones: -12) }
                TextButton(title: "-1", compact: true) { model.transposeSelection(semitones: -1) }
                TextButton(title: "+1", compact: true) { model.transposeSelection(semitones: 1) }
                TextButton(title: "+12", compact: true) { model.transposeSelection(semitones: 12) }
            }
        }
    }

    @ViewBuilder
    private func multiNoteSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("\(model.selectedNotes.count) notes MIDI sélectionnées")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                TextButton(title: "Quantifier 1/16", compact: true) {
                    model.quantizeSelection(subdivisionBeats: 0.25)
                }
                TextButton(title: "Quantifier 1/8", compact: true) {
                    model.quantizeSelection(subdivisionBeats: 0.5)
                }
                TextButton(title: "Octave +12", compact: true) {
                    model.transposeSelection(semitones: 12)
                }
                TextButton(title: "Octave -12", compact: true) {
                    model.transposeSelection(semitones: -12)
                }
                TextButton(title: "Demi-ton +1", compact: true) {
                    model.transposeSelection(semitones: 1)
                }
                TextButton(title: "Demi-ton -1", compact: true) {
                    model.transposeSelection(semitones: -1)
                }
            }
        }
    }

    // MARK: 3. Track Section

    @ViewBuilder
    private func trackSection(_ track: AudioTrack) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(track.isMIDI ? "Piste MIDI" : "Piste Audio")

            FieldRow("Nom") {
                CommitField(value: track.name) { newName in
                    model.store.perform("Renommer la piste") { proj in
                        try? Operations.renameTrack(&proj, id: track.id, name: newName)
                    }
                }
            }

            FieldRow("Couleur") {
                HStack(spacing: 5) {
                    ForEach(0..<Theme.palette.count, id: \.self) { idx in
                        Circle()
                            .fill(Color(nsColor: Theme.trackColor(idx)))
                            .frame(width: 13, height: 13)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white, lineWidth: track.colorIndex == idx ? 1.5 : 0)
                            )
                            .onTapGesture {
                                model.store.perform("Couleur de la piste") { proj in
                                    try? Operations.setTrackColor(&proj, id: track.id, colorIndex: idx)
                                }
                            }
                    }
                }
            }

            if track.isMIDI {
                FieldRow("Instrument") {
                    Picker("", selection: Binding(
                        get: { track.program },
                        set: { prog in model.setTrackProgram(track.id, prog) }
                    )) {
                        ForEach(0..<GeneralMIDI.programs.count, id: \.self) { p in
                            Text("\(p + 1) · \(GeneralMIDI.programs[p])").tag(p)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }
                .disabled(track.isDrum || track.channel == 9)

                FieldRow("Canal MIDI") {
                    Picker("", selection: Binding(
                        get: { track.channel },
                        set: { ch in model.setTrackChannel(track.id, ch, isDrum: ch == 9) }
                    )) {
                        ForEach(0..<16, id: \.self) { ch in
                            Text(ch == 9 ? "10 (Batterie GM)" : "Canal \(ch + 1)").tag(ch)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }

                FieldRow("Transposer") {
                    NumberField(value: Double(track.transpose), unit: "st", step: 1, range: -48...48, decimals: 0) { val in
                        model.setTrackTranspose(track.id, Int(val.rounded()))
                    }
                }
            }

            FieldRow("Gain") {
                NumberField(value: track.gainDB, unit: "dB", step: 0.5, range: -60...24, decimals: 1) { val in
                    model.setTrackGain(track.id, gainDB: val)
                }
            }

            FieldRow("Pan") {
                NumberField(value: track.pan, unit: "", step: 0.05, range: -1...1, decimals: 2) { val in
                    model.setTrackPan(track.id, pan: val)
                }
            }

            HStack(spacing: 6) {
                TextButton(
                    title: "Muet",
                    prominent: track.mute,
                    compact: true
                ) {
                    model.toggleTrackMute(track.id)
                }
                TextButton(
                    title: "Solo",
                    prominent: track.solo,
                    compact: true
                ) {
                    model.toggleTrackSolo(track.id)
                }
                if track.isMIDI {
                    TextButton(
                        title: "🎹 Piano-Roll",
                        prominent: track.pianoRollExpanded,
                        compact: true
                    ) {
                        model.toggleTrackPianoRoll(track.id)
                    }
                } else {
                    TextButton(
                        title: "L/R",
                        prominent: track.stereoSplit,
                        compact: true
                    ) {
                        model.toggleTrackStereoSplit(track.id)
                    }
                }
            }

            if track.isMIDI && !track.notes.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    TextButton(title: "Rendre en piste Audio (WAV)", symbol: "waveform.badge.plus", compact: true) {
                        model.bounceMIDITrackToAudio(track.id, replaceMIDITrack: false)
                    }
                    .help("Synthétise la piste MIDI en WAV 24-bit et l'ajoute comme piste Audio sur la timeline")

                    TextButton(title: "Convertir en piste Audio", symbol: "arrow.triangle.2.circlepath", compact: true) {
                        model.bounceMIDITrackToAudio(track.id, replaceMIDITrack: true)
                    }
                    .help("Remplace cette piste MIDI par son rendu Audio WAV")
                }
            }

            if project.tracks.count > 1, let trackIdx = project.trackIndex(of: track.id) {
                HStack(spacing: 6) {
                    TextButton(
                        title: "Monter",
                        symbol: "arrow.up",
                        compact: true,
                        disabled: trackIdx == 0
                    ) {
                        model.moveTrack(track.id, by: -1)
                    }
                    .help("Monter la piste d'un cran (⌥↑)")

                    TextButton(
                        title: "Descendre",
                        symbol: "arrow.down",
                        compact: true,
                        disabled: trackIdx >= project.tracks.count - 1
                    ) {
                        model.moveTrack(track.id, by: 1)
                    }
                    .help("Descendre la piste d'un cran (⌥↓)")
                }
            }

            HStack(spacing: 6) {
                TextButton(title: "Dupliquer la piste", compact: true) {
                    model.duplicateSelectedTrack()
                }
                if project.tracks.count > 1 {
                    TextButton(title: "Supprimer", compact: true) {
                        model.removeSelectedTrack()
                    }
                }
            }
        }
    }

    // MARK: 4. Project & Remote Interfaces Section

    @ViewBuilder
    private func projectSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Projet & Mixage")

            FieldRow("Master") {
                NumberField(value: project.masterGainDB, unit: "dB", step: 0.5, range: -60...12, decimals: 1) { val in
                    model.store.perform("Gain Master") { proj in
                        proj.masterGainDB = val
                    }
                }
            }

            if project.hasMIDITracks {
                FieldRow("Tempo") {
                    NumberField(value: project.bpm, unit: "BPM", step: 1, range: 20...320, decimals: 1) { val in
                        model.setBPM(val)
                    }
                }

                FieldRow("Signature") {
                    HStack(spacing: 4) {
                        Picker("", selection: Binding(
                            get: { "\(project.timeSignatureNumerator)/\(project.timeSignatureDenominator)" },
                            set: { sig in
                                let parts = sig.split(separator: "/").compactMap { Int($0) }
                                if parts.count == 2 {
                                    model.setTimeSignature(numerator: parts[0], denominator: parts[1])
                                }
                            }
                        )) {
                            Text("4/4").tag("4/4")
                            Text("3/4").tag("3/4")
                            Text("6/8").tag("6/8")
                            Text("5/4").tag("5/4")
                            Text("7/8").tag("7/8")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                    }
                }

                FieldRow("Banque MIDI") {
                    Button(model.engine.activeSoundfontName) {
                        model.chooseSoundfontPanel()
                    }
                    .controlSize(.small)
                    .help("Charger une banque SoundFont (.sf2 / .dls)")
                }
            }

            FieldRow("Fréquence") {
                Text("\(Int(project.sampleRate)) Hz")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Color(nsColor: Theme.textDim))
            }

            FieldRow("Durée totale") {
                Text(TimeFormat.timecode(project.totalDuration))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Color(nsColor: Theme.textDim))
            }

            Divider().overlay(Color(nsColor: Theme.separator)).padding(.vertical, 2)
            SectionHeader("Contrôle externe")

            HStack(spacing: 6) {
                Circle()
                    .fill(Color(nsColor: model.apiListening ? Theme.meterSafe : Theme.textFaint))
                    .frame(width: 7, height: 7)
                Text("HTTP / MCP")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: Theme.textDim))
                Spacer()
                Text(":\(String(model.apiPort))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(nsColor: Theme.text))
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(Color(nsColor: model.oscListening ? Theme.meterSafe : Theme.textFaint))
                    .frame(width: 7, height: 7)
                Text("OSC UDP")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: Theme.textDim))
                Spacer()
                Text(":\(String(model.oscInputPort))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(nsColor: Theme.text))
            }
        }
    }
}
