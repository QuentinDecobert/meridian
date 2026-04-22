import XCTest
@testable import Meridian

/// Tests for the "bonus wire" — the correlation surfaced when the quota fetch
/// is failing AND Claude API is in `.majorOutage`. These assert the two
/// load-bearing bits of logic that decide whether the wire fires :
///
///   1. `ClaudeStatus.isClaudeAPIMajorOutage` — the single predicate read by
///      both `PopoverView` (to pick the FlightDeck branch) and `MenuBarLabel`
///      (to drive the red pip).
///   2. `StaleFormatter.minutesAgo` / `compactAgo` — the two copy paths used
///      by the banner and the footer.
///
/// View-layer assembly (FlightDeckView + StatusSection) is already covered by
/// previews and exercised by the build; these tests stay focused on the pure
/// logic so they run fast and stay trivially deterministic.
final class BonusWireLogicTests: XCTestCase {

    // MARK: - isClaudeAPIMajorOutage

    /// The happy path: API specifically in `.majorOutage` → wire fires.
    func testBonusWireFiresWhenClaudeAPIIsInMajorOutage() {
        let status: ClaudeStatus = .degraded(
            components: [
                ComponentState(id: ClaudeStatusComponents.claudeAPIID, name: "Claude API", status: .majorOutage),
                ComponentState(id: ClaudeStatusComponents.claudeCodeID, name: "Claude Code", status: .operational),
            ],
            incident: nil
        )
        XCTAssertTrue(status.isClaudeAPIMajorOutage)
    }

    /// Claude Code going down must NOT fire the wire — the menu-bar pip and
    /// the bonus-wire hero are reserved for Claude API specifically.
    /// (Product call, noted in the proto's decision block.)
    func testBonusWireDoesNotFireWhenOnlyClaudeCodeIsDown() {
        let status: ClaudeStatus = .degraded(
            components: [
                ComponentState(id: ClaudeStatusComponents.claudeAPIID, name: "Claude API", status: .operational),
                ComponentState(id: ClaudeStatusComponents.claudeCodeID, name: "Claude Code", status: .majorOutage),
            ],
            incident: nil
        )
        XCTAssertFalse(status.isClaudeAPIMajorOutage)
    }

    /// Lesser severities on Claude API (degraded / partial / maintenance)
    /// must NOT fire the wire — those stay inside the popover status chip.
    func testBonusWireDoesNotFireForLesserAPIServiceEvents() {
        for severity: ComponentStatus in [.degradedPerformance, .partialOutage, .underMaintenance] {
            let status: ClaudeStatus = .degraded(
                components: [
                    ComponentState(id: ClaudeStatusComponents.claudeAPIID, name: "Claude API", status: severity),
                    ComponentState(id: ClaudeStatusComponents.claudeCodeID, name: "Claude Code", status: .operational),
                ],
                incident: nil
            )
            XCTAssertFalse(
                status.isClaudeAPIMajorOutage,
                "Severity \(severity) must NOT fire the bonus wire"
            )
        }
    }

    /// `.allClear` and `.unknown` never fire — defensive, they don't carry
    /// component data in the first place.
    func testBonusWireDoesNotFireForAllClearOrUnknown() {
        XCTAssertFalse(ClaudeStatus.allClear.isClaudeAPIMajorOutage)
        XCTAssertFalse(ClaudeStatus.unknown.isClaudeAPIMajorOutage)
    }

    /// Edge case : the API outage AND Code outage combo. Wire still fires
    /// because Claude API specifically is in `.majorOutage` — the Code
    /// status doesn't matter.
    func testBonusWireFiresEvenWhenClaudeCodeIsAlsoDown() {
        let status: ClaudeStatus = .degraded(
            components: [
                ComponentState(id: ClaudeStatusComponents.claudeAPIID, name: "Claude API", status: .majorOutage),
                ComponentState(id: ClaudeStatusComponents.claudeCodeID, name: "Claude Code", status: .majorOutage),
            ],
            incident: nil
        )
        XCTAssertTrue(status.isClaudeAPIMajorOutage)
    }

    // MARK: - StaleFormatter.minutesAgo

    func testMinutesAgoReturnsUnknownForNil() {
        XCTAssertEqual(StaleFormatter.minutesAgo(nil), "unknown")
    }

    func testMinutesAgoUnderOneMinuteReturnsLessThanOneMin() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fresh = now.addingTimeInterval(-30)
        XCTAssertEqual(StaleFormatter.minutesAgo(fresh, reference: now), "< 1 min ago")
    }

    func testMinutesAgoUnderOneHourReturnsMinAgo() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let refreshed = now.addingTimeInterval(-27 * 60)
        XCTAssertEqual(StaleFormatter.minutesAgo(refreshed, reference: now), "27 min ago")
    }

    func testMinutesAgoExactlyOneHourReturnsHourAgo() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let refreshed = now.addingTimeInterval(-60 * 60)
        XCTAssertEqual(StaleFormatter.minutesAgo(refreshed, reference: now), "1h ago")
    }

    func testMinutesAgoOverOneHourReturnsCompositeFormat() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let refreshed = now.addingTimeInterval(-(1 * 60 * 60 + 12 * 60))
        XCTAssertEqual(StaleFormatter.minutesAgo(refreshed, reference: now), "1h 12m ago")
    }

    // MARK: - StaleFormatter.compactAgo

    func testCompactAgoIsUppercaseReady() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(StaleFormatter.compactAgo(nil, reference: now), "UNKNOWN")
        XCTAssertEqual(
            StaleFormatter.compactAgo(now.addingTimeInterval(-10), reference: now),
            "JUST NOW"
        )
        XCTAssertEqual(
            StaleFormatter.compactAgo(now.addingTimeInterval(-27 * 60), reference: now),
            "27 MIN AGO"
        )
        XCTAssertEqual(
            StaleFormatter.compactAgo(now.addingTimeInterval(-3600), reference: now),
            "1H AGO"
        )
        XCTAssertEqual(
            StaleFormatter.compactAgo(now.addingTimeInterval(-(2 * 3600 + 5 * 60)), reference: now),
            "2H 5M AGO"
        )
    }
}
