@testable import GrabberKit
import XCTest

final class AudioLanguageSeedTests: XCTestCase {
    private let originalJA = AudioTrack(
        id: "ja|orig",
        languageCode: "ja",
        label: "Japanese (original)",
        isOriginal: true,
        isDefault: true
    )
    private let dubEN = AudioTrack(
        id: "en|dub",
        languageCode: "en",
        label: "English",
        isOriginal: false,
        isDefault: false
    )
    private let origEN = AudioTrack(
        id: "en|orig",
        languageCode: "en",
        label: "English (original)",
        isOriginal: true,
        isDefault: false
    )

    func test_lastOriginal_winsWhenPresent() {
        let picked = AudioLanguageSeed.pick(
            tracks: [originalJA, dubEN],
            last: .original,
            policy: .youtubeDefault
        )
        XCTAssertEqual(picked.id, originalJA.id)
    }

    func test_lastCode_prefersDubWhenBothExist() {
        let picked = AudioLanguageSeed.pick(
            tracks: [origEN, dubEN],
            last: .code("en"),
            policy: .original
        )
        XCTAssertEqual(picked.id, dubEN.id)
    }

    func test_policyOriginal_thenDefault_thenSynthetic() {
        let pickedPolicy = AudioLanguageSeed.pick(
            tracks: [originalJA, dubEN],
            last: nil,
            policy: .original
        )
        XCTAssertEqual(pickedPolicy.id, originalJA.id)

        let noOriginal = AudioTrack(
            id: "en|dub",
            languageCode: "en",
            label: "English",
            isOriginal: false,
            isDefault: true
        )
        let pickedDefault = AudioLanguageSeed.pick(
            tracks: [noOriginal],
            last: nil,
            policy: .original
        )
        XCTAssertEqual(pickedDefault.id, noOriginal.id)

        let synthetic = AudioLanguageSeed.pick(
            tracks: [],
            last: nil,
            policy: .youtubeDefault
        )
        XCTAssertEqual(synthetic.id, "default")
        XCTAssertNil(synthetic.languageCode)
        XCTAssertTrue(synthetic.isDefault)
    }
}
