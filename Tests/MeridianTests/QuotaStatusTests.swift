import XCTest
@testable import Meridian

final class QuotaStatusTests: XCTestCase {
    // Boundary cases — the thresholds are the load-bearing part of the spec.

    func testZeroPercentIsUnused() {
        XCTAssertEqual(QuotaStatus.from(percent: 0), .unused)
    }

    func testVeryLowPercentRoundsToUnused() {
        // 0.4 rounds to 0 → unused (spec : "0 % = non utilisé")
        XCTAssertEqual(QuotaStatus.from(percent: 0.4), .unused)
    }

    func testJustAboveZeroIsSerene() {
        // 0.6 rounds to 1 → serene (spec : "1-49 % = cruise")
        XCTAssertEqual(QuotaStatus.from(percent: 0.6), .serene)
        XCTAssertEqual(QuotaStatus.from(percent: 1), .serene)
        XCTAssertEqual(QuotaStatus.from(percent: 27), .serene)
    }

    func testUpperSereneBoundary() {
        XCTAssertEqual(QuotaStatus.from(percent: 49), .serene)
        XCTAssertEqual(QuotaStatus.from(percent: 49.4), .serene)
    }

    func testHalfwayEscalatesToWatch() {
        // 49.6 rounds to 50 → climb
        XCTAssertEqual(QuotaStatus.from(percent: 49.6), .watch)
        XCTAssertEqual(QuotaStatus.from(percent: 50), .watch)
        XCTAssertEqual(QuotaStatus.from(percent: 64), .watch)
        XCTAssertEqual(QuotaStatus.from(percent: 79), .watch)
    }

    func testUpperWatchBoundary() {
        XCTAssertEqual(QuotaStatus.from(percent: 79.4), .watch)
    }

    func testCriticalThreshold() {
        XCTAssertEqual(QuotaStatus.from(percent: 79.6), .critical)
        XCTAssertEqual(QuotaStatus.from(percent: 80), .critical)
        XCTAssertEqual(QuotaStatus.from(percent: 92), .critical)
        XCTAssertEqual(QuotaStatus.from(percent: 100), .critical)
        XCTAssertEqual(QuotaStatus.from(percent: 150), .critical)
    }

    // Labels must not be empty — they are the primary a11y channel.

    func testAllStatusesProvideANonEmptyLabel() {
        for status in QuotaStatus.allCases {
            XCTAssertFalse(status.label.isEmpty, "status \(status) has empty label")
        }
    }

    // Flight-trajectory lexicon — locks the user-facing wording to the
    // cockpit metaphor (`idle · cruise · climb · peak`). Update this mapping
    // only with explicit product validation.

    func testLabelsUseFlightTrajectoryLexicon() {
        XCTAssertEqual(QuotaStatus.unused.label,   "idle")
        XCTAssertEqual(QuotaStatus.serene.label,   "cruise")
        XCTAssertEqual(QuotaStatus.watch.label,    "climb")
        XCTAssertEqual(QuotaStatus.critical.label, "peak")
    }
}
