import Foundation

public struct PotPluginInstaller: Sendable {
    private let home: URL
    private let tools: ManagedTools
    private let isExecutable: @Sendable (URL) -> Bool
    private let fileExists: @Sendable (URL) -> Bool
    private let pluginStore: any PluginStoring

    public init(
        home: URL,
        tools: ManagedTools,
        isExecutable: @escaping @Sendable (URL) -> Bool,
        fileExists: @escaping @Sendable (URL) -> Bool,
        pluginStore: any PluginStoring
    ) {
        self.home = home
        self.tools = tools
        self.isExecutable = isExecutable
        self.fileExists = fileExists
        self.pluginStore = pluginStore
    }

    public static func live(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> PotPluginInstaller {
        PotPluginInstaller(
            home: home,
            tools: .live(home: home),
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
        let node = tools.nodeURL
        guard isExecutable(node), let mainJS = nodeEntry() else { return nil }
        return ProcessLaunch(
            executableURL: node,
            arguments: [mainJS.path, "--host", host, "--port", "\(port)"]
        )
    }

    private var pluginDest: URL {
        home.appendingPathComponent("Library/Application Support/MediaGrabber/yt-dlp-plugins")
    }

    private func nodeEntry() -> URL? {
        if let bundled = existing(tools.shieldServer) {
            return bundled
        }
        return existing(appSupportMainJS)
    }

    private var appSupportMainJS: URL {
        home.appendingPathComponent(
            "Library/Application Support/MediaGrabber/bgutil-server/server/build/main.js"
        )
    }

    private func pluginSource() -> URL? {
        if let zip = existing(tools.shieldPlugin) {
            return zip
        }
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
