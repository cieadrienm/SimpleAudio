import SwiftUI
import UniformTypeIdentifiers
import SimpleAudioCore

struct WelcomeView: View {
    @Bindable var model: AppModel
    @State private var targeted = false

    var body: some View {
        let _ = model.language
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
                Text(L(
                    "Glissez des fichiers Audio (WAV, AIFF, M4A, MP3, FLAC, CAF) ou MIDI (.mid, .sf2) ici",
                    "Drop Audio (WAV, AIFF, M4A, MP3, FLAC, CAF) or MIDI (.mid, .sf2) files here"
                ))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(nsColor: Theme.textDim))
            }

            HStack(spacing: 10) {
                TextButton(title: L("Ouvrir Audio / MIDI…", "Open Audio / MIDI…"), symbol: "folder", prominent: true) {
                    model.openDocumentPanel()
                }
                TextButton(title: L("Démo Audio", "Audio Demo"), symbol: "waveform") {
                    model.loadDemoProject()
                }
                TextButton(title: L("Démo Hybride Audio + MIDI", "Hybrid Audio + MIDI Demo"), symbol: "pianokeys") {
                    model.loadHybridDemoProject()
                }
            }

            if !model.recentFiles.isEmpty {
                VStack(spacing: 6) {
                    Text(L("RÉCENTS", "RECENT"))
                        .font(.system(size: 9.5, weight: .semibold))
                        .kerning(0.8)
                        .foregroundStyle(Color(nsColor: Theme.textFaint))
                    HStack(spacing: 6) {
                        ForEach(model.recentFiles.prefix(5), id: \.path) { url in
                            let ext = url.pathExtension.lowercased()
                            let icon = AppModel.midiExtensions.contains(ext) ? "pianokeys" : (AppModel.projectExtensions.contains(ext) ? "doc.text" : "waveform")
                            TextButton(title: url.lastPathComponent, symbol: icon, compact: true) {
                                model.requestOpen(url)
                            }
                            .help(url.path)
                        }
                    }
                }
                .padding(.top, 2)
            }

            HStack(spacing: 18) {
                shortcutHint(L("Espace", "Space"), L("Lecture", "Play"))
                shortcutHint("B", L("Scinder", "Split"))
                shortcutHint("P", L("Piano-Roll", "Piano Roll"))
                shortcutHint("Q", L("Quantifier", "Quantize"))
                shortcutHint("Z", L("Zoom marqueur/curseur", "Smart Zoom"))
                shortcutHint("⌘E", L("Exporter", "Export"))
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
