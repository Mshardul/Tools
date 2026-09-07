import Foundation

public struct PotPluginInstaller: Sendable {
    private let home: URL
    private let searchPaths: [URL]
    private let isExecutable: @Sendable (URL) -> Bool
    private let fileExists: @Sendable (URL) -> Bool
    private let pluginStore: any PluginStoring

    public init(
        home: URL,
        searchPaths: [URL],
        isExecutable: @escaping @Sendable (URL) -> Bool,
        fileExists: @escaping @Sendable (URL) -> Bool,
        pluginStore: any PluginStoring
    ) {
        self.home = home
        self.searchPaths = searchPaths
        self.isExecutable = isExecutable
        self.fileExists = fileExists
        self.pluginStore = pluginStore
    }

    public static func live(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> PotPluginInstaller {
        PotPluginInstaller(
            home: home,
            searchPaths: EnvironmentProbe.defaultSearchPaths,
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0.path) },
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            pluginStore: FoundationPluginStore()
        )
    }

    public func pluginDirs() -> [URL] {
        guard let source = pluginSource() else {
            return []
        }
        let dest = pluginDest
        try? pluginStore.createDirectory(at: dest)
        let target = dest.appendingPathComponent(source.lastPathComponent)
        if !pluginStore.fileExists(atPath: target.path) {
            try? pluginStore.copyItem(at: source, to: target)
        }
        guard pluginStore.fileExists(atPath: target.path) else {
            return []
        }
        return [dest]
    }

    public func resolveServerLaunch(port: Int, host: String = "127.0.0.1") -> ProcessLaunch? {
        if let bgutil = firstExecutable(named: "bgutil-ytdlp-pot-provider") {
            return ProcessLaunch(
                executableURL: bgutil,
                arguments: ["--host", host, "--port", "\(port)"]
            )
        }
        guard let node = firstExecutable(named: "node"), let mainJS = nodeEntry() else {
            return nil
        }
        return ProcessLaunch(
            executableURL: node,
            arguments: [mainJS.path, "--host", host, "--port", "\(port)"]
        )
    }

    private var pluginDest: URL {
        home.appendingPathComponent("Library/Application Support/MediaGrabber/yt-dlp-plugins")
    }

    private func firstExecutable(named name: String) -> URL? {
        searchPaths
            .map { $0.appendingPathComponent(name) }
            .first { isExecutable($0) }
    }

    private func nodeEntry() -> URL? {
        if let appSupport = existing(appSupportMainJS) {
            return appSupport
        }
        if let pipx = pipxMainJS(root: pipxShareLib) {
            return pipx
        }
        return pipxMainJS(root: pipxLegacyLib)
    }

    private var appSupportMainJS: URL {
        home.appendingPathComponent(
            "Library/Application Support/MediaGrabber/bgutil-server/server/build/main.js"
        )
    }

    private var pipxShareLib: URL {
        home.appendingPathComponent(".local/share/pipx/venvs/bgutil-ytdlp-pot-provider/lib")
    }

    private var pipxLegacyLib: URL {
        home.appendingPathComponent(".local/pipx/venvs/bgutil-ytdlp-pot-provider/lib")
    }

    private func pipxMainJS(root: URL) -> URL? {
        let pythons = pluginStore.contentsOfDirectory(at: root).filter {
            $0.lastPathComponent.hasPrefix("python")
        }
        var index = 0
        while index < pythons.count {
            if let found = mainJS(underSitePackages: pythons[index]) {
                return found
            }
            index += 1
        }
        return nil
    }

    private func mainJS(underSitePackages pythonDir: URL) -> URL? {
        let site = pythonDir.appendingPathComponent("site-packages")
        let packages = pluginStore.contentsOfDirectory(at: site)
        var index = 0
        while index < packages.count {
            let candidate = packages[index].appendingPathComponent("server/build/main.js")
            if fileExists(candidate) {
                return candidate
            }
            index += 1
        }
        return nil
    }

    private func pluginSource() -> URL? {
        if let fromJS = nodeEntry().flatMap(pluginsBesideMainJS), fileExists(fromJS) {
            return fromJS
        }
        let zip = home.appendingPathComponent(
            "Library/Application Support/MediaGrabber/bgutil-plugin.zip"
        )
        return existing(zip)
    }

    private func pluginsBesideMainJS(_ mainJS: URL) -> URL {
        mainJS
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("yt_dlp_plugins")
    }

    private func existing(_ url: URL) -> URL? {
        fileExists(url) ? url : nil
    }
}
