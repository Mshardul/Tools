import Foundation

public struct ManagedTools: Sendable {
    public let resourceRoot: URL
    public let supportRoot: URL
    public let isExecutable: @Sendable (URL) -> Bool
    public let versionOf: @Sendable (URL) -> String?

    public init(
        resourceRoot: URL,
        supportRoot: URL,
        isExecutable: @escaping @Sendable (URL) -> Bool = { url in
            FileManager.default.isExecutableFile(atPath: url.path)
        },
        versionOf: @escaping @Sendable (URL) -> String? = ManagedTools.runVersion
    ) {
        self.resourceRoot = resourceRoot
        self.supportRoot = supportRoot
        self.isExecutable = isExecutable
        self.versionOf = versionOf
    }

    public static func live(
        bundle: Bundle = .main,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> ManagedTools {
        let resources = bundle.resourceURL ?? bundle.bundleURL.appendingPathComponent("Contents/Resources")
        let support = home.appendingPathComponent("Library/Application Support/MediaGrabber")
        return ManagedTools(resourceRoot: resources, supportRoot: support)
    }

    public var bundledYtDlp: URL {
        resourceRoot.appendingPathComponent("Tools/yt-dlp")
    }

    public var updatedYtDlp: URL {
        supportRoot.appendingPathComponent("bin/yt-dlp")
    }

    public var ffmpegURL: URL {
        resourceRoot.appendingPathComponent("Tools/ffmpeg")
    }

    public var ffprobeURL: URL {
        resourceRoot.appendingPathComponent("Tools/ffprobe")
    }

    public var nodeURL: URL {
        resourceRoot.appendingPathComponent("Tools/node")
    }

    public var shieldServer: URL {
        resourceRoot.appendingPathComponent("Shield/server/build/main.js")
    }

    public var shieldPlugin: URL {
        resourceRoot.appendingPathComponent("Shield/plugin.zip")
    }

    public func ytDlpURL() -> URL {
        let bundled = bundledYtDlp
        let updated = updatedYtDlp
        guard isExecutable(updated) else { return bundled }
        guard isExecutable(bundled) else { return updated }
        guard let bundledVersion = versionOf(bundled),
              let updatedVersion = versionOf(updated),
              let bundledParsed = DottedVersion(parsing: bundledVersion),
              let updatedParsed = DottedVersion(parsing: updatedVersion),
              updatedParsed > bundledParsed
        else { return bundled }
        return updated
    }

    public static func runVersion(_ url: URL) -> String? {
        let process = Process()
        process.executableURL = url
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return EnvironmentProbe.parseYtDlp(output)
    }
}
