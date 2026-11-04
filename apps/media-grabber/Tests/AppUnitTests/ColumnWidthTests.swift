import AppKit
@testable import GrabberKit
@testable import MediaGrabber
import XCTest

final class ColumnWidthTests: XCTestCase {
    func test_resolvedUsesOverride() {
        var config = ColumnConfig.default
        config.setColumnWidth(.title, 333)
        XCTAssertEqual(ColumnMetrics.resolvedWidth(for: .title, config: config), 333)
    }

    func test_resolvedFallsBackToDefault() {
        let config = ColumnConfig.default
        XCTAssertEqual(
            ColumnMetrics.resolvedWidth(for: .title, config: config),
            ColumnMetrics.width(for: .title)
        )
    }

    func test_clampEnforcesMinimum() {
        let min = ColumnMetrics.minWidth(for: .title)
        XCTAssertEqual(ColumnMetrics.clamped(10, for: .title), min)
    }

    func test_defaultColumnsFitActionsWithoutHorizontalScroll() {
        let columns = ColumnConfig.default.orderedVisibleColumns()
        let occupied = DownloadsGridColumns.selectionWidth
            + columns.reduce(CGFloat(0)) { $0 + ColumnMetrics.width(for: $1) }
        XCTAssertLessThanOrEqual(occupied, ColumnMetrics.tableViewport(windowWidth: 820))
        XCTAssertLessThanOrEqual(occupied, ColumnMetrics.tableViewport(windowWidth: 980))
    }

    @MainActor
    func test_titleCueDiffersForFailedAndSaved() {
        let tokens = DownloadsGridTokens.aurora
        let failed = GridTitleCellView()
        failed.apply(title: "Clip", state: .failed(.unknown(raw: "")), tokens: tokens)
        let saved = GridTitleCellView()
        saved.apply(title: "Clip", state: .completed, tokens: tokens)
        XCTAssertNotEqual(failed.cueColor, saved.cueColor)
    }

    func test_actionsNotResizable() {
        XCTAssertFalse(ColumnMetrics.isResizable(.actions))
        XCTAssertTrue(ColumnMetrics.isResizable(.title))
    }

    func test_autoFitUsesWidestSampleAndMin() {
        let min = ColumnMetrics.minWidth(for: .site)
        let fitted = ColumnMetrics.autoFitWidth(
            sampleStrings: ["a", String(repeating: "W", count: 40)],
            min: min
        )
        XCTAssertGreaterThanOrEqual(fitted, min)
        let shortOnly = ColumnMetrics.autoFitWidth(sampleStrings: ["a"], min: min)
        XCTAssertEqual(shortOnly, min)
        XCTAssertGreaterThan(fitted, shortOnly)
    }
}
