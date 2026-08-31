import AppKit
import GrabberKit
import SwiftUI

struct AdvancedPane: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.theme) private var theme

    private var appDataURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MediaGrabber")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PrefPaneHeader(.advanced)

            PrefRow("App data") {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([appDataURL])
                }
            }

            PrefRow(
                "Reset columns",
                helper: "Table layout back to default."
            ) {
                Button("Reset") {
                    appModel.columnConfig = .default
                }
            }

            PrefRow(
                "Reset settings",
                helper: "All preferences back to default. Downloads are untouched."
            ) {
                Button("Reset\u{2026}") {
                    confirmReset()
                }
                .foregroundStyle(theme.palette.danger)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func confirmReset() {
        Task {
            let confirmed = await appModel.confirm(ConfirmationRequest(
                title: "Reset settings?",
                message: "All preferences go back to their defaults. "
                    + "Your downloads and table columns aren't affected.",
                confirmTitle: "Reset",
                cancelTitle: "Cancel",
                isDestructive: true,
                suppressionKey: nil
            ))
            if confirmed {
                appModel.resetAllSettings()
            }
        }
    }
}
