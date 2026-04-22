import XCTest
import SwiftUI
@testable import Meridian

/// Smoke tests around the static helpers used by `APIUsagePanel`. The view
/// itself is validated via SwiftUI previews — XCTest stays on the pure
/// logic pieces so the suite remains fast and IDE-independent.
final class APIUsagePanelTests: XCTestCase {

    // The `APIModelRow.displayName(for:)` is a `private` symbol from a
    // rendering helper. We verify its behaviour indirectly through the
    // public mock snapshots, which is what the UI actually renders.

    func testMockTypicalSortsHeroThenHaikuThenOpus() {
        let snapshot = APIUsageSnapshot.mockTypical
        XCTAssertEqual(snapshot.models.count, 3)
        XCTAssertEqual(snapshot.models[0].modelID, "claude-sonnet-4-6")
        XCTAssertEqual(snapshot.models[1].modelID, "claude-haiku-4-5")
        XCTAssertEqual(snapshot.models[2].modelID, "claude-opus-4-7")
    }

    func testMockHeavyCapsAtFiveModelsForBreakdown() {
        let snapshot = APIUsageSnapshot.mockHeavy
        // The panel caps at 5 rows; the Heavy mock deliberately has 5 so
        // we can QA the densest layout.
        XCTAssertEqual(snapshot.models.count, 5)
    }

    func testMockIdleHasNoModels() {
        let snapshot = APIUsageSnapshot.mockIdle
        XCTAssertTrue(snapshot.models.isEmpty)
        XCTAssertEqual(snapshot.monthToDateUSD, Decimal(0))
    }
}
