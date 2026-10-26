import AppKit
import SwiftUI
import SimpleAudioCore

struct AboutSheet: View {
    let apiPort: UInt16
    let apiListening: Bool
    let oscPort: UInt16
    let oscListening: Bool
    let openHelp: () -> Void
    var openUpdates: () -> Void = {}
    let close: () -> Void

    @State private var copiedVersion = false

    private struct FeatureCard: Identifiable {
        let id = UUID()
        let icon: String
        let tint: NSColor
        let title: String
        let detail: String
    }

    private var features: [FeatureCard] {
        [
            FeatureCard(
                icon: "waveform.path.ecg",
                tint: Theme.accent,
                title: L("Formes d’onde & Piano-Roll MIDI", "Waveforms & MIDI Piano Roll"),
                detail: L(
                    "Timeline hybride Audio + MIDI 120 Hz ProMotion : enveloppes Peak + RMS accélérées vDSP, Piano-Roll interactif dépliable (P) et clavier d'écoute.",
                    "120 Hz ProMotion hybrid Audio + MIDI timeline: vDSP-accelerated Peak + RMS envelopes, collapsible interactive Piano Roll (P) and audition keyboard."
                )
            ),
            FeatureCard(
                icon: "scissors",
                tint: Theme.rangeSelection,
                title: L("Montage, Fondus & Édition MIDI", "Editing, Fades & MIDI Tools"),
                detail: L(
                    "Scinder (B), plage In/Out, 4 courbes de fondu, quantification MIDI (Q), transposition (↑/↓) et conversion de piste MIDI en Audio WAV.",
                    "Split (B), In/Out range, 4 fade curves, MIDI quantization (Q), transposition (↑/↓) and MIDI-to-Audio WAV track bounce."
                )
            ),
            FeatureCard(
                icon: "pianokeys",
                tint: Theme.meterLow,
                title: L("Synthèse GM 128, SoundFont & DSP", "GM 128 Synthesis, SoundFont & DSP"),
                detail: L(
                    "Moteur hybride AVAudioEngine + Apple DLSMusicDevice (128 instruments GM, batterie Ch.10, banques .sf2/.dls) et normalisation Peak / -14 LUFS.",
                    "Hybrid AVAudioEngine + Apple DLSMusicDevice engine (128 GM instruments, Ch.10 drums, .sf2/.dls banks) and Peak / -14 LUFS normalization."
                )
            ),
            FeatureCard(
                icon: "antenna.radiowaves.left.and.right",
                tint: Theme.muteColor,
                title: L("Export Audio/MIDI, OSC & MCP", "Audio/MIDI Export, OSC & MCP"),
                detail: L(
                    "Export WAV, AIFF, CAF, M4A, ALAC, FLAC, MP3, .mid et stems. Pilotage complet via OSC (:9110), API HTTP (/v1) et serveur MCP.",
                    "Export WAV, AIFF, CAF, M4A, ALAC, FLAC, MP3, .mid and stems. Full remote control via OSC (:9110), HTTP API (/v1) and MCP server."
                )
            ),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // MARK: Header (Icon + Title + Version badge)
            HStack(alignment: .center, spacing: 18) {
                appIconView
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("SimpleAudio")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.text.swiftUI)
                        versionBadge
                    }
                    Text(L(
                        "Éditeur Audio & MIDI multipiste natif ultra-léger — formes d'onde, Piano-Roll, fondus, export & OSC/MCP",
                        "Ultra-light native multitrack Audio & MIDI editor — waveforms, Piano Roll, fades, export & OSC/MCP"
                    ))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.textDim.swiftUI)
                    HStack(spacing: 8) {
                        statusPill(
                            icon: "bolt.horizontal.fill",
                            text: apiListening ? "HTTP API 127.0.0.1:\(apiPort)/v1" : L("HTTP API hors ligne", "HTTP API offline"),
                            tint: apiListening ? Theme.meterSafe : Theme.textFaint
                        )
                        statusPill(
                            icon: "antenna.radiowaves.left.and.right",
                            text: oscListening ? "OSC UDP :\(oscPort)" : L("OSC hors ligne", "OSC offline"),
                            tint: oscListening ? Theme.rangeSelection : Theme.textFaint
                        )
                        statusPill(
                            icon: "waveform",
                            text: "DSP 64-bit · vDSP",
                            tint: Theme.accent
                        )
                    }
                    .padding(.top, 3)
                }
                Spacer(minLength: 0)
            }

            Rectangle()
                .fill(Theme.separator.swiftUI)
                .frame(height: 1)

            // MARK: Architecture & Capabilities Grid
            VStack(alignment: .leading, spacing: 8) {
                Text(L("ARCHITECTURE & MOTEUR AUDIO", "ARCHITECTURE & AUDIO ENGINE"))
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(Theme.textFaint.swiftUI)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                    ],
                    spacing: 10
                ) {
                    ForEach(features) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(item.tint.swiftUI)
                                .frame(width: 24, height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(item.tint.swiftUI.opacity(0.14))
                                )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(Theme.text.swiftUI)
                                Text(item.detail)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Theme.textDim.swiftUI)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineSpacing(1.5)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Theme.lane.swiftUI)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                        )
                    }
                }
            }

            Rectangle()
                .fill(Theme.separator.swiftUI)
                .frame(height: 1)

            // MARK: Footer (Credits + Help + OK button)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Button {
                        if let url = URL(string: "https://adrien-m.net") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Adrien Mondot · cie Adrien M")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textDim.swiftUI)
                            Text("· adrien-m.net ↗")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.accent.swiftUI)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(L("Ouvrir https://adrien-m.net dans le navigateur", "Open https://adrien-m.net in browser"))

                    Text(L(
                        "Éditeur audio natif macOS · Bundle \(Bundle.main.bundleIdentifier ?? "net.cieadrienm.simpleaudio")",
                        "Native macOS audio editor · Bundle \(Bundle.main.bundleIdentifier ?? "net.cieadrienm.simpleaudio")"
                    ))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(Theme.textFaint.swiftUI)
                }
                Spacer()
                Button {
                    close()
                    openUpdates()
                } label: {
                    Label(L("Mises à jour…", "Check for Updates…"), systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textDim.swiftUI)

                Button {
                    close()
                    openHelp()
                } label: {
                    Label(L("Aide (⌘?)", "Help (⌘?)"), systemImage: "book.closed")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textDim.swiftUI)

                Button("OK", action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 580)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
    }

    private var appIconView: some View {
        Group {
            if let icon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 68, height: 68)
                    .shadow(color: Color.black.opacity(0.45), radius: 8, x: 0, y: 4)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.lane.swiftUI)
                    .frame(width: 68, height: 68)
                    .overlay(
                        Image(systemName: "waveform")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Theme.accent.swiftUI)
                    )
            }
        }
    }

    private var versionBadge: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(AppVersion.current.cliLine, forType: .string)
            copiedVersion = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                copiedVersion = false
            }
        } label: {
            HStack(spacing: 5) {
                Text(AppVersion.current.shortLabel)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.accent.swiftUI)
                Image(systemName: copiedVersion ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(copiedVersion ? Theme.meterSafe.swiftUI : Theme.textFaint.swiftUI)
                if copiedVersion {
                    Text(L("Copié", "Copied"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.meterSafe.swiftUI)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Theme.accent.swiftUI.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Theme.accent.swiftUI.opacity(0.32), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(L(
            "Cliquer pour copier « \(AppVersion.current.cliLine) » dans le presse-papiers",
            "Click to copy “\(AppVersion.current.cliLine)” to the clipboard"
        ))
    }

    private func statusPill(icon: String, text: String, tint: NSColor) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(tint.swiftUI)
            Text(text)
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(Theme.textDim.swiftUI)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Theme.lane.swiftUI)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}
