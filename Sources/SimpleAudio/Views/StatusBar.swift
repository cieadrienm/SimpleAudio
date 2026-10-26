import SwiftUI
import SimpleAudioCore

struct StatusBar: View {
    @Bindable var model: AppModel

    private var project: AudioProject { model.store.project }

    var body: some View {
        let _ = model.language
        HStack(spacing: 14) {
            Text(model.statusMessage == "Prêt" || model.statusMessage == "Ready" ? L("Prêt", "Ready") : model.statusMessage)
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: Theme.textDim))
                .lineLimit(1)

            Spacer()

            if let range = model.selectionRange, range.upperBound > range.lowerBound + 1e-4 {
                Text(L(
                    "Plage : \(TimeFormat.timecode(range.lowerBound)) → \(TimeFormat.timecode(range.upperBound)) (\(TimeFormat.shortDuration(range.upperBound - range.lowerBound)))",
                    "Range: \(TimeFormat.timecode(range.lowerBound)) → \(TimeFormat.timecode(range.upperBound)) (\(TimeFormat.shortDuration(range.upperBound - range.lowerBound)))"
                ))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color(nsColor: Theme.rangeSelection))
            } else if let note = model.primarySelectedNote {
                Text(L(
                    "Note \(GeneralMIDI.noteName(note.pitch)) · vél \(note.velocity) · \(TimeFormat.shortDuration(note.duration))",
                    "Note \(GeneralMIDI.noteName(note.pitch)) · vel \(note.velocity) · \(TimeFormat.shortDuration(note.duration))"
                ))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color(nsColor: Theme.textDim))
            } else if let clip = model.primarySelectedClip {
                Text("\(clip.name) · \(TimeFormat.shortDuration(clip.duration)) · \(TimeFormat.decibels(clip.gainDB))")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color(nsColor: Theme.textDim))
            }

            Divider().frame(height: 12)

            if project.noteCount > 0 {
                Text(L(
                    "\(project.tracks.count) piste\(project.tracks.count > 1 ? "s" : "") · \(project.allClips.count) clip\(project.allClips.count > 1 ? "s" : "") · \(project.noteCount) note\(project.noteCount > 1 ? "s" : "") · \(Int(project.bpm)) BPM",
                    "\(project.tracks.count) track\(project.tracks.count > 1 ? "s" : "") · \(project.allClips.count) clip\(project.allClips.count > 1 ? "s" : "") · \(project.noteCount) note\(project.noteCount > 1 ? "s" : "") · \(Int(project.bpm)) BPM"
                ))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color(nsColor: Theme.textFaint))
            } else {
                Text(L(
                    "\(project.tracks.count) piste\(project.tracks.count > 1 ? "s" : "") · \(project.allClips.count) clip\(project.allClips.count > 1 ? "s" : "") · \(Int(project.sampleRate)) Hz",
                    "\(project.tracks.count) track\(project.tracks.count > 1 ? "s" : "") · \(project.allClips.count) clip\(project.allClips.count > 1 ? "s" : "") · \(Int(project.sampleRate)) Hz"
                ))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color(nsColor: Theme.textFaint))
            }

            Divider().frame(height: 12)

            HStack(spacing: 8) {
                statusDot(label: "API :\(model.apiPort)", active: model.apiListening)
                statusDot(label: "OSC :\(model.oscInputPort)", active: model.oscListening)
            }

            Divider().frame(height: 12)

            HStack(spacing: 12) {
                Button {
                    model.showHelp = true
                } label: {
                    Text(L("? aide", "? help"))
                }
                .buttonStyle(.plain)
                .help(L("Ouvrir le guide d’utilisation de SimpleAudio (⌘?)", "Open SimpleAudio User Guide (⌘?)"))

                Button {
                    model.showShortcuts = true
                } label: {
                    Text(L("⌘/ raccourcis", "⌘/ shortcuts"))
                }
                .buttonStyle(.plain)
                .help(L("Afficher les raccourcis clavier (⌘/)", "Show Keyboard Shortcuts (⌘/)"))

                if case .updateAvailable(let rel) = model.updater.state {
                    Button {
                        model.showUpdater = true
                    } label: {
                        Text(L("↑ MAJ v\(rel.version)", "↑ Update v\(rel.version)"))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(nsColor: Theme.background))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color(nsColor: Theme.accent))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(L("Une mise à jour (v\(rel.version)) est disponible", "An update (v\(rel.version)) is available"))
                }

                Button {
                    model.showAbout = true
                } label: {
                    Text(AppVersion.current.shortLabel)
                        .foregroundStyle(Color(nsColor: Theme.textDim))
                }
                .buttonStyle(.plain)
                .help(L("À propos de SimpleAudio \(AppVersion.current.description)", "About SimpleAudio \(AppVersion.current.description)"))
            }
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(Color(nsColor: Theme.textFaint))
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(Color(nsColor: Theme.panel))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(nsColor: Theme.separator))
                .frame(height: 1)
        }
    }

    private func statusDot(label: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(nsColor: active ? Theme.meterSafe : Theme.textFaint))
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(nsColor: Theme.textFaint))
        }
    }
}
