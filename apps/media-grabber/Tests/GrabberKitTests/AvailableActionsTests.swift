@testable import GrabberKit
import TestSupport
import XCTest

final class AvailableActionsTests: XCTestCase {
    private typealias Fix = EngineFixture

    private func actions(_ state: JobState) -> Set<RowAction> {
        DownloadEngine.availableActions(for: state)
    }

    func test_queued() {
        XCTAssertEqual(actions(.queued), [.pause, .cancel, .forceStart, .remove, .openInBrowser])
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

    func test_cancelled_hasShowLog() {
        XCTAssertEqual(actions(.cancelled), [.remove, .openInBrowser, .showLog])
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
        XCTAssertEqual(actions(.waitingForNetwork), [.cancel, .remove, .openInBrowser])
        XCTAssertEqual(
            actions(.cooldown(until: Date(timeIntervalSince1970: 0))),
            [.cancel, .remove, .openInBrowser]
        )
    }

    func test_retryWithCookies_onlyForCookieRelevantFailures() {
        let without: [JobState] = [
            .queued, .probing, .running, .paused, .completed, .cancelled,
            .failed(.networkDown), .failed(.geoBlocked), .failed(.unavailable),
            .waitingForNetwork, .cooldown(until: .init())
        ]
        for state in without {
            XCTAssertFalse(actions(state).contains(.retryWithCookies), "\(state)")
        }
        for state: JobState in [
            .failed(.cookieReadFailed),
            .failed(.private),
            .failed(.ageRestricted)
        ] {
            XCTAssertTrue(actions(state).contains(.retryWithCookies), "\(state)")
        }
    }

    func test_failedCookieReadFailed_includesRetryWithCookies() {
        let set = actions(.failed(.cookieReadFailed))
        XCTAssertTrue(set.isSuperset(of: [
            .retry,
            .retryWithCookies,
            .showLog,
            .remove,
            .openInBrowser
        ]))
    }

    func test_failedPrivate_hasRetryWithCookies_notRetry() {
        let set = actions(.failed(.private))
        XCTAssertTrue(set.contains(.retryWithCookies))
        XCTAssertFalse(set.contains(.retry))
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
                DownloadEngine.availableActions(for: job.state),
                "\(job.state)"
            )
        }
    }
}
