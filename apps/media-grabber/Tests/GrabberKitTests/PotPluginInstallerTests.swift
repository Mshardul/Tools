@testable import GrabberKit
import TestSupport
import XCTest

final class PotPluginInstallerTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/tmp/mg-pot-home")
    private let bin = URL(fileURLWithPath: "/tmp/mg-pot-bin")

    private func installer(
        executable: Set<String> = [],
        existing: Set<String> = [],
        store: FakePluginStore = FakePluginStore()
    ) -> PotPluginInstaller {
        PotPluginInstaller(
            home: home,
            searchPaths: [bin],
            isExecutable: { executable.contains($0.path) },
            fileExists: { existing.contains($0.path) },
            pluginStore: store
        )
    }

    func testResolveNilWhenNothingFound() {
        let sut = installer()
        XCTAssertNil(sut.resolveServerLaunch(port: 4416))
        XCTAssertEqual(sut.pluginDirs(), [])
    }

    func testPrefersBgutilBinaryOnSearchPath() {
        let bgutil = bin.appendingPathComponent("bgutil-ytdlp-pot-provider")
        let sut = installer(executable: [bgutil.path], existing: [bgutil.path])
        let launch = sut.resolveServerLaunch(port: 4416)
        XCTAssertEqual(launch?.executableURL, bgutil)
        XCTAssertEqual(launch?.arguments, ["--host", "127.0.0.1", "--port", "4416"])
    }

    func testFallsBackToNodeAndAppSupportMainJS() {
        let node = bin.appendingPathComponent("node")
        let mainJS = home.appendingPathComponent(
            "Library/Application Support/MediaGrabber/bgutil-server/server/build/main.js"
        )
        let sut = installer(executable: [node.path], existing: [node.path, mainJS.path])
        let launch = sut.resolveServerLaunch(port: 4420)
        XCTAssertEqual(launch?.executableURL, node)
        XCTAssertEqual(
            launch?.arguments,
            [mainJS.path, "--host", "127.0.0.1", "--port", "4420"]
        )
    }

    func testFallsBackToPipxVenvMainJS() {
        let node = bin.appendingPathComponent("node")
        let lib = home.appendingPathComponent(
            ".local/share/pipx/venvs/bgutil-ytdlp-pot-provider/lib"
        )
        let python = lib.appendingPathComponent("python3.12")
        let pkg = python.appendingPathComponent("site-packages/bgutil_ytdlp_pot_provider")
        let mainJS = pkg.appendingPathComponent("server/build/main.js")
        let store = FakePluginStore()
        store.listings = [
            lib.path: [python],
            python.appendingPathComponent("site-packages").path: [pkg]
        ]
        let sut = installer(
            executable: [node.path],
            existing: [node.path, mainJS.path],
            store: store
        )
        let launch = sut.resolveServerLaunch(port: 4416)
        XCTAssertEqual(launch?.executableURL, node)
        XCTAssertEqual(launch?.arguments.first, mainJS.path)
    }

    func testPluginDirsCopiesYtDlpPluginsBesideMainJS() {
        let node = bin.appendingPathComponent("node")
        let mainJS = home.appendingPathComponent(
            "Library/Application Support/MediaGrabber/bgutil-server/server/build/main.js"
        )
        let plugins = home.appendingPathComponent(
            "Library/Application Support/MediaGrabber/bgutil-server/yt_dlp_plugins"
        )
        let store = FakePluginStore()
        store.files = [plugins.path]
        let sut = installer(
            executable: [node.path],
            existing: [node.path, mainJS.path, plugins.path],
            store: store
        )
        let dirs = sut.pluginDirs()
        let dest = home.appendingPathComponent(
            "Library/Application Support/MediaGrabber/yt-dlp-plugins"
        )
        XCTAssertEqual(dirs, [dest])
        XCTAssertEqual(store.copies.map(\.from), [plugins])
        XCTAssertEqual(store.copies.map(\.to.path), [dest.appendingPathComponent("yt_dlp_plugins").path])
    }
}
