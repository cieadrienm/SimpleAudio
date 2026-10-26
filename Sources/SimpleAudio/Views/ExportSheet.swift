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
        let _ = model.language
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(nsColor: Theme.accent))
                Text(L("Exporter l'audio", "Export Audio"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(nsColor: Theme.text))
                Spacer()
            }

            Divider().overlay(Color(nsColor: Theme.separator))

            VStack(alignment: .leading, spacing: 11) {
                FieldRow(L("Format", "Format")) {
                    Picker("", selection: $format) {
                        ForEach(ExportFormat.allCases, id: \.self) { fmt in
                            Text(fmt.label).tag(fmt)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 210)
                }

                if format != .mid {
                    FieldRow(L("Fréquence", "Sample Rate")) {
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
                        FieldRow(L("Résolution", "Bit Depth")) {
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

                    FieldRow(L("Canaux", "Channels")) {
                        Picker("", selection: $channels) {
                            Text(L("Stéréo (L/R)", "Stereo (L/R)")).tag(2)
                            Text(L("Mono", "Mono")).tag(1)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }

                    if let range = model.selectionRange, range.upperBound > range.lowerBound + 1e-4 {
                        FieldRow(L("Étendue", "Range")) {
                            Picker("", selection: $exportRangeOnly) {
                                Text(L(
                                    "Projet complet (\(TimeFormat.shortDuration(model.store.project.totalDuration)))",
                                    "Full Project (\(TimeFormat.shortDuration(model.store.project.totalDuration)))"
                                )).tag(false)
                                Text(L(
                                    "Plage (\(TimeFormat.shortDuration(range.upperBound - range.lowerBound)))",
                                    "Selection Range (\(TimeFormat.shortDuration(range.upperBound - range.lowerBound)))"
                                )).tag(true)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 240)
                        }
                    }

                    FieldRow(L("Sortie", "Output")) {
                        Picker("", selection: $exportStems) {
                            Text(L("Mixage stéréo (Master)", "Stereo Mix (Master)")).tag(false)
                            Text(L("Pistes séparées (Stems)", "Separate Tracks (Stems)")).tag(true)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 220)
                    }

                    FieldRow(L("Niveau", "Level")) {
                        Picker("", selection: $normMode) {
                            Text(L("Niveau tel quel", "As-Is Level")).tag(0)
                            Text(L("Normaliser crête (-0.1 dBFS)", "Peak Normalize (-0.1 dBFS)")).tag(1)
                            Text(L("Normaliser loudness (-14 LUFS)", "Loudness Normalize (-14 LUFS)")).tag(2)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 220)
                    }
                } else {
                    Text(L(
                        "Exporte toutes les pistes MIDI du projet au format Standard MIDI File (.mid Format 1) avec tempo et signature.",
                        "Exports all project MIDI tracks as a Standard MIDI File (.mid Format 1) with tempo and time signature."
                    ))
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: Theme.textDim))
                        .padding(.vertical, 4)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(nsColor: Theme.meterHot))
            }

            Divider().overlay(Color(nsColor: Theme.separator))

            HStack {
                TextButton(title: L("Annuler", "Cancel")) {
                    model.showExportSheet = false
                }
                Spacer()
                TextButton(
                    title: exporting ? L("Export en cours…", "Exporting…") : (exportStems ? L("Exporter les stems…", "Export Stems…") : L("Exporter…", "Export…")),
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
            panel.title = L("Choisir le dossier pour les pistes (Stems)", "Choose Folder for Track Stems")
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
                model.statusMessage = L(
                    "\(urls.count) pistes exportées vers \(folder.lastPathComponent)",
                    "\(urls.count) stems exported to \(folder.lastPathComponent)"
                )
                model.showExportSheet = false
            } catch {
                exporting = false
                errorMessage = error.localizedDescription
            }
        } else {
            let panel = NSSavePanel()
            panel.title = L("Exporter l'audio", "Export Audio")
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
                    format: L("Exporté : %@ (%.2f s, %.1f dBFS, %.1f LUFS)", "Exported: %@ (%.2f s, %.1f dBFS, %.1f LUFS)"),
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
