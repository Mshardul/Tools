@testable import GrabberKit
import XCTest

final class VideoQualityOptionsTests: XCTestCase {
    func test_unknown_offersFullLadderPlusBest() {
        XCTAssertEqual(
            VideoQualityOptions.offered(from: meta(.unknown)),
            [2160, 1440, 1080, 720, 480, .max]
        )
    }

    func test_listed1080_keepsRungsAtOrBelowPlusBest() {
        XCTAssertEqual(
            VideoQualityOptions.offered(from: meta(.listed, heights: [1080, 720])),
            [1080, 720, 480, .max]
        )
    }

    func test_listedEmptyHeights_offersBestOnly() {
        XCTAssertEqual(
            VideoQualityOptions.offered(from: meta(.listed, heights: [])),
            [.max]
        )
    }

    func test_seed_prefersLastWhenOffered() {
        let offered = [1080, 720, 480, Int.max]
        XCTAssertEqual(
            VideoQualityOptions.seed(last: 720, defaultHeight: 1080, offered: offered),
            720
        )
    }

    func test_seed_fallsBackToDefaultThenMaxNumeric() {
        let withDefault = [1080, 720, 480, Int.max]
        XCTAssertEqual(
            VideoQualityOptions.seed(last: 2160, defaultHeight: 1080, offered: withDefault),
            1080
        )
        XCTAssertEqual(
            VideoQualityOptions.seed(last: 2160, defaultHeight: 1440, offered: [720, 480, .max]),
            720
        )
        XCTAssertEqual(
            VideoQualityOptions.seed(last: nil, defaultHeight: 1080, offered: [.max]),
            .max
        )
    }

    private func meta(
        _ availability: FormatAvailability,
        heights: [Int] = []
    ) -> MediaMetadata {
        MediaMetadata(
            title: "Clip",
            durationSeconds: 1,
            isPlaylist: false,
            sourceURL: "https://example.com/v",
            formatAvailability: availability,
            videoHeights: heights
        )
    }
}
