@testable import GrabberKit
import TestSupport
import XCTest

final class RateLimiterWiringTests: XCTestCase {
    func testEngineSeedsRateLimiterFromTheCapProperty() async {
        let engine = EngineFixture.engine(runner: FakeProcessRunner(), probe: FakeMetadataProbe(), cap: 5)
        let adaptive = await engine.adaptiveCapForTest()
        let effective = await engine.effectiveCapForTest()
        XCTAssertEqual(adaptive, EngineTuning.default.adaptiveConcurrencyStart)
        XCTAssertEqual(effective, EngineTuning.default.adaptiveConcurrencyStart)
    }

    func testEffectiveCapRespectsTestCapBelowAdaptive() async {
        let engine = EngineFixture.engine(runner: FakeProcessRunner(), probe: FakeMetadataProbe(), cap: 1)
        let effective = await engine.effectiveCapForTest()
        XCTAssertEqual(effective, 1)
    }

    func testSetCapReclampsRateLimiter() async {
        let engine = EngineFixture.engine(runner: FakeProcessRunner(), probe: FakeMetadataProbe(), cap: 6)
        await engine.setCap(1)
        let effective = await engine.effectiveCapForTest()
        XCTAssertEqual(effective, 1)
    }

    func testEngineTracksOnlineFromMonitor() async {
        let net = FakeNetworkMonitor(startOnline: true)
        let engine = EngineFixture.engine(
            runner: FakeProcessRunner(), probe: FakeMetadataProbe(), networkMonitor: net
        )
        net.goOffline()
        try? await Task.sleep(for: .milliseconds(50))
        let online = await engine.isOnlineForTest()
        XCTAssertFalse(online)
    }
}
