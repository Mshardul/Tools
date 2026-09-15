import SwiftUI

struct PreferencesView: View {
    let selectedPane: PreferencesPane

    var body: some View {
        ScrollView {
            paneBody
                .padding(Spacing.s6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var paneBody: some View {
        switch selectedPane {
        case .downloads: DownloadsPane()
        case .appearance: AppearancePane()
        case .network: NetworkPane()
        case .cookies: SignInCookiesPane()
        case .updates: UpdatesPane()
        case .logsPrivacy: LogsPrivacyPane()
        case .advanced: AdvancedPane()
        case .diagnostics: DiagnosticsPane()
        }
    }
}
