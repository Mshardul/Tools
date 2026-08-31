import SwiftUI

struct PreferencesView: View {
    @Environment(\.theme) private var theme

    @State private var selectedPane: PreferencesPane

    init(initialPane: PreferencesPane = .downloads) {
        _selectedPane = State(initialValue: initialPane)
    }

    var body: some View {
        HStack(spacing: 0) {
            rail
                .frame(width: 200)
            Divider().overlay(theme.palette.hair)
            ScrollView {
                paneBody
                    .padding(Spacing.s6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            ForEach(PreferencesRailGroup.allCases, id: \.self) { group in
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(group.caption)
                        .font(theme.monoFont(10, .medium))
                        .textCase(.uppercase)
                        .foregroundStyle(theme.palette.faint)
                        .padding(.horizontal, Spacing.s3)
                        .padding(.bottom, 2)
                    ForEach(group.panes, id: \.self) { pane in
                        railButton(pane)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.s5)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func railButton(_ pane: PreferencesPane) -> some View {
        let active = pane == selectedPane
        return Button { selectedPane = pane } label: {
            Text(pane.title)
                .font(theme.bodyFont(12, active ? .semibold : .regular))
                .foregroundStyle(active ? theme.palette.text : theme.palette.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.s3)
                .padding(.vertical, Spacing.s1)
                .background(
                    active ? theme.palette.panel : .clear,
                    in: RoundedRectangle(cornerRadius: theme.chipRadius)
                )
        }
        .buttonStyle(.plain)
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
        }
    }
}
