import Foundation

extension DownloadEngine {
    // The deferred-start seam — backoff and host-cooldown both defer through here by Date.
    func deferStart(_ id: UUID, until notBefore: Date) {
        deferrals.removeAll { $0.id == id }
        deferrals.append((id: id, notBefore: notBefore))
        deferrals.sort { $0.notBefore < $1.notBefore }
        armDeferralTask()
    }

    func deferStartForTest(_ id: UUID, until notBefore: Date) {
        deferStart(id, until: notBefore)
    }

    func cancelDeferral(_ id: UUID) {
        deferrals.removeAll { $0.id == id }
        armDeferralTask()
    }

    func cancelDeferralForTest(_ id: UUID) {
        cancelDeferral(id)
    }

    func enterCooldownForTest(_ id: UUID, until: Date) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        job.state = .cooldown(until: until)
        job.cooldownUntil = until
        deferStart(id, until: until)
        bump()
        emitSnapshot()
    }

    func fireDueDeferralsForTest() {
        fireDueDeferrals()
    }

    private func armDeferralTask() {
        deferralTask?.cancel()
        guard let earliest = deferrals.first?.notBefore else {
            deferralTask = nil
            return
        }
        let clock = dependencies.clock
        deferralTask = Task { [weak self] in
            await clock.sleep(until: earliest)
            await self?.fireDueDeferrals()
        }
    }

    private func fireDueDeferrals() {
        let now = dependencies.clock.now
        let due = deferrals.filter { $0.notBefore <= now }
        deferrals.removeAll { $0.notBefore <= now }
        deferralTask = nil
        var flipped = false
        for entry in due {
            flipped = resumeIfCooldownElapsed(entry.id, now: now) || flipped
        }
        if !due.isEmpty {
            if flipped {
                bump()
                emitSnapshot()
            }
            evaluateSchedule()
        }
        armDeferralTask()
    }

    // Cancelling or failing the cooling row drops its timer. A queued sibling still needs a wake at the deadline.
    func ensureHostCooldownWake(for host: RateHost) {
        guard let deadline = rateLimiter.cooldownDeadline(for: host) else { return }
        let sameHost: (DownloadJob) -> Bool = { RateHost(urlString: $0.request.url) == host }
        let queued = jobs.contains { $0.state == .queued && sameHost($0) }
        guard queued else { return }
        let cooling = jobs.contains { isCooldownState($0.state) && sameHost($0) }
        guard !cooling else { return }
        deferStart(hostWakeID(for: host), until: deadline)
    }

    private func hostWakeID(for host: RateHost) -> UUID {
        if let existing = hostWakeIDs[host] {
            return existing
        }
        let made = UUID()
        hostWakeIDs[host] = made
        return made
    }

    private func resumeIfCooldownElapsed(_ id: UUID, now: Date) -> Bool {
        guard let job = jobs.first(where: { $0.id == id }) else { return false }
        guard case let .cooldown(until) = job.state, until <= now else { return false }
        job.state = .queued
        job.cooldownUntil = nil
        return true
    }
}
