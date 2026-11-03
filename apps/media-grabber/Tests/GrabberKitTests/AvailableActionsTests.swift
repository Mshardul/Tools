@testable import GrabberKit
import TestSupport
import XCTest

final class AvailableActionsTests: XCTestCase {
    private typealias Fix = EngineFixture

    private func actions(_ state: JobState) -> Set<RowAction> {
        DownloadEngine.availableActions(for: state)
    }

    func test_queued_immediatelySchedulable_noForceStart() {
        XCTAssertEqual(
            DownloadEngine.availableActions(for: .queued, isImmediatelySchedulable: true),
            [.cancel, .remove, .openInBrowser]
        )
    }

    func test_queued_notImmediatelySchedulable_offersForceStart() {
        XCTAssertEqual(
            DownloadEngine.availableActions(for: .queued, isImmediatelySchedulable: false),
            [.cancel, .forceStart, .remove, .openInBrowser]
        )
    }

    func test_probing_hasNoPauseOrShowLog() {
        XCTAssertEqual(actions(.probing), [.cancel, .remove, .openInBrowser])
    }

    func test_running_hasShowLog() {
        XCTAssertEqual(actions(.running), [.pause, .cancel, .remove, .openInBrowser, .showLog])
    }

    func test_paused_hasShowLog() {
        XCTAssertEqual(actions(.paused), [.resume, .cancel, .remove, .openInBrowser, .showLog])
    }

    func test_completed_hasShowLog() {
        XCTAssertEqual(actions(.completed), [.reveal, .remove, .openInBrowser, .showLog])
    }

    func test_cancelled_offersRestart() {
        XCTAssertEqual(actions(.cancelled), [.retry, .remove, .openInBrowser, .showLog])
    }

    func test_failedActionsFromPresentation_rateLimited() {
        let set = actions(.failed(.rateLimited()))
        XCTAssertTrue(set.isSuperset(of: [.retry, .showLog, .remove, .openInBrowser]))
        XCTAssertFalse(set.contains(.pause))
        XCTAssertFalse(set.contains(.forceStart))
    }

    func test_failedActions_geoBlockedHasNoRetry() {
        let set = actions(.failed(.geoBlocked))
        XCTAssertFalse(set.contains(.retry))
        XCTAssertTrue(set.isSuperset(of: [.showLog, .remove, .openInBrowser]))
    }

    func test_showLogInEveryRunState_notBeforeARun() {
        for state: JobState in [.running, .paused, .completed, .cancelled] {
            XCTAssertTrue(actions(state).contains(.showLog), "\(state)")
        }
        for state: JobState in [.queued, .probing] {
            XCTAssertFalse(actions(state).contains(.showLog), "\(state)")
        }
    }

    func test_waitingForNetwork_and_cooldown() {
        XCTAssertEqual(actions(.waitingForNetwork), [.cancel, .remove, .openInBrowser, .showLog])
        XCTAssertEqual(
            actions(.cooldown(until: Date(timeIntervalSince1970: 0))),
            [.forceStart, .cancel, .remove, .openInBrowser, .showLog]
        )
    }

    func testCooldownOffersForceStart() {
        let set = DownloadEngine.availableActions(for: .cooldown(until: .now))
        XCTAssertTrue(set.contains(.forceStart))
        XCTAssertTrue(set.isSuperset(of: [.cancel, .remove, .openInBrowser, .showLog]))
        XCTAssertFalse(set.contains(.pause))
    }

    func testWaitingForNetworkHasNoForceStart() {
        let set = DownloadEngine.availableActions(for: .waitingForNetwork)
        XCTAssertFalse(set.contains(.forceStart))
        XCTAssertEqual(set, [.cancel, .remove, .openInBrowser, .showLog])
    }

    func test_retryWithCookies_onlyWhenSignInIsSuggested() {
        let failures: [JobState] = [
            .failed(.cookieReadFailed), .failed(.private), .failed(.ageRestricted), .failed(.botCheck),
            .failed(.formatsMissing), .failed(.rateLimited()), .failed(.geoBlocked)
        ]
        for state in failures {
            XCTAssertFalse(
                DownloadEngine.availableActions(for: state, signInAdvice: .none).contains(.retryWithCookies),
                "\(state)"
            )
            XCTAssertFalse(
                DownloadEngine.availableActions(for: state, signInAdvice: .checkBrowser).contains(.retryWithCookies),
                "\(state)"
            )
            XCTAssertTrue(
                DownloadEngine.availableActions(for: state, signInAdvice: .suggest).contains(.retryWithCookies),
                "\(state)"
            )
        }
    }

    func test_nonFailedStates_neverOfferRetryWithCookies() {
        let states: [JobState] = [
            .queued, .probing, .running, .paused, .completed, .cancelled,
            .waitingForNetwork, .cooldown(until: .init())
        ]
        for state in states {
            XCTAssertFalse(
                DownloadEngine.availableActions(for: state, signInAdvice: .suggest).contains(.retryWithCookies),
                "\(state)"
            )
        }
    }

    func test_failedCookieReadFailed_offersPlainRetry() {
        let set = actions(.failed(.cookieReadFailed))
        XCTAssertTrue(set.isSuperset(of: [.retry, .showLog, .remove, .openInBrowser]))
        XCTAssertFalse(set.contains(.retryWithCookies))
    }

    func test_failedPrivate_noRetry_withSuggestOffersSignInRestart() {
        let set = DownloadEngine.availableActions(for: .failed(.private), signInAdvice: .suggest)
        XCTAssertTrue(set.contains(.retryWithCookies))
        XCTAssertFalse(set.contains(.retry))
    }

    func test_snapshot_ageRestricted_unconfiguredSuggests_configuredChecksBrowser() async throws {
        for (source, expected) in [(CookieSource.none, SignInAdvice.suggest), (.chrome, .checkBrowser)] {
            let prefs = try Preferences(defaults: XCTUnwrap(UserDefaults(suiteName: UUID().uuidString)))
            prefs.cookiesFromBrowser = source
            let runner = FakeProcessRunner()
            runner.script(
                FakeProcessRunner.Script(lines: [.stderr("ERROR: Sign in to confirm your age")], exitCode: 1),
                forPathEndingIn: "yt-dlp"
            )
            let probe = FakeMetadataProbe()
            probe.result(FakeMetadataProbe.success(title: "Clip"))
            let engine = Fix.engine(runner: runner, probe: probe, preferences: prefs)
            let collector = EventCollector(engine.events)
            let id = await submitJob(engine, Fix.request())
            await expectState(collector, id) { $0 == .failed(.ageRestricted) }
            let job = await engine.currentSnapshot().jobs.first { $0.id == id }
            XCTAssertEqual(job?.signInAdvice, expected)
            XCTAssertEqual(job?.availableActions.contains(.retryWithCookies), expected == .suggest)
        }
    }

    @MainActor
    func test_snapshotAdvice_botCheck_onlyOnYouTube() {
        let youtube = DownloadJob(request: Fix.request(url: "https://www.youtube.com/watch?v=x"))
        let vimeo = DownloadJob(request: Fix.request(url: "https://vimeo.com/1"))
        for job in [youtube, vimeo] {
            job.state = .failed(.botCheck)
        }
        XCTAssertEqual(DownloadEngine.signInAdvice(for: youtube, cookiesConfigured: false), .suggest)
        XCTAssertEqual(DownloadEngine.signInAdvice(for: vimeo, cookiesConfigured: false), SignInAdvice.none)
        XCTAssertEqual(DownloadEngine.signInAdvice(for: vimeo, cookiesConfigured: true), SignInAdvice.none)
    }

    func test_transitionUpdatesTheSet() async {
        let runner = FakeProcessRunner()
        runner.perLineDelay = .milliseconds(20)
        runner.script(
            Fix.completingScript([Fix.progressLine(" 50.0%"), Fix.progressLine("100.0%")]),
            forPathEndingIn: "yt-dlp"
        )
        let probe = FakeMetadataProbe()
        probe.result(FakeMetadataProbe.success(title: "Clip"))
        let engine = Fix.engine(runner: runner, probe: probe)
        let collector = EventCollector(engine.events)

        let id = await submitJob(engine, Fix.request())
        await expectState(collector, id) { $0 == .completed }

        for snapshot in collector.snapshots {
            guard let job = snapshot.jobs.first(where: { $0.id == id }) else { continue }
            XCTAssertEqual(
                job.availableActions,
                DownloadEngine.availableActions(for: job.state, isImmediatelySchedulable: true),
                "\(job.state)"
            )
        }
    }
}
