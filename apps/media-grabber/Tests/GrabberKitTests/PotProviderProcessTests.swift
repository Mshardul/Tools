@testable import GrabberKit
import TestSupport
import XCTest

final class PotProviderProcessTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/tmp/mg-pot-proc-home")
    private let bin = URL(fileURLWithPath: "/tmp/mg-pot-proc-bin")

    private func bgutilInstaller() -> PotPluginInstaller {
        let bgutil = bin.appendingPathComponent("bgutil-ytdlp-pot-provider")
        return PotPluginInstaller(
            home: home,
            searchPaths: [bin],
            isExecutable: { $0.path == bgutil.path },
            fileExists: { $0.path == bgutil.path },
            pluginStore: FakePluginStore()
        )
    }

    private func emptyInstaller() -> PotPluginInstaller {
        PotPluginInstaller(
            home: home,
            searchPaths: [bin],
            isExecutable: { _ in false },
            fileExists: { _ in false },
            pluginStore: FakePluginStore()
        )
    }

    func testEnsureMissingWhenInstallerFindsNothing() async {
        let runner = FakeProcessRunner()
        let provider = PotProviderProcess(
            installer: emptyInstaller(),
            runner: runner,
            pinger: FakePinger(false),
            tuning: .default,
            log: nil
        )
        await provider.ensure()
        let status = await provider.status
        XCTAssertEqual(status, .missing)
        XCTAssertTrue(runner.launches.isEmpty)
    }

    func testEnsureRunningWhenPingSucceeds() async {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .seconds(60)
        let provider = PotProviderProcess(
            installer: bgutilInstaller(),
            runner: runner,
            pinger: FakePinger(true),
            tuning: .default,
            log: nil
        )
        await provider.ensure()
        let status = await provider.status
        XCTAssertEqual(status, .running(port: 4416))
        XCTAssertEqual(runner.launches.count, 1)
        await provider.stop()
    }

    private var noStartupWait: EngineTuning {
        var tuning = EngineTuning.default
        tuning.potStartupWaitSeconds = 0
        return tuning
    }

    func testEnsureDownWhenPingFails() async {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .seconds(60)
        let provider = PotProviderProcess(
            installer: bgutilInstaller(),
            runner: runner,
            pinger: FakePinger(false),
            tuning: noStartupWait,
            log: nil
        )
        await provider.ensure()
        let status = await provider.status
        XCTAssertEqual(status, .down)
        await provider.stop()
    }

    func testRestartIncrementsLaunches() async {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .seconds(60)
        let provider = PotProviderProcess(
            installer: bgutilInstaller(),
            runner: runner,
            pinger: FakePinger(true),
            tuning: .default,
            log: nil
        )
        await provider.ensure()
        await provider.restart()
        XCTAssertEqual(runner.launches.count, 2)
        await provider.stop()
    }

    func testSlowStartingServer_isWaitedForAndEndsUpRunning() async {
        let runner = FakeProcessRunner()
        runner.perRunDelay = .seconds(60)
        var tuning = EngineTuning.default
        tuning.potStartupWaitSeconds = 10
        let provider = PotProviderProcess(
            installer: bgutilInstaller(),
            runner: runner,
            pinger: FlakyPinger(failuresBeforeSuccess: 2),
            tuning: tuning,
            log: nil
        )
        await provider.ensure()
        let status = await provider.status
        guard case .running = status else { return XCTFail("expected running, got \(status)") }
        await provider.stop()
    }
}

private final class FlakyPinger: ShieldPinging, @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int

    init(failuresBeforeSuccess: Int) {
        remaining = failuresBeforeSuccess
    }

    func ping(_: URL, timeout _: TimeInterval) async -> Bool {
        lock.withLock {
            guard remaining > 0 else { return true }
            remaining -= 1
            return false
        }
    }
}
