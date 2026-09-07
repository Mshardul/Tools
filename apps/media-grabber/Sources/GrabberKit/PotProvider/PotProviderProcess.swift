import Foundation

public actor PotProviderProcess: PotProviding {
    private let installer: PotPluginInstaller
    private let runner: ProcessRunning
    private let pinger: any ShieldPinging
    private let tuning: EngineTuning
    private let log: LogWriter?
    private let portChecker: any LoopbackPortChecking

    private var statusValue: ShieldStatus = .missing
    private var childTask: Task<Void, Never>?
    private var generation = 0

    public init(
        installer: PotPluginInstaller,
        runner: ProcessRunning,
        pinger: any ShieldPinging,
        tuning: EngineTuning,
        log: LogWriter?,
        portChecker: any LoopbackPortChecking = AlwaysFreePortChecker()
    ) {
        self.installer = installer
        self.runner = runner
        self.pinger = pinger
        self.tuning = tuning
        self.log = log
        self.portChecker = portChecker
    }

    public var status: ShieldStatus {
        statusValue
    }

    public var baseURL: URL? {
        guard case let .running(port) = statusValue else {
            return nil
        }
        return URL(string: "http://127.0.0.1:\(port)")
    }

    public var pluginDirs: [URL] {
        installer.pluginDirs()
    }

    public func ensure() async {
        if await isHealthyRunning() {
            return
        }
        await startChild()
    }

    public func restart() async {
        await stop()
        await logEvent(.shieldRestarted(reason: "user"))
        await ensure()
    }

    public func stop() async {
        abandonChild()
        if case .running = statusValue {
            statusValue = .down
        }
    }

    private func isHealthyRunning() async -> Bool {
        guard case let .running(port) = statusValue, let url = pingURL(port: port) else {
            return false
        }
        return await pinger.ping(url, timeout: TimeInterval(tuning.potHealthTimeoutSeconds))
    }

    private func startChild() async {
        abandonChild()
        guard let port = firstFreePort() else {
            statusValue = .down
            return
        }
        guard let launch = installer.resolveServerLaunch(port: port, host: "127.0.0.1") else {
            statusValue = .missing
            await logEvent(.shieldMissing)
            return
        }
        watch(runner.run(launch))
        await applyHealth(port: port)
    }

    private func watch(_ execution: ProcessExecution) {
        generation += 1
        let token = generation
        childTask = Task { [weak self] in
            let result = await execution.result()
            await self?.childExited(result, token: token)
        }
    }

    private func applyHealth(port: Int) async {
        guard let url = pingURL(port: port) else {
            statusValue = .down
            return
        }
        let ok = await pinger.ping(url, timeout: TimeInterval(tuning.potHealthTimeoutSeconds))
        if ok {
            statusValue = .running(port: port)
            await logEvent(.shieldStarted(port: port))
        } else {
            abandonChild()
            statusValue = .down
        }
    }

    private func childExited(_ result: ProcessResult, token: Int) async {
        guard token == generation, !result.wasCancelled else {
            return
        }
        await logEvent(.shieldExited(code: result.exitCode))
        statusValue = .down
        let delay = min(max(tuning.potRestartBackoffSeconds, 0), 30)
        try? await Task.sleep(for: .seconds(delay))
        guard token == generation else {
            return
        }
        await ensure()
    }

    private func abandonChild() {
        generation += 1
        childTask?.cancel()
        childTask = nil
    }

    private func firstFreePort() -> Int? {
        var port = 4416
        while port <= 4426 {
            if portChecker.isFree(port) {
                return port
            }
            port += 1
        }
        return nil
    }

    private func pingURL(port: Int) -> URL? {
        URL(string: "http://127.0.0.1:\(port)/ping")
    }

    private func logEvent(_ event: LogEvent) async {
        await log?.log(event)
    }
}
