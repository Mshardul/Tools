import Foundation

#if canImport(AppKit)
    import AppKit
#endif

@MainActor
protocol SettingsLinkOpening {
    func open(_ url: URL)
}

struct WorkspaceSettingsLink: SettingsLinkOpening {
    func open(_ url: URL) {
        #if canImport(AppKit)
            NSWorkspace.shared.open(url)
        #endif
    }
}
