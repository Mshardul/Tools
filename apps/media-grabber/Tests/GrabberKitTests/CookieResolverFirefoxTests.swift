@testable import GrabberKit
import TestSupport
import XCTest

final class CookieResolverFirefoxTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/tester")

    private var iniPath: String {
        home.appendingPathComponent("Library/Application Support/Firefox/profiles.ini").path
    }

    private var profilesDir: String {
        home.appendingPathComponent("Library/Application Support/Firefox/Profiles").path
    }

    private func resolver(ini: String?) -> CookieResolver {
        var fm = FakeFileManaging()
        if let ini {
            fm.files = [iniPath]
            fm.readable = [iniPath]
            fm.contents = [iniPath: ini]
        }
        return CookieResolver(fileManager: fm, home: home)
    }

    func test_absentFile_returnsEmpty() {
        XCTAssertEqual(resolver(ini: nil).firefoxProfiles(), [])
    }

    func test_twoProfiles_relativePaths_defaultMarked() {
        let ini = """
        [Install4F96D1932A9F858E]
        Default=Profiles/abc.default-release

        [Profile1]
        Name=default
        IsRelative=1
        Path=Profiles/xyz.default

        [Profile0]
        Name=default-release
        IsRelative=1
        Path=Profiles/abc.default-release
        """
        let got = resolver(ini: ini).firefoxProfiles()
        XCTAssertEqual(Set(got.map(\.name)), ["default", "default-release"])
        let def = got.first { $0.isDefault }
        XCTAssertEqual(def?.name, "default-release")
        XCTAssertEqual(def?.path, "\(profilesDir)/abc.default-release")
    }

    func test_absolutePath_usedVerbatim() {
        let ini = """
        [Profile0]
        Name=custom
        IsRelative=0
        Path=/opt/ff/custom
        Default=1
        """
        let got = resolver(ini: ini).firefoxProfiles()
        XCTAssertEqual(got.count, 1)
        XCTAssertEqual(got[0].path, "/opt/ff/custom")
        XCTAssertTrue(got[0].isDefault)
    }

    func test_malformedSectionSkipped_notThrown() {
        let ini = """
        [Profile0]
        garbage line without equals
        Name=ok
        Path=Profiles/ok

        [Profile1]
        Name=
        Path=
        """
        let got = resolver(ini: ini).firefoxProfiles()
        XCTAssertEqual(got.map(\.name), ["ok"])
    }

    func test_zeroProfiles_returnsEmpty() {
        XCTAssertEqual(resolver(ini: "[General]\nStartWithLastProfile=1").firefoxProfiles(), [])
    }
}
