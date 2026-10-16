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
    private let signInProbe: (any MetadataProbing)?

    enum SignInTest: Equatable {
        case idle
        case running
        case passed(String)
        case failed(String)
    }

    private(set) var signInTest: SignInTest = .idle
    private(set) var firefoxProfiles: [FirefoxProfile] = []
    private(set) var safariAccess: SafariCookieAccess = .noContainer
    private(set) var chromiumBrowserFound = true

    init(
        prefs: Preferences,
        resolver: CookieResolver = CookieResolver(),
        settingsLink: SettingsLinkOpening = WorkspaceSettingsLink(),
        openURL: OpenURLSink = WorkspaceOpenURLSink(),
        signInProbe: (any MetadataProbing)? = nil
    ) {
        self.signInProbe = signInProbe
        self.prefs = prefs
        self.resolver = resolver
        self.settingsLink = settingsLink
        self.openURL = openURL
    }

    var source: CookieSource {
        get { prefs.cookiesFromBrowser }
        set {
            prefs.cookiesFromBrowser = newValue
            signInTest = .idle
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

    var showsChromiumNotFoundNote: Bool {
        isChromium && !chromiumBrowserFound
    }

    var canTestSignIn: Bool {
        !source.isNone && signInProbe != nil
    }

    func testSignIn() async {
        guard let signInProbe, signInTest != .running else { return }
        let name = SignInCookiesPane.displayName(for: source)
        let resolution = resolver.resolve(source: source, jobOverride: false)
        guard let argument = resolution.argument else {
            signInTest = .failed(message(for: resolution.verdict, browser: name))
            return
        }
        signInTest = .running
        var context = ExtractorContext.none
        context.cookieArgument = argument
        switch await signInProbe.probe(CanaryProbe.url, context: context) {
        case .success:
            signInTest = .passed("MediaGrabber can read your \(name) sign-in.")
        case .failure(.cookieReadFailed):
            signInTest = .failed(
                "MediaGrabber couldn't read your \(name) sign-in. Close \(name) and try again. "
                    + "If your Mac asks for permission, choose Allow."
            )
        case .failure(.network):
            signInTest = .failed("The test couldn't finish because there's no internet connection.")
        case .failure:
            signInTest = .failed("The test couldn't finish. Try again in a moment.")
        }
    }

    private func message(for verdict: CookieVerdict, browser: String) -> String {
        switch verdict {
        case .needsFullDiskAccess where safariAccess == .denied:
            "MediaGrabber needs permission to read \(browser) first. Use the Full Disk Access button above."
        case .needsFullDiskAccess, .noProfiles, .unconfigured, .ready:
            "\(browser) isn't installed on this Mac, or hasn't been opened yet."
        }
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

    private var isChromium: Bool {
        switch source {
        case .chrome, .brave, .edge: true
        default: false
        }
    }

    private func refresh() {
        firefoxProfiles = resolver.firefoxProfiles()
        safariAccess = resolver.safariAccess()
        if isChromium {
            chromiumBrowserFound = resolver.resolve(source: source, jobOverride: false).verdict != .noProfiles
        }
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
