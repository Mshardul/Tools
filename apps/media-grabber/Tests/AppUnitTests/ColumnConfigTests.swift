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

    func test_roundTripCodable() throws {
        var original = ColumnConfig.default
        original.sortColumn = .addedAt
        original.sortDirection = .descending
        original.columnFilters = [.type: ["Video"]]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ColumnConfig.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
