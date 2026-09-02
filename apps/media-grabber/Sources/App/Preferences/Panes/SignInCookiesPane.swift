import GrabberKit
import SwiftUI

struct SignInCookiesPane: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.theme) private var theme

    @State private var model: CookiePaneModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PrefPaneHeader(.cookies)
            if let model {
                content(model)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if model == nil {
                model = CookiePaneModel(prefs: appModel.prefs)
            }
            model?.onAppear()
        }
        .onChange(of: model?.source) { _, newValue in
            guard let newValue, !newValue.isNone, appModel.pendingCookieRetryJobID != nil else {
                return
            }
            Task { await appModel.resolveCookieRetry() }
        }
    }

    @ViewBuilder
    private func content(_ model: CookiePaneModel) -> some View {
        if let jobID = appModel.pendingCookieRetryJobID {
            pendingRetryBanner(jobID: jobID)
        }
        browserRow(model)
        firefoxProfileRow(model)
        if model.showsFullDiskAccessRow {
            fullDiskAccessRow(model)
        }
        if model.showsLearnMore {
            learnMoreRow(model)
        }
        if model.showsTip {
            tipBlock
        }
    }

    private func browserRow(_ model: CookiePaneModel) -> some View {
        @Bindable var model = model
        return PrefRow(
            "Browser",
            helper: "Use your browser's YouTube sign-in for age-restricted or private videos."
        ) {
            SkinnedPicker(
                caption: "Browser",
                rows: Self.browserRows,
                selection: Binding(
                    get: { Self.displayCase(for: model.source) },
                    set: { model.source = Self.cookieSource(for: $0) }
                ),
                triggerLabel: Self.displayName(for: model.source)
            )
        }
    }

    @ViewBuilder
    private func firefoxProfileRow(_ model: CookiePaneModel) -> some View {
        @Bindable var model = model
        if model.showsFirefoxProfilePicker {
            PrefRow("Firefox profile") {
                SkinnedPicker(
                    caption: "Profile",
                    rows: model.firefoxProfiles.map {
                        SkinnedPickerRow(id: $0.name, title: $0.name, subtitle: nil)
                    },
                    selection: Binding(
                        get: { model.selectedFirefoxProfile ?? Self.defaultProfileName(model) },
                        set: { model.selectedFirefoxProfile = $0 }
                    ),
                    triggerLabel: model.selectedFirefoxProfile ?? Self.defaultProfileName(model)
                )
            }
        } else if model.showsFirefoxNoProfilesNote {
            PrefRow("Firefox profile") {
                Text("No Firefox profiles found.")
                    .font(theme.bodyFont(11.5, .regular))
                    .foregroundStyle(theme.palette.dim)
            }
        }
    }

    private func learnMoreRow(_ model: CookiePaneModel) -> some View {
        PrefRow("Cookie access for \(Self.displayName(for: model.source))") {
            Button("Learn more \u{2197}") { model.openHelp() }
                .buttonStyle(.plain)
                .font(theme.bodyFont(12, .medium))
                .foregroundStyle(theme.palette.accent)
        }
    }

    private var tipBlock: some View {
        Text(
            "For the most reliable results, use a browser profile that's signed in to "
                + "YouTube and keep it closed while downloading."
        )
        .font(theme.bodyFont(11.5, .regular))
        .foregroundStyle(theme.palette.dim)
        .padding(.top, Spacing.s3)
    }

    @ViewBuilder
    private func fullDiskAccessRow(_ model: CookiePaneModel) -> some View {
        switch model.safariAccess {
        case .granted:
            PrefRow("Full Disk Access") {
                HStack(spacing: Spacing.s1) {
                    Circle().fill(theme.palette.accent).frame(width: 8, height: 8)
                    Text("Full Disk Access granted.")
                        .font(theme.bodyFont(12, .regular))
                        .foregroundStyle(theme.palette.dim)
                }
            }
        case .denied:
            PrefRow(
                "Full Disk Access",
                helper: "MediaGrabber needs Full Disk Access to read Safari's sign-in."
            ) {
                HStack(spacing: Spacing.s2) {
                    Icon(kind: .warning, size: 12).foregroundStyle(theme.palette.warn)
                    Button("Open System Settings") { model.openFullDiskAccessSettings() }
                }
            }
        case .noContainer:
            EmptyView()
        }
    }

    private func pendingRetryBanner(jobID: UUID) -> some View {
        let title = appModel.rowStore.rows.first { $0.id == jobID }?.snapshot.title
        return HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
            Icon(kind: .warning, size: 12).foregroundStyle(theme.palette.warn)
            Text(Self.pendingBannerText(jobTitle: title))
                .font(theme.bodyFont(12, .regular))
                .foregroundStyle(theme.palette.text)
        }
        .padding(.vertical, Spacing.s3)
    }

    // MARK: - Static helpers (unit-tested without rendering)

    static func displayName(for source: CookieSource) -> String {
        switch source {
        case .none: "None"
        case .safari: "Safari"
        case .chrome: "Chrome"
        case .brave: "Brave"
        case .edge: "Microsoft Edge"
        case .firefox: "Firefox"
        }
    }

    static func pendingBannerText(jobTitle: String?) -> String {
        "Pick a browser to retry \"\(jobTitle ?? "this download")\" with your sign-in."
    }

    private enum BrowserCase: String, Hashable, CaseIterable {
        case none, safari, chrome, brave, edge, firefox
    }

    private static var browserRows: [SkinnedPickerRow<BrowserCase>] {
        BrowserCase.allCases.map {
            SkinnedPickerRow(id: $0, title: displayName(for: cookieSource(for: $0)), subtitle: nil)
        }
    }

    private static func displayCase(for source: CookieSource) -> BrowserCase {
        switch source {
        case .none: .none
        case .safari: .safari
        case .chrome: .chrome
        case .brave: .brave
        case .edge: .edge
        case .firefox: .firefox
        }
    }

    private static func cookieSource(for browserCase: BrowserCase) -> CookieSource {
        switch browserCase {
        case .none: .none
        case .safari: .safari
        case .chrome: .chrome
        case .brave: .brave
        case .edge: .edge
        case .firefox: .firefox(profile: nil)
        }
    }

    private static func defaultProfileName(_ model: CookiePaneModel) -> String {
        model.firefoxProfiles.first(where: \.isDefault)?.name
            ?? model.firefoxProfiles.first?.name
            ?? ""
    }
}
