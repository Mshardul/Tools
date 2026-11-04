@testable import GrabberKit
import TestSupport
import XCTest

final class PlayerClientCatalogTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("player-clients-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testCatalogRequestTimesOutQuickly() {
        XCTAssertEqual(PlayerClientCatalog.request().timeoutInterval, 5)
    }

    func testClientsFromAcceptsANonEmptyStringArray() {
        let data = Data("{\"playerClients\":[\"ios\",\"tv\"]}".utf8)
        XCTAssertEqual(PlayerClientCatalog.clients(from: data), ["ios", "tv"])
    }

    func testClientsFromRejectsInvalidPayloads() {
        let payloads = [
            "{}",
            "{\"playerClients\":[]}",
            "{\"playerClients\":[\"\"]}",
            "{\"playerClients\":[1]}",
            "nope",
            "{\"playerClients\":[\"tv\",\"ios;web\"]}",
            "{\"playerClients\":[\"TV\"]}"
        ]
        for payload in payloads {
            XCTAssertNil(PlayerClientCatalog.clients(from: Data(payload.utf8)))
        }
    }

    func testThrownFetchWithNoFileUsesTheBundledOrderAndFetchesAgain() async {
        let clock = DateBox(Date(timeIntervalSince1970: 1000))
        let store = PlayerClientCatalogStore(directory: directory, now: { clock.date })
        let calls = LockedBox(0)
        let first = await store.order {
            calls.mutate { $0 += 1 }
            throw CatalogTestError.offline
        }
        XCTAssertEqual(first, PlayerClientRotation.bundled)
        _ = await store.order {
            calls.mutate { $0 += 1 }
            throw CatalogTestError.offline
        }
        XCTAssertEqual(calls.read { $0 }, 1)
        clock.date = clock.date.addingTimeInterval(3601)
        _ = await store.order {
            calls.mutate { $0 += 1 }
            throw CatalogTestError.offline
        }
        XCTAssertEqual(calls.read { $0 }, 2)
    }

    func testFreshSavedOrderSkipsFetch() async {
        let clock = DateBox(Date(timeIntervalSince1970: 1000))
        let store = PlayerClientCatalogStore(directory: directory, now: { clock.date })
        let payload = Data("{\"playerClients\":[\"ios\",\"tv\"]}".utf8)
        let first = await store.order { payload }
        XCTAssertEqual(first, ["ios", "tv"])

        clock.date = clock.date.addingTimeInterval(3600)
        let calls = LockedBox(0)
        let second = await store.order {
            calls.mutate { $0 += 1 }
            return payload
        }
        XCTAssertEqual(calls.read { $0 }, 0)
        XCTAssertEqual(second, ["ios", "tv"])
    }

    func testStaleSavedOrderRefetchesAndAFailureKeepsTheSavedList() async {
        let clock = DateBox(Date(timeIntervalSince1970: 1000))
        let store = PlayerClientCatalogStore(directory: directory, now: { clock.date })
        let payload = Data("{\"playerClients\":[\"ios\",\"tv\"]}".utf8)
        _ = await store.order { payload }

        clock.date = clock.date.addingTimeInterval(86401)
        let calls = LockedBox(0)
        let kept = await store.order {
            calls.mutate { $0 += 1 }
            throw CatalogTestError.offline
        }
        XCTAssertEqual(calls.read { $0 }, 1)
        XCTAssertEqual(kept, ["ios", "tv"])
    }

    func testInvalidPayloadKeepsTheSavedList() async {
        let clock = DateBox(Date(timeIntervalSince1970: 1000))
        let store = PlayerClientCatalogStore(directory: directory, now: { clock.date })
        let payload = Data("{\"playerClients\":[\"ios\",\"tv\"]}".utf8)
        _ = await store.order { payload }

        clock.date = clock.date.addingTimeInterval(86401)
        let kept = await store.order { Data("nope".utf8) }
        XCTAssertEqual(kept, ["ios", "tv"])
    }
}

private final class DateBox: @unchecked Sendable {
    var date: Date
    init(_ date: Date) {
        self.date = date
    }
}

private enum CatalogTestError: Error {
    case offline
}
