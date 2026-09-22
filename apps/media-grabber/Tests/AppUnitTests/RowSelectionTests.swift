@testable import MediaGrabber
import XCTest

final class RowSelectionTests: XCTestCase {
    private let idA = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let idB = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let idC = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    private let idD = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!

    func test_pruneDropsInvisible() {
        let pruned = RowSelection.prune([idA, idB, idC], visibleChildIDs: [idA, idC])
        XCTAssertEqual(pruned, [idA, idC])
    }

    func test_toggleAddsAndRemoves() {
        XCTAssertEqual(RowSelection.toggle(idA, in: []), [idA])
        XCTAssertEqual(RowSelection.toggle(idA, in: [idA, idB]), [idB])
    }

    func test_rangeSelectingInclusiveSlice() {
        let order = [idA, idB, idC, idD]
        let ranged = RowSelection.rangeSelecting(
            from: idA,
            to: idC,
            visibleChildOrder: order,
            replacing: [idD]
        )
        XCTAssertEqual(ranged, [idA, idB, idC])
    }

    func test_rangeSelectingWithoutAnchorSelectsTargetOnly() {
        let ranged = RowSelection.rangeSelecting(
            from: nil,
            to: idB,
            visibleChildOrder: [idA, idB, idC],
            replacing: [idA, idC]
        )
        XCTAssertEqual(ranged, [idB])
    }

    func test_rangeSelectingMissingAnchorSelectsTargetOnly() {
        let ranged = RowSelection.rangeSelecting(
            from: idD,
            to: idB,
            visibleChildOrder: [idA, idB, idC],
            replacing: []
        )
        XCTAssertEqual(ranged, [idB])
    }
}
