import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SimpleAudioCore
import SimpleAudioEngine

struct ExportSheet: View {
    @Bindable var model: AppModel

    @State private var format: ExportFormat = .wav
    @State private var sampleRate: Double = 48_000
    @State private var bitDepth: ExportBitDepth = .int24
    @State private var channels: Int = 2
    @State private var exportRangeOnly: Bool = false
    @State private var exportStems: Bool = false
    @State private var normMode: Int = 0 // 0 = off, 1 = Peak -0.1 dBFS, 2 = -14 LUFS
    @State private var exporting: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(nsColor: Theme.accent))
                Text("Exporter l'audio")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(nsColor: Theme.text))
                Spacer()
            }

            Divider().overlay(Color(nsColor: Theme.separator))

            VStack(alignment: .leading, spacing: 11) {
                FieldRow("Format") {
                    Picker("", selection: $format) {
                        ForEach(ExportFormat.allCases, id: \.self) { fmt in
                            Text(fmt.label).tag(fmt)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 210)
                }

                FieldRow("Fréquence") {
                    Picker("", selection: $sampleRate) {
                        Text("44 100 Hz").tag(44_100.0)
                        Text("48 000 Hz").tag(48_000.0)
                        Text("96 000 Hz").tag(96_000.0)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }

                if format == .wav || format == .aiff || format == .caf {
                    FieldRow("Résolution") {
                        Picker("", selection: $bitDepth) {
                            ForEach(ExportBitDepth.allCases, id: \.self) { depth in
                                Text(depth.label).tag(depth)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                    }
                }

                FieldRow("Canaux") {
                    Picker("", selection: $channels) {
                        Text("Stéréo (L/R)").tag(2)
                        Text("Mono").tag(1)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }

                if let range = model.selectionRange, range.upperBound > range.lowerBound + 1e-4 {
                    FieldRow("Étendue") {
                        Picker("", selection: $exportRangeOnly) {
                            Text("Projet complet (\(TimeFormat.shortDuration(model.store.project.totalDuration)))").tag(false)
                            Text("Plage (\(TimeFormat.shortDuration(range.upperBound - range.lowerBound)))").tag(true)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 240)
                    }
                }

                FieldRow("Sortie") {
                    Picker("", selection: $exportStems) {
                        Text("Mixage stéréo (Master)").tag(false)
                        Text("Pistes séparées (Stems)").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 220)
                }

                FieldRow("Niveau") {
                    Picker("", selection: $normMode) {
                        Text("Niveau tel quel").tag(0)
                        Text("Normaliser crête (-0.1 dBFS)").tag(1)
                        Text("Normaliser loudness (-14 LUFS)").tag(2)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 220)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(nsColor: Theme.meterHot))
            }

            Divider().overlay(Color(nsColor: Theme.separator))

            HStack {
                TextButton(title: "Annuler") {
                    model.showExportSheet = false
                }
                Spacer()
                TextButton(
                    title: exporting ? "Export en cours…" : (exportStems ? "Exporter les stems…" : "Exporter…"),
                    symbol: "checkmark.circle.fill",
                    prominent: true,
                    disabled: exporting
                ) {
                    runExport()
                }
            }
        }
        .padding(20)
        .frame(width: 410)
        .background(Color(nsColor: Theme.panel))
        .onAppear {
            sampleRate = model.store.project.sampleRate
            if let range = model.selectionRange, range.upperBound > range.lowerBound + 1e-4 {
                exportRangeOnly = true
            }
        }
    }

    private func runExport() {
        errorMessage = nil
        let range = exportRangeOnly ? model.selectionRange : nil

        if exportStems {
            let panel = NSOpenPanel()
            panel.title = "Choisir le dossier pour les pistes (Stems)"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let folder = panel.url else { return }

            exporting = true
            do {
                let urls = try AudioExporter.exportStems(
                    project: model.store.project,
                    waveforms: model.waveforms,
                    directory: folder,
                    format: format,
                    sampleRate: sampleRate,
                    bitDepth: bitDepth,
                    range: range,
                    baseURL: model.store.url
                )
                exporting = false
                model.statusMessage = "\(urls.count) pistes exportées vers \(folder.lastPathComponent)"
                model.showExportSheet = false
            } catch {
                exporting = false
                errorMessage = error.localizedDescription
            }
        } else {
            let panel = NSSavePanel()
            panel.title = "Exporter l'audio"
            let baseName = model.store.url?.deletingPathExtension().lastPathComponent ?? "Export"
            panel.nameFieldStringValue = "\(baseName).\(format.fileExtension)"
            guard panel.runModal() == .OK, let dest = panel.url else { return }

            exporting = true
            let opts = ExportOptions(
                format: format,
                sampleRate: sampleRate,
                bitDepth: bitDepth,
                channels: channels,
                range: range,
                normalizePeak: normMode == 1,
                targetPeakDB: -0.1,
                normalizeLUFS: normMode == 2,
                targetLUFS: -14.0
            )
            do {
                let res = try AudioExporter.export(
                    project: model.store.project,
                    waveforms: model.waveforms,
                    to: dest,
                    options: opts,
                    baseURL: model.store.url
                )
                exporting = false
                model.statusMessage = String(
                    format: "Exporté : %@ (%.2f s, %.1f dBFS, %.1f LUFS)",
                    res.url.lastPathComponent,
                    res.duration,
                    res.peakDB,
                    res.integratedLUFS
                )
                model.showExportSheet = false
            } catch {
                exporting = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
