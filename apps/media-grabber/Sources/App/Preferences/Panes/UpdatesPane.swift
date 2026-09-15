import SwiftUI

struct UpdatesPane: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var prefs = appModel.prefs
        return VStack(alignment: .leading, spacing: 0) {
            PrefPaneHeader(.updates)

            PrefRow(
                "Check for app updates automatically",
                helper: "Looks for a newer MediaGrabber release once a day."
            ) {
                Toggle("", isOn: $prefs.autoCheckAppUpdates)
                    .labelsHidden()
            }

            PrefRow(
                "Notify when the downloader is outdated",
                helper: "Warn if yt-dlp falls behind the version this app expects."
            ) {
                Toggle("", isOn: $prefs.autoCheckYtDlpUpdates)
                    .labelsHidden()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
