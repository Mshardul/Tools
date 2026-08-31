enum PreferencesPane: String, CaseIterable, Hashable {
    case downloads
    case appearance
    case network
    case cookies
    case updates
    case logsPrivacy
    case advanced

    var title: String {
        switch self {
        case .downloads: "Downloads"
        case .appearance: "Appearance"
        case .network: "Network"
        case .cookies: "Sign-in & cookies"
        case .updates: "Updates"
        case .logsPrivacy: "Logs & privacy"
        case .advanced: "Advanced"
        }
    }

    var subtitle: String {
        switch self {
        case .downloads:
            "Defaults for new downloads. Change any of these per download on the Home screen."
        case .appearance:
            "Pick a look. Theme sets the personality; palette sets the colours."
        case .network:
            "Applied to new downloads."
        case .cookies:
            "Sign in to reach private or age-restricted videos."
        case .updates:
            "Check for new versions of the app and the downloader."
        case .logsPrivacy:
            "What the app records, and where to find it."
        case .advanced:
            "Reset options. These don't touch your downloaded files."
        }
    }

    var group: PreferencesRailGroup {
        switch self {
        case .downloads, .appearance, .network: .general
        case .cookies: .youtube
        case .updates, .logsPrivacy, .advanced: .system
        }
    }
}

enum PreferencesRailGroup: String, CaseIterable, Hashable {
    case general
    case youtube
    case system

    var caption: String {
        switch self {
        case .general: "General"
        case .youtube: "YouTube"
        case .system: "System"
        }
    }

    var panes: [PreferencesPane] {
        PreferencesPane.allCases.filter { $0.group == self }
    }
}
