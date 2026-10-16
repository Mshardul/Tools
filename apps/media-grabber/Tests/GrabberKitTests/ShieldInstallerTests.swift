@testable import GrabberKit
import TestSupport
import XCTest

final class ShieldInstallerTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/tester")

    private final class Disk: @unchecked Sendable {
        private let lock = NSLock()
        private var paths: Set<String>
        init(_ paths: Set<String>) {
            self.paths = paths
        }

        func has(_ path: String) -> Bool {
            lock.withLock { paths.contains(path) }
        }

        func add(_ path: String) {
            lock.withLock { _ = paths.insert(path) }
        }

        func remove(_ path: String) {
            lock.withLock { _ = paths.remove(path) }
        }
    }

    private var support: String {
        home.path + "/Library/Application Support/MediaGrabber"
    }

    private var mainJS: String {
        support + "/bgutil-server/server/build/main.js"
    }

    private var plugin: String {
        support + "/bgutil-plugin.zip"
    }

    private func installer(
        runner: FakeProcessRunner,
        disk: Disk,
        brew: Bool = true
    ) -> ShieldInstaller {
        ShieldInstaller(
            runner: runner,
            home: home,
            isExecutable: { disk.has($0) || (brew && $0 == "/opt/homebrew/bin/brew") },
            fileExists: { disk.has($0) },
            prepareDirectory: { _ in },
            removeItem: { disk.remove($0.path) }
        )
    }

    private func succeedingRunner(nodeVersion: String = "v24.8.0") -> FakeProcessRunner {
        let runner = FakeProcessRunner()
        runner.script(.stdout(nodeVersion), forPathEndingIn: "node")
        for tool in ["curl", "tar", "npm", "npx", "brew"] {
            runner.script(.stdout("ok"), forPathEndingIn: tool)
        }
        return runner
    }

    private func commands(_ runner: FakeProcessRunner) -> [String] {
        runner.launches
            .map { $0.executableURL.lastPathComponent + " " + $0.arguments.first.map(\.self).debugDescription }
    }

    func test_alreadyInstalled_doesNothing() async {
        let runner = succeedingRunner()
        let disk = Disk([mainJS, plugin])
        let outcome = await installer(runner: runner, disk: disk).install()
        XCTAssertEqual(outcome, .installed)
        XCTAssertTrue(runner.launches.isEmpty)
    }

    func test_nodePresent_downloadsPluginAndServerThenBuilds() async {
        let runner = succeedingRunner()
        let disk = Disk(["/opt/homebrew/bin/node"])
        let sut = ShieldInstaller(
            runner: runner, home: home,
            isExecutable: { disk.has($0) },
            fileExists: { disk.has($0) },
            prepareDirectory: { _ in },
            removeItem: { disk.remove($0.path) }
        )
        runner.script(.stdout("ok"), forPathEndingIn: "npx")
        // Building produces main.js; emulate by registering it once npx runs (checked after the run).
        disk.add(mainJS)
        let outcome = await sut.install()
        XCTAssertEqual(outcome, .installed)
        let names = runner.launches.map(\.executableURL.lastPathComponent)
        XCTAssertEqual(names, ["node", "curl", "curl", "tar", "npm", "npx"])
        let urls = runner.launches.filter { $0.executableURL.lastPathComponent == "curl" }.compactMap(\.arguments.last)
        XCTAssertTrue(urls[0].hasSuffix("/releases/download/\(ShieldInstaller.version)/bgutil-ytdlp-pot-provider.zip"))
        XCTAssertTrue(urls[1].hasSuffix("/archive/refs/tags/\(ShieldInstaller.version).tar.gz"))
        XCTAssertEqual(runner.launches[4].arguments, ["ci"])
        XCTAssertEqual(runner.launches[5].arguments, ["tsc"])
    }

    func test_buildToolsGetAUsablePath() async {
        let runner = succeedingRunner()
        let disk = Disk(["/opt/homebrew/bin/node", mainJS])
        _ = await installer(runner: runner, disk: disk).install()
        let npm = runner.launches.first { $0.executableURL.lastPathComponent == "npm" }
        XCTAssertTrue(npm?.environment?["PATH"]?.contains("/opt/homebrew/bin") ?? false)
    }

    func test_nodeMissing_installsItThroughHomebrew() async {
        let runner = succeedingRunner()
        let disk = Disk([mainJS])
        let sut = ShieldInstaller(
            runner: runner, home: home,
            isExecutable: {
                $0 == "/opt/homebrew/bin/brew" ||
                    ($0 == "/opt/homebrew/bin/node" && runner.launches.contains { $0.arguments == [
                        "install",
                        "node"
                    ] })
            },
            fileExists: { disk.has($0) },
            prepareDirectory: { _ in },
            removeItem: { disk.remove($0.path) }
        )
        let outcome = await sut.install()
        XCTAssertEqual(outcome, .installed)
        XCTAssertEqual(runner.launches.first?.arguments, ["install", "node"])
    }

    func test_nodeTooOld_isUpgradedNotReinstalled() async {
        let runner = succeedingRunner(nodeVersion: "v20.11.0")
        let disk = Disk(["/opt/homebrew/bin/node", mainJS])
        _ = await installer(runner: runner, disk: disk).install()
        XCTAssertTrue(runner.launches.contains { $0.arguments == ["upgrade", "node"] })
        XCTAssertFalse(runner.launches.contains { $0.arguments == ["install", "node"] })
    }

    func test_nodeMissingAndNoHomebrew_needsHomebrew_andRunsNothing() async {
        let runner = succeedingRunner()
        let outcome = await installer(runner: runner, disk: Disk([]), brew: false).install()
        XCTAssertEqual(outcome, .needsHomebrew)
        XCTAssertTrue(runner.launches.isEmpty)
    }

    func test_downloadFailure_isReportedAndStopsBeforeBuilding() async {
        let runner = succeedingRunner()
        runner.script(.stderr("curl: (6) Could not resolve host\n"), forPathEndingIn: "curl")
        let disk = Disk(["/opt/homebrew/bin/node"])
        let outcome = await installer(runner: runner, disk: disk).install()
        guard case let .failed(detail) = outcome else { return XCTFail("expected failure") }
        XCTAssertTrue(detail.hasPrefix("download:"))
        XCTAssertFalse(runner.launches.contains { $0.executableURL.lastPathComponent == "npm" })
    }

    func test_buildFailure_isReported() async {
        let runner = succeedingRunner()
        runner.script(.stderr("npm ERR! boom\n"), forPathEndingIn: "npm")
        let disk = Disk(["/opt/homebrew/bin/node"])
        let outcome = await installer(runner: runner, disk: disk).install()
        guard case let .failed(detail) = outcome else { return XCTFail("expected failure") }
        XCTAssertTrue(detail.hasPrefix("npm ci:"))
    }

    func test_progressMessagesArePlainLanguage_neverRawToolOutput() async {
        let runner = succeedingRunner()
        runner.script(
            .stdout("==> Pouring python@3.15--3.15.0.arm64_golden_gate.bottle.tar.gz"),
            forPathEndingIn: "npm"
        )
        let disk = Disk(["/opt/homebrew/bin/node", mainJS])
        let seen = LockedBox<[String]>([])
        _ = await installer(runner: runner, disk: disk).install { text in seen.mutate { $0.append(text) } }
        let messages = seen.read { $0 }
        XCTAssertFalse(messages.isEmpty)
        for message in messages {
            XCTAssertFalse(message.contains("=="), message)
            XCTAssertFalse(message.contains("Pouring"), message)
        }
    }
}
