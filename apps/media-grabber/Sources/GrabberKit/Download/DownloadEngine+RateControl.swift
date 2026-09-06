import Foundation

extension DownloadEngine {
    // MARK: - Concurrency

    var cap: Int {
        if let capOverrideForTests {
            return capOverrideForTests
        }
        return dependencies.debugFlags.concurrencyCapOverride ?? preferences.maxConcurrentDownloads
    }

    // The scheduler and forceStart eviction both use this — never adaptiveCap or cap alone.
    var effectiveCap: Int {
        min(rateLimiter.adaptiveCap, cap)
    }

    func blockedHostIDs(now: Date, queuedOnly: Bool) -> Set<UUID> {
        Set(jobs.filter { job in
            let stateMatches = queuedOnly ? job.state == .queued : jobNeedsProbe(job)
            guard stateMatches else { return false }
            return rateLimiter.blocked(host: RateHost(urlString: job.request.url), now: now)
        }.map(\.id))
    }

    private func jobNeedsProbe(_ job: DownloadJob) -> Bool {
        job.state == .queued
            && (job.title == nil || job.extractor == nil || job.durationSeconds == nil)
    }

    // A host under any rate pressure gets the throttled fragment count so a retry is gentler.
    func fragmentCount(for url: String) -> Int {
        rateLimiter.state(for: RateHost(urlString: url)) == .normal
            ? dependencies.tuning.concurrentFragmentsNormal
            : dependencies.tuning.concurrentFragmentsThrottled
    }

    // Test seam: drive cap deterministically without a Preferences round-trip.
    func setCap(_ value: Int?) {
        capOverrideForTests = value
        rateLimiter.setPreferencesCap(cap)
        evaluateSchedule()
    }

    func adaptiveCapForTest() -> Int {
        rateLimiter.adaptiveCap
    }

    func effectiveCapForTest() -> Int {
        effectiveCap
    }

    // MARK: - Network

    func startNetworkMonitoring(_ monitor: any NetworkPathMonitoring) {
        guard networkTask == nil else { return }
        networkTask = Task { [weak self] in
            for await online in monitor.stream {
                await self?.applyNetworkChange(online)
            }
        }
    }

    func applyNetworkChange(_ online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        logEvent(.networkPathChanged(online: online))
        if online {
            resumeFromNetwork()
        } else {
            parkForNetworkLoss()
        }
        bump()
        emitSnapshot()
        evaluateSchedule()
    }

    private func resumeFromNetwork() {
        if queueHalt == .networkDown {
            queueHalt = nil
        }
        for job in jobs where job.state == .waitingForNetwork {
            job.state = .queued
            move(job, toTail: true)
        }
    }

    private func parkForNetworkLoss() {
        queueHalt = .networkDown
        for job in jobs where job.state == .running || job.state == .probing {
            if job.state == .probing {
                probeTask?.cancel()
                probeInFlight = false
            } else {
                childTasks[job.id]?.cancel()
            }
            job.state = .waitingForNetwork
            job.progress = nil
        }
    }

    func isOnlineForTest() -> Bool {
        isOnline
    }

    // MARK: - Circuit reset

    public func resetCircuit(_ host: RateHost) async {
        guard rateLimiter.circuitOpenHosts.contains(host) else { return }
        rateLimiter.resetCircuit(host: host)
        logEvent(.circuitReset(host: host.canonical, byUser: true))
        afterRateReset()
    }

    public func resetAllCircuits() async {
        let hosts = rateLimiter.circuitOpenHosts
        guard !hosts.isEmpty else { return }
        rateLimiter.resetAllCircuits()
        for host in hosts {
            logEvent(.circuitReset(host: host.canonical, byUser: true))
        }
        afterRateReset()
    }

    private func afterRateReset() {
        bump()
        emitSnapshot()
        evaluateSchedule()
    }
}
