@testable import GrabberKit
import TestSupport
import XCTest

final class VPNDetectingTests: XCTestCase {
    func testFakeDefaultsInactive() {
        XCTAssertFalse(FakeVPNDetector().isVPNActive)
    }

    func testFakeCanBeActive() {
        XCTAssertTrue(FakeVPNDetector(isVPNActive: true).isVPNActive)
    }

    func testTunnelWithARoutableAddressCarriesTraffic() {
        let interfaces = [
            InterfaceRecord(name: "en0", isUp: true, address: "192.168.1.23"),
            InterfaceRecord(name: "utun0", isUp: true, address: "fe80::1"),
            InterfaceRecord(name: "utun4", isUp: true, address: "10.8.0.6"),
            InterfaceRecord(name: "utun4", isUp: true, address: "fe80::abcd")
        ]
        XCTAssertTrue(InterfaceVPNDetector.carriesTraffic(interfaces))
    }

    func testBuiltInTunnelsWithOnlyLinkLocalAddressesAreNotAVPN() {
        let interfaces = [
            InterfaceRecord(name: "lo0", isUp: true, address: "127.0.0.1"),
            InterfaceRecord(name: "lo0", isUp: true, address: "::1"),
            InterfaceRecord(name: "en0", isUp: true, address: "192.168.1.23"),
            InterfaceRecord(name: "awdl0", isUp: true, address: "fe80::a1ff:fe11"),
            InterfaceRecord(name: "utun0", isUp: true, address: "fe80::1"),
            InterfaceRecord(name: "utun1", isUp: true, address: "fe80::2"),
            InterfaceRecord(name: "utun2", isUp: true, address: "fe80::3"),
            InterfaceRecord(name: "utun3", isUp: true, address: "fe80::4"),
            InterfaceRecord(name: "ipsec0", isUp: true, address: "fe80::5")
        ]
        XCTAssertFalse(InterfaceVPNDetector.carriesTraffic(interfaces))
    }

    func testDownTunnelDoesNotCount() {
        let interfaces = [
            InterfaceRecord(name: "utun4", isUp: false, address: "10.8.0.6")
        ]
        XCTAssertFalse(InterfaceVPNDetector.carriesTraffic(interfaces))
    }

    func testWireGuardULACarriesTraffic() {
        let interfaces = [
            InterfaceRecord(name: "wg0", isUp: true, address: "fd12:3456::2")
        ]
        XCTAssertTrue(InterfaceVPNDetector.carriesTraffic(interfaces))
    }
}
