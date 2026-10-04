import AppKit
import SwiftUI

struct DebugMenuCommands: Commands {
    let appModel: AppModel
    let relauncher: AppRelauncher

    var body: some Commands {
        CommandMenu("Debug") {
            Button("Force Onboarding (Relaunch)") {
                relauncher.relaunch(withExtraArguments: ["-MGForceOnboarding"])
            }
            Button("Reset State (Relaunch)…") {
                confirmAndReset()
            }
            Divider()
            Menu("Concurrency Cap") {
                ForEach([1, 2, 3, 4, 5, 6], id: \.self) { cap in
                    Button("\(cap)") {
                        appModel.prefs.maxConcurrentDownloads = cap
                    }
                }
            }
        }
    }

    private func confirmAndReset() {
        let alert = NSAlert()
        alert.messageText = "Reset all local state?"
        alert.informativeText =
            "This wipes the download queue, history, and preferences, then relaunches. This cannot be undone."
        alert.addButton(withTitle: "Reset and Relaunch")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        relauncher.relaunch(withExtraArguments: ["-MGResetState"])
    }
}
