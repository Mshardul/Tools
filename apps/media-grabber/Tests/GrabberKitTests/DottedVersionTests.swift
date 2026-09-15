@testable import GrabberKit
import XCTest

final class DottedVersionTests: XCTestCase {
    func testParsesDottedIntegerComponents() {
        XCTAssertNotNil(DottedVersion(parsing: "2026.07.10"))
    }

    func testAcceptsAVPrefix() {
        XCTAssertNotNil(DottedVersion(parsing: "v2026.07.10"))
    }

    func testAcceptsAPatchSuffix() {
        XCTAssertNotNil(DottedVersion(parsing: "2026.07.10.1"))
    }

    func testRejectsNonNumericComponents() {
        XCTAssertNil(DottedVersion(parsing: "nightly-build"))
    }

    func testRejectsEmptyString() {
        XCTAssertNil(DottedVersion(parsing: ""))
    }

    func testComparesChronologically() throws {
        let older = try XCTUnwrap(DottedVersion(parsing: "2026.05.02"))
        let newer = try XCTUnwrap(DottedVersion(parsing: "2026.07.10"))
        XCTAssertLessThan(older, newer)
        XCTAssertFalse(newer < older)
    }

    func testComparesPatchSuffixAsExtraComponent() throws {
        let base = try XCTUnwrap(DottedVersion(parsing: "2026.07.10"))
        let patched = try XCTUnwrap(DottedVersion(parsing: "2026.07.10.1"))
        XCTAssertLessThan(base, patched)
    }

    func testEqualVersionsAreNotLessThanEachOther() throws {
        let first = try XCTUnwrap(DottedVersion(parsing: "2026.07.10"))
        let second = try XCTUnwrap(DottedVersion(parsing: "2026.07.10"))
        XCTAssertFalse(first < second)
        XCTAssertEqual(first, second)
    }

    func testDriftVerdictInstalledOlderThanMinimumIsDrift() {
        let verdict = DottedVersion.driftVerdict(installedRaw: "2026.05.02", minimumRaw: "2026.07.10")
        XCTAssertEqual(verdict, .drift(installed: "2026.05.02", minimum: "2026.07.10"))
    }

    func testDriftVerdictInstalledEqualToMinimumIsCurrent() {
        let verdict = DottedVersion.driftVerdict(installedRaw: "2026.07.10", minimumRaw: "2026.07.10")
        XCTAssertEqual(verdict, .current)
    }

    func testDriftVerdictInstalledNewerThanMinimumIsCurrent() {
        let verdict = DottedVersion.driftVerdict(installedRaw: "2026.09.01", minimumRaw: "2026.07.10")
        XCTAssertEqual(verdict, .current)
    }

    func testDriftVerdictUnparseableInstalledIsUnknownNotStale() {
        let verdict = DottedVersion.driftVerdict(installedRaw: "nightly-build", minimumRaw: "2026.07.10")
        XCTAssertEqual(verdict, .unknown(raw: "nightly-build"))
    }
}
