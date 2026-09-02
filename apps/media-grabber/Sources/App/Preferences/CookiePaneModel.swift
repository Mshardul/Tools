import Foundation
import GrabberKit
import Observation

@MainActor
@Observable
final class CookiePaneModel {
    private let prefs: Preferences
    private let resolver: CookieResolver
    private let settingsLink: SettingsLinkOpening
    private let openURL: OpenURLSink

    private(set) var firefoxProfiles: [FirefoxProfile] = []
    private(set) var safariAccess: SafariCookieAccess = .noContainer

    init(
        prefs: Preferences,
        resolver: CookieResolver = CookieResolver(),
        settingsLink: SettingsLinkOpening = WorkspaceSettingsLink(),
        openURL: OpenURLSink = WorkspaceOpenURLSink()
    ) {
        self.prefs = prefs
        self.resolver = resolver
        self.settingsLink = settingsLink
        self.openURL = openURL
    }

    var source: CookieSource {
        get { prefs.cookiesFromBrowser }
        set {
            prefs.cookiesFromBrowser = newValue
            refresh()
        }
    }

    var selectedFirefoxProfile: String? {
        get {
            if case let .firefox(profile) = source {
                return profile
            }
            return nil
        }
        set { source = .firefox(profile: newValue) }
    }

    var showsFirefoxProfilePicker: Bool {
        isFirefox && firefoxProfiles.count >= 2
    }

    var showsFirefoxNoProfilesNote: Bool {
        isFirefox && firefoxProfiles.isEmpty
    }

    var showsFullDiskAccessRow: Bool {
        source == .safari && safariAccess != .noContainer
    }

    var showsLearnMore: Bool {
        !source.isNone
    }

    var showsTip: Bool {
        !source.isNone
    }

    func onAppear() {
        refresh()
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ) else {
            return
        }
        settingsLink.open(url)
    }

    func openHelp() {
        openURL.open(CookieHelpURL.url(forBrowserKey: source.browserKey))
    }

    private var isFirefox: Bool {
        if case .firefox = source {
            return true
        }
        return false
    }

    private func refresh() {
        firefoxProfiles = resolver.firefoxProfiles()
        safariAccess = resolver.safariAccess()
        if hasStaleFirefoxProfile() {
            prefs.cookiesFromBrowser = .firefox(profile: nil)
        }
    }

    // A stored .firefox(name) whose profile no longer exists — reset to the default profile.
    private func hasStaleFirefoxProfile() -> Bool {
        guard case let .firefox(name) = prefs.cookiesFromBrowser, let name else { return false }
        return !firefoxProfiles.contains(where: { $0.name == name })
    }
}
