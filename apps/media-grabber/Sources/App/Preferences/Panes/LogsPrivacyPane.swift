import AppKit
import SwiftUI

struct LogsPrivacyPane: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.theme) private var theme

    private var logFolderURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MediaGrabber")
    }

    var body: some View {
        @Bindable var prefs = appModel.prefs
        return VStack(alignment: .leading, spacing: 0) {
            PrefPaneHeader(.logsPrivacy)

            PrefRow("Log files") {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([logFolderURL])
                }
            }

            PrefRow(
                "Verbose logging",
                helper: "More detail for troubleshooting."
            ) {
                Toggle("", isOn: $prefs.verboseLogging)
                    .labelsHidden()
            }

            PrefRow("Privacy details") {
                Button("Open") {
                    if let url = Bundle.main.url(forResource: "PRIVACY", withExtension: "md") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
