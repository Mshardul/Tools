import Foundation

public enum ShieldInstallOutcome: Sendable, Equatable {
    case installed
    case needsHomebrew
    case failed(detail: String)
}

public struct ShieldInstaller: Sendable {
    // The server and plugin must come from the same release; bump both together, deliberately.
    public static let version = "2.0.2"
    public static let minimumNodeMajor = 22

    private static let repo = "https://github.com/Brainicism/bgutil-ytdlp-pot-provider"
    private static let toolPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    private let runner: ProcessRunning
    private let home: URL
    private let isExecutable: @Sendable (String) -> Bool
    private let fileExists: @Sendable (String) -> Bool
    private let prepareDirectory: @Sendable (URL) -> Void
    private let removeItem: @Sendable (URL) -> Void

    public init(
        runner: ProcessRunning = ProcessRunner(),
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        prepareDirectory: @escaping @Sendable (URL) -> Void = {
            try? FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        },
        removeItem: @escaping @Sendable (URL) -> Void = { try? FileManager.default.removeItem(at: $0) }
    ) {
        self.runner = runner
        self.home = home
        self.isExecutable = isExecutable
        self.fileExists = fileExists
        self.prepareDirectory = prepareDirectory
        self.removeItem = removeItem
    }

    private var supportDirectory: URL {
        home.appendingPathComponent("Library/Application Support/MediaGrabber")
    }

    private var serverRoot: URL {
        supportDirectory.appendingPathComponent("bgutil-server")
    }

    private var serverDirectory: URL {
        serverRoot.appendingPathComponent("server")
    }

    private var pluginZip: URL {
        supportDirectory.appendingPathComponent("bgutil-plugin.zip")
    }

    private var builtServer: URL {
        serverDirectory.appendingPathComponent("build/main.js")
    }

    // Progress callbacks carry short plain-language stage names, never raw tool output.
    public func install(onProgress: @escaping @Sendable (String) -> Void = { _ in }) async -> ShieldInstallOutcome {
        if fileExists(builtServer.path), fileExists(pluginZip.path) {
            return .installed
        }
        let node: String
        switch await ensureNode(onProgress) {
        case let .success(path): node = path
        case .failure(.needsHomebrew): return .needsHomebrew
        case let .failure(.failed(detail)): return .failed(detail: detail)
        }
        prepareDirectory(supportDirectory)

        onProgress("Downloading the shield\u{2026}")
        let tarball = supportDirectory.appendingPathComponent("bgutil-source.tar.gz")
        if let detail = await download(
            "\(Self.repo)/releases/download/\(Self.version)/bgutil-ytdlp-pot-provider.zip",
            to: pluginZip
        ) {
            return .failed(detail: "download: \(detail)")
        }
        if let detail = await download("\(Self.repo)/archive/refs/tags/\(Self.version).tar.gz", to: tarball) {
            return .failed(detail: "download: \(detail)")
        }

        onProgress("Setting it up \u{2014} this can take a minute\u{2026}")
        removeItem(serverRoot)
        prepareDirectory(serverRoot)
        let unpack = await run("/usr/bin/tar", ["-xzf", tarball.path, "-C", serverRoot.path, "--strip-components=1"])
        removeItem(tarball)
        if let detail = unpack.failureDetail {
            return .failed(detail: "unpack: \(detail)")
        }
        let binDirectory = URL(fileURLWithPath: node).deletingLastPathComponent().path
        for tool in ["npm ci", "npx tsc"] {
            let parts = tool.split(separator: " ").map(String.init)
            let result = await run("\(binDirectory)/\(parts[0])", Array(parts.dropFirst()), directory: serverDirectory)
            if let detail = result.failureDetail {
                return .failed(detail: "\(tool): \(detail)")
            }
        }
        guard fileExists(builtServer.path) else {
            return .failed(detail: "the server was built but main.js is missing")
        }
        return .installed
    }

    private enum NodeFailure: Error {
        case needsHomebrew
        case failed(String)
    }

    private func ensureNode(_ onProgress: @Sendable (String) -> Void) async -> Result<String, NodeFailure> {
        let current = nodePath()
        var needsInstall = current == nil
        var upgrade = false
        if let current, await nodeMajor(current) < Self.minimumNodeMajor {
            needsInstall = true
            upgrade = true
        }
        if needsInstall {
            guard let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: isExecutable) else {
                return .failure(.needsHomebrew)
            }
            onProgress("Getting things ready\u{2026}")
            let result = await run(brew, [upgrade ? "upgrade" : "install", "node"])
            if let detail = result.failureDetail {
                return .failure(.failed("node: \(detail)"))
            }
        }
        guard let node = nodePath() else {
            return .failure(.failed("node was not found after installing it"))
        }
        return .success(node)
    }

    private func nodePath() -> String? {
        ["/opt/homebrew/bin/node", "/usr/local/bin/node"].first(where: isExecutable)
    }

    private func nodeMajor(_ node: String) async -> Int {
        let output = await run(node, ["--version"]).stdout.first ?? ""
        let digits = output.drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int(digits) ?? 0
    }

    private func download(_ url: String, to destination: URL) async -> String? {
        await run("/usr/bin/curl", ["-fL", "--retry", "2", "-o", destination.path, url]).failureDetail
    }

    private struct RunResult {
        var exitCode: Int32
        var stdout: [String]
        var stderrTail: [String]

        var failureDetail: String? {
            guard exitCode != 0 else { return nil }
            return stderrTail.isEmpty ? "exited \(exitCode)" : stderrTail.joined(separator: "\n")
        }
    }

    private func run(_ path: String, _ arguments: [String], directory: URL? = nil) async -> RunResult {
        let launch = ProcessLaunch(
            executableURL: URL(fileURLWithPath: path),
            arguments: arguments,
            environment: ["PATH": Self.toolPath],
            currentDirectoryURL: directory
        )
        let execution = runner.run(launch)
        var stdout: [String] = []
        var stderrTail: [String] = []
        for await line in execution.lines {
            switch line {
            case let .stdout(text): stdout.append(text)
            case let .stderr(text): stderrTail = Array((stderrTail + [text]).suffix(5))
            }
        }
        let result = await execution.result()
        return RunResult(exitCode: result.exitCode, stdout: stdout, stderrTail: stderrTail)
    }
}
