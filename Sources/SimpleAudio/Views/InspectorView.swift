import SwiftUI
import SimpleAudioCore
import SimpleAudioEngine

struct InspectorView: View {
    @Bindable var model: AppModel

    private var project: AudioProject { model.store.project }

    var body: some View {
        let _ = model.language
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
            SectionHeader(L("Plage sélectionnée", "Selected Range")) {
                Button(L("Effacer", "Clear")) {
                    model.selectionRange = nil
                }
                .font(.system(size: 10.5))
                .foregroundStyle(Color(nsColor: Theme.textDim))
                .buttonStyle(.plain)
            }

            FieldRow(L("Début", "Start")) {
                NumberField(value: range.lowerBound, unit: "s", step: 0.05, range: 0...range.upperBound, decimals: 3) { newStart in
                    model.selectionRange = min(newStart, range.upperBound)...range.upperBound
                }
            }
            FieldRow(L("Fin", "End")) {
                NumberField(value: range.upperBound, unit: "s", step: 0.05, range: range.lowerBound...36000, decimals: 3) { newEnd in
                    model.selectionRange = range.lowerBound...max(newEnd, range.lowerBound)
                }
            }
            FieldRow(L("Durée", "Duration")) {
                Text(TimeFormat.shortDuration(range.upperBound - range.lowerBound))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Color(nsColor: Theme.rangeSelection))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                TextButton(title: L("Copier", "Copy"), symbol: "doc.on.doc", compact: true) {
                    model.copySelection()
                }
                TextButton(title: L("Couper", "Cut"), symbol: "scissors", compact: true) {
                    model.cutSelection()
                }
                TextButton(title: L("Rogner", "Crop"), symbol: "crop", compact: true) {
                    model.cropToSelection()
                }
                TextButton(title: L("Silencer", "Silence"), symbol: "speaker.slash", compact: true) {
                    model.silenceSelection()
                }
                TextButton(title: L("Fondu ↗", "Fade ↗"), compact: true) {
                    model.applyFadeIn(duration: 0.5)
                }
                TextButton(title: L("Fondu ↘", "Fade ↘"), compact: true) {
                    model.applyFadeOut(duration: 0.5)
                }
            }
        }
    }

    // MARK: 2. Clip Section

    @ViewBuilder
    private func clipSection(_ clip: AudioClip) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(L("Clip audio", "Audio Clip"))

            FieldRow(L("Nom", "Name")) {
                CommitField(value: clip.name) { newName in
                    model.store.perform(L("Renommer le clip", "Rename Clip")) { proj in
                        try? Operations.renameClip(&proj, id: clip.id, name: newName)
                    }
                }
            }

            FieldRow(L("Position", "Position")) {
                NumberField(value: clip.offset, unit: "s", step: 0.05, range: 0...36000, decimals: 3) { val in
                    model.store.perform(L("Déplacer le clip", "Move Clip")) { proj in
                        if let (ti, _) = proj.clipLocation(of: clip.id) {
                            try? Operations.moveClip(&proj, id: clip.id, toTrack: proj.tracks[ti].id, offset: val)
                        }
                    }
                }
            }

            FieldRow(L("Durée", "Duration")) {
                NumberField(
                    value: clip.duration,
                    unit: "s",
                    step: 0.05,
                    range: AudioClip.minDuration...max(AudioClip.minDuration, clip.sourceDuration - clip.sourceStart),
                    decimals: 3
                ) { val in
                    model.store.perform(L("Durée du clip", "Clip Duration")) { proj in
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

            FieldRow(L("Entrée src.", "Source In")) {
                NumberField(
                    value: clip.sourceStart,
                    unit: "s",
                    step: 0.05,
                    range: 0...max(0, clip.sourceDuration - clip.duration),
                    decimals: 3
                ) { val in
                    model.store.perform(L("Glisser la source", "Slip Source")) { proj in
                        try? Operations.slipClip(&proj, id: clip.id, toSourceStart: val)
                    }
                }
            }

            Divider().overlay(Color(nsColor: Theme.separator)).padding(.vertical, 2)
            SectionHeader(L("Gain & Fondus", "Gain & Fades"))

            FieldRow(L("Gain", "Gain")) {
                NumberField(value: clip.gainDB, unit: "dB", step: 0.5, range: -60...24, decimals: 1) { val in
                    model.store.perform(L("Gain du clip", "Clip Gain")) { proj in
                        try? Operations.setClipGain(&proj, id: clip.id, gainDB: val)
                    }
                }
                if abs(clip.gainDB) > 0.05 {
                    Button("0") {
                        model.store.perform(L("Réinitialiser le gain", "Reset Gain")) { proj in
                            try? Operations.setClipGain(&proj, id: clip.id, gainDB: 0)
                        }
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(nsColor: Theme.accent))
                }
            }

            FieldRow(L("Pan", "Pan")) {
                NumberField(value: clip.pan, unit: "", step: 0.05, range: -1...1, decimals: 2) { val in
                    model.store.perform(L("Panoramique du clip", "Clip Pan")) { proj in
                        try? Operations.setClipPan(&proj, id: clip.id, pan: val)
                    }
                }
            }

            FieldRow(L("Fondu ↗", "Fade ↗")) {
                NumberField(
                    value: clip.fadeIn,
                    unit: "s",
                    step: 0.05,
                    range: 0...max(0, clip.duration - clip.fadeOut),
                    decimals: 2
                ) { val in
                    model.store.perform(L("Fondu d'entrée", "Fade In")) { proj in
                        try? Operations.setFade(&proj, id: clip.id, fadeIn: val)
                    }
                }
            }

            FieldRow(L("Fondu ↘", "Fade ↘")) {
                NumberField(
                    value: clip.fadeOut,
                    unit: "s",
                    step: 0.05,
                    range: 0...max(0, clip.duration - clip.fadeIn),
                    decimals: 2
                ) { val in
                    model.store.perform(L("Fondu de sortie", "Fade Out")) { proj in
                        try? Operations.setFade(&proj, id: clip.id, fadeOut: val)
                    }
                }
            }

            FieldRow(L("Courbe", "Curve")) {
                Picker("", selection: Binding(
                    get: { clip.fadeShape },
                    set: { shape in
                        model.store.perform(L("Courbe de fondu", "Fade Curve")) { proj in
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
                    title: clip.mute ? L("Muet ✓", "Muted ✓") : L("Muet", "Mute"),
                    symbol: "speaker.slash",
                    prominent: clip.mute,
                    compact: true
                ) {
                    model.toggleMuteSelectedClips()
                }
                TextButton(
                    title: clip.reversed ? L("Inversé ✓", "Reversed ✓") : L("Inverser", "Reverse"),
                    symbol: "arrow.left.arrow.right",
                    prominent: clip.reversed,
                    compact: true
                ) {
                    model.reverseSelectedClips()
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                TextButton(title: L("Normaliser", "Normalize"), compact: true) {
                    model.normalizeSelectedClips(targetDB: -0.1)
                }
                TextButton(title: L("Élaguer silence", "Strip Silence"), compact: true) {
                    model.stripSilenceOnSelected()
                }
                TextButton(title: L("Dupliquer", "Duplicate"), compact: true) {
                    model.duplicateSelectedClips()
                }
                TextButton(title: L("Supprimer", "Delete"), compact: true) {
                    model.deleteSelection(ripple: false)
                }
            }
        }
    }

    @ViewBuilder
    private func multiClipSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(L("\(model.selectedClips.count) clips sélectionnés", "\(model.selectedClips.count) clips selected"))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                TextButton(title: L("Fondu ↗ 0.5s", "Fade ↗ 0.5s"), compact: true) {
                    model.applyFadeIn(duration: 0.5)
                }
                TextButton(title: L("Fondu ↘ 0.5s", "Fade ↘ 0.5s"), compact: true) {
                    model.applyFadeOut(duration: 0.5)
                }
                TextButton(title: L("Normaliser", "Normalize"), compact: true) {
                    model.normalizeSelectedClips(targetDB: -0.1)
                }
                TextButton(title: L("Inverser", "Reverse"), compact: true) {
                    model.reverseSelectedClips()
                }
            }
        }
    }

    // MARK: 2b. MIDI Note Section

    @ViewBuilder
    private func noteSection(_ note: MIDINote) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(L("Note MIDI (\(GeneralMIDI.noteName(note.pitch)))", "MIDI Note (\(GeneralMIDI.noteName(note.pitch)))"))

            FieldRow(L("Hauteur", "Pitch")) {
                NumberField(value: Double(note.pitch), unit: "", step: 1, range: 0...127, decimals: 0) { val in
                    model.setNotePitch(note.id, Int(val.rounded()))
                }
            }

            FieldRow(L("Position", "Position")) {
                NumberField(value: note.start, unit: "s", step: 0.05, range: 0...36000, decimals: 3) { val in
                    model.setNoteStart(note.id, val)
                }
            }

            FieldRow(L("Durée", "Duration")) {
                NumberField(value: note.duration, unit: "s", step: 0.05, range: MIDINote.minDuration...60, decimals: 3) { val in
                    model.setNoteDuration(note.id, val)
                }
            }

            FieldRow(L("Vélocité", "Velocity")) {
                NumberField(value: Double(note.velocity), unit: "", step: 4, range: 1...127, decimals: 0) { val in
                    model.setNoteVelocity(note.id, Int(val.rounded()))
                }
            }

            HStack(spacing: 6) {
                TextButton(
                    title: note.mute ? L("Muette ✓", "Muted ✓") : L("Muette", "Mute"),
                    symbol: "speaker.slash",
                    prominent: note.mute,
                    compact: true
                ) {
                    model.setNoteMute(note.id, !note.mute)
                }
                TextButton(title: L("Quantifier", "Quantize"), symbol: "pianokeys", compact: true) {
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
            SectionHeader(L("\(model.selectedNotes.count) notes MIDI sélectionnées", "\(model.selectedNotes.count) MIDI notes selected"))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                TextButton(title: L("Quantifier 1/16", "Quantize 1/16"), compact: true) {
                    model.quantizeSelection(subdivisionBeats: 0.25)
                }
                TextButton(title: L("Quantifier 1/8", "Quantize 1/8"), compact: true) {
                    model.quantizeSelection(subdivisionBeats: 0.5)
                }
                TextButton(title: L("Octave +12", "Octave +12"), compact: true) {
                    model.transposeSelection(semitones: 12)
                }
                TextButton(title: L("Octave -12", "Octave -12"), compact: true) {
                    model.transposeSelection(semitones: -12)
                }
                TextButton(title: L("Demi-ton +1", "Semitone +1"), compact: true) {
                    model.transposeSelection(semitones: 1)
                }
                TextButton(title: L("Demi-ton -1", "Semitone -1"), compact: true) {
                    model.transposeSelection(semitones: -1)
                }
            }
        }
    }

    // MARK: 3. Track Section

    @ViewBuilder
    private func trackSection(_ track: AudioTrack) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(track.isMIDI ? L("Piste MIDI", "MIDI Track") : L("Piste Audio", "Audio Track"))

            FieldRow(L("Nom", "Name")) {
                CommitField(value: track.name) { newName in
                    model.store.perform(L("Renommer la piste", "Rename Track")) { proj in
                        try? Operations.renameTrack(&proj, id: track.id, name: newName)
                    }
                }
            }

            FieldRow(L("Couleur", "Color")) {
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
                                model.store.perform(L("Couleur de la piste", "Track Color")) { proj in
                                    try? Operations.setTrackColor(&proj, id: track.id, colorIndex: idx)
                                }
                            }
                    }
                }
            }

            if track.isMIDI {
                FieldRow(L("Instrument", "Instrument")) {
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

                FieldRow(L("Canal MIDI", "MIDI Channel")) {
                    Picker("", selection: Binding(
                        get: { track.channel },
                        set: { ch in model.setTrackChannel(track.id, ch, isDrum: ch == 9) }
                    )) {
                        ForEach(0..<16, id: \.self) { ch in
                            Text(ch == 9 ? L("10 (Batterie GM)", "10 (GM Drums)") : L("Canal \(ch + 1)", "Channel \(ch + 1)")).tag(ch)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }

                FieldRow(L("Transposer", "Transpose")) {
                    NumberField(value: Double(track.transpose), unit: "st", step: 1, range: -48...48, decimals: 0) { val in
                        model.setTrackTranspose(track.id, Int(val.rounded()))
                    }
                }
            }

            FieldRow(L("Gain", "Gain")) {
                NumberField(value: track.gainDB, unit: "dB", step: 0.5, range: -60...24, decimals: 1) { val in
                    model.setTrackGain(track.id, gainDB: val)
                }
            }

            FieldRow(L("Pan", "Pan")) {
                NumberField(value: track.pan, unit: "", step: 0.05, range: -1...1, decimals: 2) { val in
                    model.setTrackPan(track.id, pan: val)
                }
            }

            HStack(spacing: 6) {
                TextButton(
                    title: L("Muet", "Mute"),
                    prominent: track.mute,
                    compact: true
                ) {
                    model.toggleTrackMute(track.id)
                }
                TextButton(
                    title: L("Solo", "Solo"),
                    prominent: track.solo,
                    compact: true
                ) {
                    model.toggleTrackSolo(track.id)
                }
                if track.isMIDI {
                    TextButton(
                        title: L("🎹 Piano-Roll", "🎹 Piano Roll"),
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
                    TextButton(title: L("Rendre en piste Audio (WAV)", "Bounce to Audio Track (WAV)"), symbol: "waveform.badge.plus", compact: true) {
                        model.bounceMIDITrackToAudio(track.id, replaceMIDITrack: false)
                    }
                    .help(L("Synthétise la piste MIDI en WAV 24-bit et l'ajoute comme piste Audio sur la timeline", "Synthesizes the MIDI track to 24-bit WAV and adds it as an Audio track on the timeline"))

                    TextButton(title: L("Convertir en piste Audio", "Convert to Audio Track"), symbol: "arrow.triangle.2.circlepath", compact: true) {
                        model.bounceMIDITrackToAudio(track.id, replaceMIDITrack: true)
                    }
                    .help(L("Remplace cette piste MIDI par son rendu Audio WAV", "Replaces this MIDI track with its rendered WAV audio"))
                }
            }

            if project.tracks.count > 1, let trackIdx = project.trackIndex(of: track.id) {
                HStack(spacing: 6) {
                    TextButton(
                        title: L("Monter", "Move Up"),
                        symbol: "arrow.up",
                        compact: true,
                        disabled: trackIdx == 0
                    ) {
                        model.moveTrack(track.id, by: -1)
                    }
                    .help(L("Monter la piste d'un cran (⌥↑)", "Move track up one slot (⌥↑)"))

                    TextButton(
                        title: L("Descendre", "Move Down"),
                        symbol: "arrow.down",
                        compact: true,
                        disabled: trackIdx >= project.tracks.count - 1
                    ) {
                        model.moveTrack(track.id, by: 1)
                    }
                    .help(L("Descendre la piste d'un cran (⌥↓)", "Move track down one slot (⌥↓)"))
                }
            }

            HStack(spacing: 6) {
                TextButton(title: L("Dupliquer la piste", "Duplicate Track"), compact: true) {
                    model.duplicateSelectedTrack()
                }
                if project.tracks.count > 1 {
                    TextButton(title: L("Supprimer", "Delete"), compact: true) {
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
            SectionHeader(L("Projet & Mixage", "Project & Mix"))

            FieldRow(L("Master", "Master")) {
                NumberField(value: project.masterGainDB, unit: "dB", step: 0.5, range: -60...12, decimals: 1) { val in
                    model.store.perform(L("Gain Master", "Master Gain")) { proj in
                        proj.masterGainDB = val
                    }
                }
            }

            if project.hasMIDITracks {
                FieldRow(L("Tempo", "Tempo")) {
                    NumberField(value: project.bpm, unit: "BPM", step: 1, range: 20...320, decimals: 1) { val in
                        model.setBPM(val)
                    }
                }

                FieldRow(L("Signature", "Time Sig.")) {
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

                FieldRow(L("Banque MIDI", "MIDI Bank")) {
                    Button(model.engine.activeSoundfontName) {
                        model.chooseSoundfontPanel()
                    }
                    .controlSize(.small)
                    .help(L("Charger une banque SoundFont (.sf2 / .dls)", "Load SoundFont Bank (.sf2 / .dls)"))
                }
            }

            FieldRow(L("Fréquence", "Sample Rate")) {
                Text("\(Int(project.sampleRate)) Hz")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Color(nsColor: Theme.textDim))
            }

            FieldRow(L("Durée totale", "Total Duration")) {
                Text(TimeFormat.timecode(project.totalDuration))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Color(nsColor: Theme.textDim))
            }

            Divider().overlay(Color(nsColor: Theme.separator)).padding(.vertical, 2)
            SectionHeader(L("Contrôle externe", "External Control"))

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
