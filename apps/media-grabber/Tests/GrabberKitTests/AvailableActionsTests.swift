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

    func test_probing_hasNoPause() {
        XCTAssertEqual(actions(.probing), [.cancel, .remove, .openInBrowser])
    }

    func test_running() {
        XCTAssertEqual(actions(.running), [.pause, .cancel, .remove, .openInBrowser])
    }

    func test_paused() {
        XCTAssertEqual(actions(.paused), [.resume, .cancel, .remove, .openInBrowser])
    }

    func test_completed() {
        XCTAssertEqual(actions(.completed), [.reveal, .remove, .openInBrowser])
    }

    func test_cancelled_and_failed() {
        XCTAssertEqual(actions(.cancelled), [.remove, .openInBrowser])
        XCTAssertEqual(actions(.failed(.networkDown)), [.remove, .openInBrowser])
    }

    func test_waitingForNetwork_and_cooldown() {
        XCTAssertEqual(actions(.waitingForNetwork), [.cancel, .remove, .openInBrowser])
        XCTAssertEqual(
            actions(.cooldown(until: Date(timeIntervalSince1970: 0))),
            [.cancel, .remove, .openInBrowser]
        )
    }

    func test_noGatedActionsEverIncluded() {
        let states: [JobState] = [
            .queued, .probing, .running, .paused, .completed, .cancelled,
            .failed(.networkDown), .waitingForNetwork, .cooldown(until: .init())
        ]
        for state in states {
            let set = actions(state)
            XCTAssertTrue(set.isDisjoint(with: [.retry, .retryWithCookies, .showLog]), "\(state)")
        }
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
