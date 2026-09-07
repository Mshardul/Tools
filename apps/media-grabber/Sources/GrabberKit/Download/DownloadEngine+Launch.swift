import Foundation

extension DownloadEngine {
    func launchDownload(id: UUID) {
        childTasks[id] = Task { [weak self] in
            await self?.performDownload(id: id)
        }
    }

    func launchProbe(id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }) else {
            return
        }
        let url = job.request.url
        let forceCookies = job.forceCookies
        let probe = dependencies.probe
        probeTask = Task { [weak self] in
            guard let self else {
                return
            }
            let context = await makeContext(url: url, attempt: 0, forceCookies: forceCookies)
            let result = await probe.probe(url, context: context)
            await recordProbeResult(id, result)
        }
    }

    func performDownload(id: UUID) async {
        guard let prepared = await prepareDownload(id: id) else {
            return
        }
        let execution = prepared.runner.run(prepared.launch)
        try? prepared.jobLog.writeHeader()
        async let processResult = execution.result()
        let outcome = await drainDownload(
            id: id, lines: execution.lines, jobLog: prepared.jobLog
        )
        let result = await processResult
        prepared.jobLog.close()
        let integrity = await runIntegrityCheck(
            id: id, result: result, runner: prepared.runner,
            ffprobeURL: prepared.ffprobeURL,
            ffprobeIsExecutable: prepared.ffprobeIsExecutable
        )
        await recordExit(
            id,
            result,
            integrity: integrity,
            lastError: outcome.lastError,
            launchFailed: outcome.launchFailed && result.exitCode == 127,
            cookiesRequested: prepared.cookieArgument != nil,
            extractedZeroCookies: outcome.extractedZeroCookies,
            sawAudioOnly: outcome.sawAudioOnly
        )
    }

    private struct PreparedDownload {
        var runner: ProcessRunning
        var launch: ProcessLaunch
        var jobLog: JobLog
        var cookieArgument: String?
        var ffprobeURL: URL?
        var ffprobeIsExecutable: @Sendable (URL) -> Bool
    }

    private func prepareDownload(id: UUID) async -> PreparedDownload? {
        guard let job = jobs.first(where: { $0.id == id }) else {
            return nil
        }
        let context = await makeContext(
            url: job.request.url,
            attempt: job.attempt,
            forceCookies: job.forceCookies
        )
        job.playerClientUsed = context.playerClient
        let cookieArgument = resolveCookieArgument(for: job)
        let launch = ProcessLaunch(
            executableURL: dependencies.ytDlpURL,
            arguments: downloadArguments(for: job, cookieArgument: cookieArgument, context: context)
        )
        let jobLog = JobLog(
            id: id,
            request: job.request,
            ytDlpVersion: dependencies.ytDlpVersion,
            playerClient: job.playerClientUsed,
            dir: dependencies.jobLogDir
        )
        return PreparedDownload(
            runner: dependencies.runner,
            launch: launch,
            jobLog: jobLog,
            cookieArgument: cookieArgument,
            ffprobeURL: dependencies.ffprobeURL,
            ffprobeIsExecutable: dependencies.ffprobeIsExecutable
        )
    }

    func downloadArguments(
        for job: DownloadJob,
        cookieArgument: String?,
        context: ExtractorContext
    ) -> [String] {
        let options = GlobalDownloadOptions(
            proxyURL: preferences.proxyURL,
            forceIPv4: preferences.forceIPv4,
            speedLimitKBps: preferences.speedLimitKBps
        )
        return YtDlpArguments.build(
            for: job.request,
            options: options,
            tuning: dependencies.tuning.ytDlp,
            cookieArgument: cookieArgument,
            context: context,
            concurrentFragments: fragmentCount(for: job.request.url)
        )
    }

    func resolveCookieArgument(for job: DownloadJob) -> String? {
        let home = dependencies.cookieResolverHome
            ?? FileManager.default.homeDirectoryForCurrentUser
        return CookieResolver(fileManager: dependencies.fileManager, home: home)
            .resolve(source: preferences.cookiesFromBrowser, jobOverride: job.forceCookies)
            .argument
    }

    func runIntegrityCheck(
        id: UUID,
        result: ProcessResult,
        runner: ProcessRunning,
        ffprobeURL: URL?,
        ffprobeIsExecutable: @escaping @Sendable (URL) -> Bool
    ) async -> IntegrityResult? {
        guard result.exitCode == 0, !result.wasCancelled else {
            return nil
        }
        guard let job = jobs.first(where: { $0.id == id }) else {
            return nil
        }
        guard let file = finalizedOutputFiles(for: job).first else {
            return nil
        }
        return await IntegrityCheck(
            runner: runner, ffprobeURL: ffprobeURL, isExecutable: ffprobeIsExecutable
        )
        .verify(file: file, expectedDurationSeconds: job.durationSeconds)
    }

    private struct DownloadDrainOutcome {
        var lastError: ErrorClass?
        var launchFailed = false
        var extractedZeroCookies = false
        var sawAudioOnly = false
    }

    private func drainDownload(
        id: UUID,
        lines: AsyncStream<ProcessLine>,
        jobLog: JobLog
    ) async -> DownloadDrainOutcome {
        var outcome = DownloadDrainOutcome()
        for await line in lines {
            jobLog.append(line)
            let text: String
            switch line {
            case let .stdout(stdout):
                text = stdout
                if case let .progress(progress) = ProgressParser.parseStdout(stdout) {
                    recordProgress(id, progress)
                }
            case let .stderr(stderr):
                text = stderr
                if stderr.hasPrefix("launch failed:") {
                    outcome.launchFailed = true
                }
                if let classified = ProgressParser.classifyStderr(stderr) {
                    outcome.lastError = classified
                }
            }
            if let path = ProgressParser.captureOutputPath(from: text) {
                recordOutputPath(id, path)
            }
            if text.contains("Extracted 0 cookies") {
                outcome.extractedZeroCookies = true
            }
            if text.localizedCaseInsensitiveContains("audio only") {
                outcome.sawAudioOnly = true
            }
        }
        return outcome
    }
}
