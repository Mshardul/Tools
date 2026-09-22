@testable import GrabberKit
import XCTest

final class ColumnConfigTests: XCTestCase {
    func test_actionsPinnedLastEnforcedOnLoad() throws {
        let json = """
        {
          "visibleColumns": ["title", "actions", "status"],
          "columnOrder": ["status", "title", "actions"]
        }
        """
        let config = try JSONDecoder().decode(ColumnConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.columnOrder.last, .actions)
        XCTAssertEqual(config.visibleColumns.last, .actions)
    }

    func test_actionsAlwaysVisible() {
        var config = ColumnConfig(
            visibleColumns: [.title],
            columnOrder: ColumnID.defaultOrder
        )
        XCTAssertTrue(config.visibleColumns.contains(.actions))
    }

    func test_titleAlwaysVisible() {
        var config = ColumnConfig(
            visibleColumns: [.status, .actions],
            columnOrder: ColumnID.defaultOrder
        )
        XCTAssertTrue(config.visibleColumns.contains(.title))
    }

    func test_unknownColumnDroppedOnLoad() throws {
        let json = """
        {
          "visibleColumns": ["title", "bogus", "status", "actions"],
          "columnOrder": ["title", "bogus", "status", "actions"]
        }
        """
        let config = try JSONDecoder().decode(ColumnConfig.self, from: Data(json.utf8))
        XCTAssertFalse(config.visibleColumns.map(\.rawValue).contains("bogus"))
        XCTAssertFalse(config.columnOrder.map(\.rawValue).contains("bogus"))
    }

    func test_omittedKnownColumnAppendedAtDefault() throws {
        let json = """
        { "visibleColumns": ["title", "actions"], "columnOrder": ["title", "actions"] }
        """
        let config = try JSONDecoder().decode(ColumnConfig.self, from: Data(json.utf8))
        XCTAssertTrue(config.columnOrder.contains(.status))
        XCTAssertEqual(config.columnOrder.last, .actions)
    }

    func test_sortColumnChangeClearsPrevious() {
        var config = ColumnConfig.default
        config.sortColumn = .title
        config.sortDirection = .descending
        config.cycleSort(on: .size)
        XCTAssertEqual(config.sortColumn, .size)
        XCTAssertEqual(config.sortDirection, .ascending)
    }

    func test_defaultSortsByAddedAtDescending() {
        let config = ColumnConfig.default
        XCTAssertEqual(config.sortColumn, .addedAt)
        XCTAssertEqual(config.sortDirection, .descending)
    }

    func test_addedAtVisibleByDefault() {
        XCTAssertTrue(ColumnConfig.default.visibleColumns.contains(.addedAt))
    }

    func test_statusHiddenByDefault() {
        XCTAssertFalse(ColumnConfig.default.visibleColumns.contains(.status))
    }

    func test_remarkHiddenByDefault() {
        XCTAssertFalse(ColumnConfig.default.visibleColumns.contains(.remark))
    }

    func test_remarkColumnCanBeShown() {
        var config = ColumnConfig.default
        config.setColumnVisible(.remark, visible: true)
        XCTAssertTrue(config.visibleColumns.contains(.remark))
    }

    func test_roundTripCodable() throws {
        var original = ColumnConfig.default
        original.sortColumn = .addedAt
        original.sortDirection = .descending
        original.columnFilters = [.type: ["Video"]]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ColumnConfig.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_columnWidthsRoundTrip() throws {
        var original = ColumnConfig.default
        original.setColumnWidth(.title, 320)
        original.setColumnWidth(.site, 120)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ColumnConfig.self, from: data)
        XCTAssertEqual(decoded.columnWidths[.title], 320)
        XCTAssertEqual(decoded.columnWidths[.site], 120)
    }

    func test_setColumnWidthIgnoresActions() {
        var config = ColumnConfig.default
        config.setColumnWidth(.actions, 400)
        XCTAssertNil(config.columnWidths[.actions])
    }

    func test_unknownWidthKeyDroppedOnLoad() throws {
        let json = """
        {
          "visibleColumns": ["title", "actions"],
          "columnOrder": ["title", "actions"],
          "columnWidths": { "title": 280, "bogus": 99 }
        }
        """
        let config = try JSONDecoder().decode(ColumnConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.columnWidths[.title], 280)
        XCTAssertEqual(config.columnWidths.count, 1)
    }

    func test_moveColumnBeforeActions() {
        var config = ColumnConfig(
            visibleColumns: [.title, .progress, .site, .actions],
            columnOrder: [.title, .progress, .site, .actions]
        )
        config.moveColumn(from: .progress, to: .actions)
        XCTAssertEqual(
            config.orderedVisibleColumns(),
            [.title, .site, .progress, .actions]
        )
        XCTAssertEqual(config.columnOrder.last, .actions)
    }

    func test_moveColumnRejectsMovingActions() {
        var config = ColumnConfig(
            visibleColumns: [.title, .progress, .actions],
            columnOrder: [.title, .progress, .actions]
        )
        config.moveColumn(from: .actions, to: .title)
        XCTAssertEqual(config.orderedVisibleColumns(), [.title, .progress, .actions])
    }
}
