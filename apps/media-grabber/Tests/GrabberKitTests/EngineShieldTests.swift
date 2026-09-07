@testable import GrabberKit
import TestSupport
import XCTest

final class EngineShieldTests: XCTestCase {
    private typealias Fix = EngineFixture

    private func idleProbe() -> FakeMetadataProbe {
        FakeMetadataProbe()
    }

    func testEnsureShieldCopiesRunningStatus() async {
        let pot = FakePotProvider(status: .running(port: 4416))
        let engine = Fix.engine(
            runner: FakeProcessRunner(),
            probe: idleProbe(),
            potProvider: pot
        )
        await engine.ensureShield()
        let snapshot = await engine.currentSnapshot()
        XCTAssertEqual(snapshot.shieldStatus, .running(port: 4416))
        XCTAssertNil(snapshot.queueHalt)
    }

    func testMissingPotProviderDoesNotHalt() async {
        let engine = Fix.engine(runner: FakeProcessRunner(), probe: idleProbe())
        await engine.ensureShield()
        let snapshot = await engine.currentSnapshot()
        XCTAssertEqual(snapshot.shieldStatus, .missing)
        XCTAssertNil(snapshot.queueHalt)
    }
}
