import SwiftUI
import SimpleAudioCore

struct PreferencesView: View {
    @Bindable var model: AppModel
    var onReconnectNetwork: () -> Void

    var body: some View {
        let _ = model.language
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(L("Langue", "Language"))

            FieldRow(L("Langue", "Language")) {
                Picker("", selection: $model.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.label).tag(lang)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 160)
            }

            Divider().overlay(Color(nsColor: Theme.separator))
            SectionHeader(L("Interfaces Réseau & Automatisation", "Network & Automation Interfaces"))

            FieldRow(L("Port HTTP / MCP", "HTTP / MCP Port")) {
                NumberField(
                    value: Double(model.apiPort),
                    unit: "",
                    step: 1,
                    range: 1024...65535,
                    decimals: 0
                ) { val in
                    model.apiPort = UInt16(val)
                    onReconnectNetwork()
                }
                Circle()
                    .fill(Color(nsColor: model.apiListening ? Theme.meterSafe : Theme.textFaint))
                    .frame(width: 8, height: 8)
            }

            FieldRow(L("Port OSC (UDP In)", "OSC Port (UDP In)")) {
                NumberField(
                    value: Double(model.oscInputPort),
                    unit: "",
                    step: 1,
                    range: 1024...65535,
                    decimals: 0
                ) { val in
                    model.oscInputPort = UInt16(val)
                    onReconnectNetwork()
                }
                Circle()
                    .fill(Color(nsColor: model.oscListening ? Theme.meterSafe : Theme.textFaint))
                    .frame(width: 8, height: 8)
            }

            Divider().overlay(Color(nsColor: Theme.separator))
            SectionHeader(L("Retour OSC (UDP Out)", "OSC Feedback (UDP Out)"))

            Toggle(L("Émettre la position et les niveaux en OSC", "Emit playhead position and levels via OSC"), isOn: $model.oscFeedbackEnabled)
                .font(.system(size: 11.5))
                .foregroundStyle(Color(nsColor: Theme.text))

            FieldRow(L("Hôte cible", "Target Host")) {
                CommitField(value: model.oscOutputHost, placeholder: "127.0.0.1") { host in
                    model.oscOutputHost = host
                }
                .frame(width: 120)
            }

            FieldRow(L("Port cible", "Target Port")) {
                NumberField(
                    value: Double(model.oscOutputPort),
                    unit: "",
                    step: 1,
                    range: 1024...65535,
                    decimals: 0
                ) { val in
                    model.oscOutputPort = UInt16(val)
                }
            }

            Divider().overlay(Color(nsColor: Theme.separator))
            SectionHeader(L("Mises à jour", "Updates"))

            HStack(spacing: 12) {
                Toggle(
                    L("Vérifier les mises à jour au lancement", "Check for updates on launch"),
                    isOn: $model.updater.autoCheckOnLaunch
                )
                .font(.system(size: 11.5))
                .foregroundStyle(Color(nsColor: Theme.text))

                Spacer()

                TextButton(
                    title: L("Vérifier maintenant…", "Check Now…"),
                    symbol: "arrow.clockwise",
                    compact: true
                ) {
                    model.showUpdater = true
                    model.updater.checkForUpdates(silent: false)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 440, height: 420)
        .background(Color(nsColor: Theme.panel))
        .preferredColorScheme(.dark)
    }
}
