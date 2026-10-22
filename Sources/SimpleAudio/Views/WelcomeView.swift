import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @Bindable var model: AppModel
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(Color(nsColor: Theme.accent).opacity(0.12))
                    .frame(width: 68, height: 68)
                Image(systemName: "waveform")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Color(nsColor: Theme.accent))
            }

            VStack(spacing: 6) {
                Text("SimpleAudio")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(nsColor: Theme.text))
                Text("Glissez des fichiers Audio (WAV, AIFF, M4A, MP3, FLAC, CAF) ou MIDI (.mid, .sf2) ici")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(nsColor: Theme.textDim))
            }

            HStack(spacing: 10) {
                TextButton(title: "Ouvrir Audio / MIDI…", symbol: "folder", prominent: true) {
                    model.openDocumentPanel()
                }
                TextButton(title: "Démo Audio", symbol: "waveform") {
                    model.loadDemoProject()
                }
                TextButton(title: "Démo Hybride Audio + MIDI", symbol: "pianokeys") {
                    model.loadHybridDemoProject()
                }
            }

            HStack(spacing: 18) {
                shortcutHint("Espace", "Lecture")
                shortcutHint("B", "Scinder")
                shortcutHint("P", "Piano-Roll")
                shortcutHint("Q", "Quantifier")
                shortcutHint("Z", "Zoom marqueur/curseur")
                shortcutHint("⌘E", "Exporter")
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    targeted ? Color(nsColor: Theme.accent) : Color.white.opacity(0.08),
                    style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: [6, 4])
                )
                .padding(24)
        )
        .background(Color(nsColor: Theme.background))
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            handleDrop(providers)
        }
    }

    private func shortcutHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(nsColor: Theme.text))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3.5)
                        .fill(Color.white.opacity(0.08))
                )
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: Theme.textFaint))
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            handled = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let u = item as? URL {
                    url = u
                } else {
                    url = nil
                }
                if let url {
                    Task { @MainActor in
                        if url.pathExtension.lowercased() == "simpleaudio" {
                            model.openDocument(url: url)
                        } else {
                            model.importAudioFiles(urls: [url], onNewTracks: true)
                        }
                    }
                }
            }
        }
        return handled
    }
}
