import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var timelineRef: TimelineView?
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            TransportView(
                model: model,
                onZoomIn: {
                    if let tv = timelineRef {
                        tv.zoom(by: 1.35, at: tv.x(for: model.playhead))
                    }
                },
                onZoomOut: {
                    if let tv = timelineRef {
                        tv.zoom(by: 1.0 / 1.35, at: tv.x(for: model.playhead))
                    }
                },
                onZoomFit: {
                    model.perform(.toggleZoom)
                }
            )

            HStack(spacing: 0) {
                if model.showSidebar {
                    SidebarView(model: model)
                }

                Group {
                    if model.store.project.allClips.isEmpty {
                        WelcomeView(model: model)
                    } else {
                        TimelineHost(model: model) { view in
                            if timelineRef !== view {
                                DispatchQueue.main.async {
                                    timelineRef = view
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                    handleDrop(providers)
                }

                if model.showInspector {
                    InspectorView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            StatusBar(model: model)
        }
        .background(Color(nsColor: Theme.background))
        .preferredColorScheme(.dark)
        .sheet(isPresented: $model.showExportSheet) {
            ExportSheet(model: model)
        }
        .sheet(isPresented: $model.showShortcuts) {
            ShortcutsSheet { model.showShortcuts = false }
        }
        .sheet(isPresented: $model.showHelp) {
            HelpManualSheet(openShortcuts: {
                DispatchQueue.main.async { model.showShortcuts = true }
            }) {
                model.showHelp = false
            }
        }
        .sheet(isPresented: $model.showAbout) {
            AboutSheet(
                apiPort: model.apiPort,
                apiListening: model.apiListening,
                oscPort: model.oscInputPort,
                oscListening: model.oscListening,
                openHelp: {
                    DispatchQueue.main.async { model.showHelp = true }
                },
                close: {
                    model.showAbout = false
                }
            )
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
                            model.importAudioFiles(urls: [url], onNewTracks: false)
                        }
                    }
                }
            }
        }
        return handled
    }
}
