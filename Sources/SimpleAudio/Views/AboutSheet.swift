import AppKit
import SwiftUI

struct AboutSheet: View {
    let apiPort: UInt16
    let apiListening: Bool
    let oscPort: UInt16
    let oscListening: Bool
    let openHelp: () -> Void
    let close: () -> Void

    @State private var copiedVersion = false

    private struct FeatureCard: Identifiable {
        let id = UUID()
        let icon: String
        let tint: NSColor
        let title: String
        let detail: String
    }

    private static let features: [FeatureCard] = [
        FeatureCard(
            icon: "waveform.path.ecg",
            tint: Theme.accent,
            title: "Formes d’onde haute définition",
            detail: "Enveloppes Peak + RMS multi-résolution accélérées par vDSP, affichage stéréo L/R séparé et minimap globale interactive."
        ),
        FeatureCard(
            icon: "scissors",
            tint: Theme.rangeSelection,
            title: "Montage multipiste & Fondus",
            detail: "Scinder (B / S), sélection de plage In/Out, copier-coller, glissement source (⌥-glisser) et 4 courbes de fondu (Cosinus, Linéaire, Expo, Log)."
        ),
        FeatureCard(
            icon: "slider.horizontal.below.waveform",
            tint: Theme.meterLow,
            title: "Mixage temps réel & Normalisation",
            detail: "Moteur AVAudioEngine basse latence, vu-mètres crête stéréo, élagage des silences et normalisation Peak (-0.1 dBFS) ou EBU R128 (-14 LUFS)."
        ),
        FeatureCard(
            icon: "antenna.radiowaves.left.and.right",
            tint: Theme.muteColor,
            title: "Export multi-format, OSC & MCP",
            detail: "Export WAV, AIFF, CAF, M4A, ALAC, FLAC, MP3 et stems par piste. Pilotage complet via OSC (:9110), API HTTP (/v1) et serveur MCP."
        ),
    ]

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
                    Text("Éditeur audio multipiste natif ultra-léger — montage, fondus, export & OSC/MCP")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.textDim.swiftUI)
                    HStack(spacing: 8) {
                        statusPill(
                            icon: "bolt.horizontal.fill",
                            text: apiListening ? "HTTP API 127.0.0.1:\(apiPort)/v1" : "HTTP API hors ligne",
                            tint: apiListening ? Theme.meterSafe : Theme.textFaint
                        )
                        statusPill(
                            icon: "antenna.radiowaves.left.and.right",
                            text: oscListening ? "OSC UDP :\(oscPort)" : "OSC hors ligne",
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
                Text("ARCHITECTURE & MOTEUR AUDIO")
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
                    ForEach(Self.features) { item in
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
                    Text("Adrien Mondot · cie Adrien M")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textDim.swiftUI)
                    Text("Éditeur audio natif macOS · Bundle \(Bundle.main.bundleIdentifier ?? "net.cieadrienm.simpleaudio")")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(Theme.textFaint.swiftUI)
                }
                Spacer()
                Button {
                    close()
                    openHelp()
                } label: {
                    Label("Aide (⌘?)", systemImage: "book.closed")
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
                    Text("Copié")
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
        .help("Cliquer pour copier « \(AppVersion.current.cliLine) » dans le presse-papiers")
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
