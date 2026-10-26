import AppKit
import SwiftUI
import SimpleAudioCore

struct UpdateSheet: View {
    @Bindable var updater: SimpleUpdater
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                appIcon
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Mises à jour de SimpleAudio", "SimpleAudio Updates"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.text.swiftUI)
                    Text(L(
                        "Version actuelle : \(AppVersion.current.shortLabel)",
                        "Current version: \(AppVersion.current.shortLabel)"
                    ))
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(Theme.textDim.swiftUI)
                }
                Spacer()
            }

            Rectangle()
                .fill(Theme.separator.swiftUI)
                .frame(height: 1)

            statusContent
                .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(Theme.separator.swiftUI)
                .frame(height: 1)

            HStack(spacing: 12) {
                Toggle(
                    L("Vérifier les mises à jour au lancement", "Check for updates on launch"),
                    isOn: $updater.autoCheckOnLaunch
                )
                .font(.system(size: 11))
                .foregroundStyle(Theme.textDim.swiftUI)

                Spacer()

                if case .updateAvailable(let rel) = updater.state {
                    Button(L("Plus tard", "Later"), action: close)
                    TextButton(
                        title: L("Mettre à jour et relancer", "Update & Relaunch"),
                        symbol: "arrow.down.circle.fill",
                        prominent: true
                    ) {
                        updater.downloadAndInstall(rel)
                    }
                } else {
                    TextButton(
                        title: L("Vérifier maintenant…", "Check Now…"),
                        symbol: "arrow.clockwise",
                        disabled: isBusy
                    ) {
                        updater.checkForUpdates(silent: false)
                    }
                    Button(L("Fermer", "Close"), action: close)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
    }

    private var isBusy: Bool {
        switch updater.state {
        case .checking, .downloading, .installing:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch updater.state {
        case .idle:
            statusRow(
                icon: "arrow.triangle.2.circlepath.circle",
                tint: Theme.textDim,
                title: L("Prêt à vérifier les mises à jour", "Ready to check for updates"),
                subtitle: L(
                    "Cliquez sur « Vérifier maintenant… » pour interroger le serveur de versions.",
                    "Click “Check Now…” to query the release server."
                )
            )
        case .checking:
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text(L("Recherche de mises à jour en cours…", "Checking for updates…"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.text.swiftUI)
            }
            .padding(.vertical, 8)
        case .upToDate(let ver):
            statusRow(
                icon: "checkmark.seal.fill",
                tint: Theme.meterSafe,
                title: L("SimpleAudio est à jour", "SimpleAudio is up to date"),
                subtitle: L(
                    "Vous disposez déjà de la dernière version disponible (v\(ver)).",
                    "You are running the latest available version (v\(ver))."
                )
            )
        case .updateAvailable(let rel):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.accent.swiftUI)
                    Text(L(
                        "Nouvelle version disponible : v\(rel.version)",
                        "New version available: v\(rel.version)"
                    ))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text.swiftUI)
                }

                ScrollView {
                    Text(rel.localizedNotes)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textDim.swiftUI)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(height: 110)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.lane.swiftUI)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                        )
                )
            }
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Téléchargement de la mise à jour…", "Downloading update…"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.text.swiftUI)
                ProgressView(value: max(0.05, min(1.0, progress)))
                    .progressViewStyle(.linear)
                    .tint(Theme.accent.swiftUI)
            }
            .padding(.vertical, 6)
        case .installing:
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text(L(
                    "Vérification de la signature et installation… SimpleAudio va redémarrer.",
                    "Verifying signature and installing… SimpleAudio will relaunch."
                ))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text.swiftUI)
            }
            .padding(.vertical, 8)
        case .failed(let msg):
            statusRow(
                icon: "exclamationmark.triangle.fill",
                tint: Theme.meterHot,
                title: L("Impossible de vérifier ou d'installer la mise à jour", "Update check or installation failed"),
                subtitle: msg
            )
        }
    }

    private func statusRow(icon: String, tint: NSColor, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint.swiftUI)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text.swiftUI)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textDim.swiftUI)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private var appIcon: some View {
        Group {
            if let icon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 44, height: 44)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.lane.swiftUI)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "waveform")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Theme.accent.swiftUI)
                    )
            }
        }
    }
}
