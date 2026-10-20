import SwiftUI

struct PreferencesView: View {
    @Bindable var model: AppModel
    var onReconnectNetwork: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader("Interfaces Réseau & Automatisation")

            FieldRow("Port HTTP / MCP") {
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

            FieldRow("Port OSC (UDP In)") {
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
            SectionHeader("Retour OSC (UDP Out)")

            Toggle("Émettre la position et les niveaux en OSC", isOn: $model.oscFeedbackEnabled)
                .font(.system(size: 11.5))
                .foregroundStyle(Color(nsColor: Theme.text))

            FieldRow("Hôte cible") {
                CommitField(value: model.oscOutputHost, placeholder: "127.0.0.1") { host in
                    model.oscOutputHost = host
                }
                .frame(width: 120)
            }

            FieldRow("Port cible") {
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

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 390, height: 290)
        .background(Color(nsColor: Theme.panel))
        .preferredColorScheme(.dark)
    }
}
