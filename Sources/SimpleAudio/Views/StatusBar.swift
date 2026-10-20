import SwiftUI
import SimpleAudioCore

struct StatusBar: View {
    @Bindable var model: AppModel

    private var project: AudioProject { model.store.project }

    var body: some View {
        HStack(spacing: 14) {
            Text(model.statusMessage)
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: Theme.textDim))
                .lineLimit(1)

            Spacer()

            if let range = model.selectionRange, range.upperBound > range.lowerBound + 1e-4 {
                Text("Plage : \(TimeFormat.timecode(range.lowerBound)) → \(TimeFormat.timecode(range.upperBound)) (\(TimeFormat.shortDuration(range.upperBound - range.lowerBound)))")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color(nsColor: Theme.rangeSelection))
            } else if let clip = model.primarySelectedClip {
                Text("\(clip.name) · \(TimeFormat.shortDuration(clip.duration)) · \(TimeFormat.decibels(clip.gainDB))")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color(nsColor: Theme.textDim))
            }

            Divider().frame(height: 12)

            Text("\(project.tracks.count) piste\(project.tracks.count > 1 ? "s" : "") · \(project.allClips.count) clip\(project.allClips.count > 1 ? "s" : "") · \(Int(project.sampleRate)) Hz")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Color(nsColor: Theme.textFaint))

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
                    Text("? aide")
                }
                .buttonStyle(.plain)
                .help("Ouvrir le guide d’utilisation de SimpleAudio (⌘?)")

                Button {
                    model.showShortcuts = true
                } label: {
                    Text("⌘/ raccourcis")
                }
                .buttonStyle(.plain)
                .help("Afficher les raccourcis clavier (⌘/)")

                Button {
                    model.showAbout = true
                } label: {
                    Text(AppVersion.current.shortLabel)
                        .foregroundStyle(Color(nsColor: Theme.textDim))
                }
                .buttonStyle(.plain)
                .help("À propos de SimpleAudio \(AppVersion.current.description)")
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
