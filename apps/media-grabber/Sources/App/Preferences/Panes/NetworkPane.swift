import GrabberKit
import SwiftUI

struct NetworkPane: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.theme) private var theme

    @State private var proxyText = ""

    private static let speedStep = 100
    private static let speedFloor = 100

    var body: some View {
        @Bindable var prefs = appModel.prefs
        return VStack(alignment: .leading, spacing: 0) {
            PrefPaneHeader(.network)

            PrefRow(
                "Proxy server",
                helper: "http://host:port \u{2014} blank for none."
            ) {
                TextField("", text: $proxyText)
                    .textFieldStyle(.plain)
                    .font(theme.bodyFont(12, .regular))
                    .foregroundStyle(theme.palette.text)
                    .frame(width: 200)
                    .padding(Spacing.s1)
                    .background(
                        theme.palette.panel,
                        in: RoundedRectangle(cornerRadius: theme.controlRadius)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.controlRadius)
                            .stroke(theme.palette.stroke, lineWidth: theme.hairlineWidth)
                    )
                    .onSubmit { prefs.proxyURL = proxyText }
            }

            PrefRow(
                "Force IPv4",
                helper: "Can help when connections stall."
            ) {
                Toggle("", isOn: $prefs.forceIPv4)
                    .labelsHidden()
            }

            PrefRow(
                "Speed limit",
                helper: "Applies to each download separately."
            ) {
                speedStepper(prefs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { proxyText = appModel.prefs.proxyURL ?? "" }
    }

    private func speedStepper(_ prefs: Preferences) -> some View {
        HStack(spacing: Spacing.s2) {
            Text(prefs.speedLimitKBps == 0 ? "Off" : "\(prefs.speedLimitKBps) KB/s")
                .font(theme.monoFont(12, .regular))
                .foregroundStyle(theme.palette.dim)
                .frame(minWidth: 64, alignment: .trailing)
            Stepper(
                "",
                onIncrement: { stepSpeed(prefs, up: true) },
                onDecrement: { stepSpeed(prefs, up: false) }
            )
            .labelsHidden()
        }
    }

    private func stepSpeed(_ prefs: Preferences, up: Bool) {
        let current = prefs.speedLimitKBps
        if up {
            prefs.speedLimitKBps = current == 0 ? Self.speedFloor : current + Self.speedStep
        } else {
            prefs.speedLimitKBps = current <= Self.speedFloor ? 0 : current - Self.speedStep
        }
    }
}
