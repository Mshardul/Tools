@testable import MediaGrabber
import XCTest

final class GridAccessibilityTests: XCTestCase {
    func test_keyboard_arrowsMoveFocusAndShiftExtends() {
        XCTAssertEqual(
            GridKeyboard.command(keyCode: GridKeyboard.down, shift: false),
            .move(delta: 1, extending: false)
        )
        XCTAssertEqual(GridKeyboard.command(keyCode: GridKeyboard.up, shift: true), .move(delta: -1, extending: true))
    }

    func test_keyboard_spaceTogglesAndTabEntersActions() {
        XCTAssertEqual(GridKeyboard.command(keyCode: GridKeyboard.space, shift: false), .toggleSelection)
        XCTAssertEqual(GridKeyboard.command(keyCode: GridKeyboard.tab, shift: false), .enterRowActions(reverse: false))
        XCTAssertEqual(GridKeyboard.command(keyCode: GridKeyboard.tab, shift: true), .enterRowActions(reverse: true))
        XCTAssertEqual(GridKeyboard.command(keyCode: 36, shift: false), .ignored)
    }

    func test_focusDestination_clampsToRows() {
        XCTAssertEqual(GridKeyboardFocus.destination(from: -1, delta: 1, rowCount: 3), 0)
        XCTAssertEqual(GridKeyboardFocus.destination(from: 1, delta: 1, rowCount: 3), 2)
        XCTAssertNil(GridKeyboardFocus.destination(from: 2, delta: 1, rowCount: 3))
        XCTAssertNil(GridKeyboardFocus.destination(from: 0, delta: -1, rowCount: 3))
    }

    func test_keyView_onlyEnabledButtonsOnTheFocusedRowAcceptFocus() {
        XCTAssertFalse(GridKeyView.refusesFirstResponder(enabled: true, rowIsKeyboardFocus: true))
        XCTAssertTrue(GridKeyView.refusesFirstResponder(enabled: false, rowIsKeyboardFocus: true))
        XCTAssertTrue(GridKeyView.refusesFirstResponder(enabled: true, rowIsKeyboardFocus: false))
    }

    func test_headerLabel_namesSortAndFilter() {
        XCTAssertEqual(
            GridHeaderAccessibility.label(title: "Title", sort: .ascending, showsFilter: false, filterActive: false),
            "Title, sorted ascending"
        )
        XCTAssertEqual(
            GridHeaderAccessibility.label(title: "Status", sort: .available, showsFilter: true, filterActive: true),
            "Status, sortable, filter on"
        )
        XCTAssertEqual(GridHeaderAccessibility.selectionLabel(allSelected: false), "Select all")
        XCTAssertEqual(GridHeaderAccessibility.selectionLabel(allSelected: true), "Clear selection")
    }

    func test_statusLabel_appendsRemarkOnlyWhenPresent() {
        XCTAssertEqual(
            GridStatusAccessibility.label(status: "Failed", remark: "Private video"),
            "Failed, Private video"
        )
        XCTAssertEqual(GridStatusAccessibility.label(status: "Downloading", remark: ""), "Downloading")
    }

    func test_refreshLabel_namesTheChipAction() {
        XCTAssertEqual(HealthChipAccessibility.refreshLabel(id: "shield"), "Restart bot-check shield")
        XCTAssertEqual(HealthChipAccessibility.refreshLabel(id: "engine"), "Reinstall downloader")
        XCTAssertEqual(HealthChipAccessibility.refreshLabel(id: "other"), "Refresh")
        XCTAssertEqual(HealthChipAccessibility.popoverLabel(chipLabel: "youtube.com"), "youtube.com, host rate")
    }
}
