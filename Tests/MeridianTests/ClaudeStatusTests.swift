import XCTest
@testable import Meridian

/// Pure-model tests for `ClaudeStatus` and its derivation helpers.
final class ClaudeStatusTests: XCTestCase {

    // MARK: - Severity ordering

    func testWorstStatusPicksHighestSeverity() {
        let status = ClaudeStatus.degraded(
            components: [
                ComponentState(id: ClaudeStatusComponents.claudeAPIID, name: "Claude API", status: .degradedPerformance),
                ComponentState(id: ClaudeStatusComponents.claudeCodeID, name: "Claude Code", status: .majorOutage),
            ],
            incident: nil
        )
        XCTAssertEqual(status.worstStatus, .majorOutage,
                       "major outage must win over degraded_performance")
    }

    func testWorstStatusOrdersPartialBelowMajor() {
        let status = ClaudeStatus.degraded(
            components: [
                ComponentState(id: ClaudeStatusComponents.claudeAPIID, name: "A", status: .partialOutage),
                ComponentState(id: ClaudeStatusComponents.claudeCodeID, name: "B", status: .degradedPerformance),
            ],
            incident: nil
        )
        XCTAssertEqual(status.worstStatus, .partialOutage)
    }

    func testWorstStatusOrdersMaintenanceBelowAnyRealOutage() {
        // Maintenance is intentionally lower than degraded/partial/major —
        // the chip should tint red / amber / orange, not blue, when both
        // are present.
        let status = ClaudeStatus.degraded(
            components: [
                ComponentState(id: ClaudeStatusComponents.claudeAPIID, name: "A", status: .underMaintenance),
                ComponentState(id: ClaudeStatusComponents.claudeCodeID, name: "B", status: .degradedPerformance),
            ],
            incident: nil
        )
        XCTAssertEqual(status.worstStatus, .degradedPerformance)
    }

    func testWorstStatusOnAllClearReturnsOperational() {
        XCTAssertEqual(ClaudeStatus.allClear.worstStatus, .operational)
    }

    // MARK: - ClaudeStatus helpers

    func testIsClaudeAPIMajorOutageFlagsOnlyAPI() {
        let codeOnly = ClaudeStatus.degraded(
            components: [
                ComponentState(id: ClaudeStatusComponents.claudeAPIID, name: "API", status: .operational),
                ComponentState(id: ClaudeStatusComponents.claudeCodeID, name: "Code", status: .majorOutage),
            ],
            incident: nil
        )
        XCTAssertFalse(codeOnly.isClaudeAPIMajorOutage,
                       "Code in major outage while API is up must NOT flip the API flag")

        let apiDown = ClaudeStatus.degraded(
            components: [
                ComponentState(id: ClaudeStatusComponents.claudeAPIID, name: "API", status: .majorOutage),
                ComponentState(id: ClaudeStatusComponents.claudeCodeID, name: "Code", status: .operational),
            ],
            incident: nil
        )
        XCTAssertTrue(apiDown.isClaudeAPIMajorOutage)

        XCTAssertFalse(ClaudeStatus.allClear.isClaudeAPIMajorOutage)
        XCTAssertFalse(ClaudeStatus.unknown.isClaudeAPIMajorOutage)
    }

    // MARK: - ComponentStatus.decode

    func testComponentStatusDecodesAllKnownValues() {
        XCTAssertEqual(ComponentStatus.decode("operational"), .operational)
        XCTAssertEqual(ComponentStatus.decode("degraded_performance"), .degradedPerformance)
        XCTAssertEqual(ComponentStatus.decode("partial_outage"), .partialOutage)
        XCTAssertEqual(ComponentStatus.decode("major_outage"), .majorOutage)
        XCTAssertEqual(ComponentStatus.decode("under_maintenance"), .underMaintenance)
    }

    func testComponentStatusUnknownKeepsRawPayload() {
        XCTAssertEqual(ComponentStatus.decode("new_status_we_dont_know"),
                       .unknown("new_status_we_dont_know"))
    }

    func testComponentStatusIsDegradedExcludesOperational() {
        XCTAssertFalse(ComponentStatus.operational.isDegraded)
        XCTAssertTrue(ComponentStatus.degradedPerformance.isDegraded)
        XCTAssertTrue(ComponentStatus.partialOutage.isDegraded)
        XCTAssertTrue(ComponentStatus.majorOutage.isDegraded)
        XCTAssertTrue(ComponentStatus.underMaintenance.isDegraded)
        XCTAssertTrue(ComponentStatus.unknown("x").isDegraded)
    }

    // MARK: - distill: incident ordering

    func testDistillOrdersActiveIncidentsMostRecentFirst() throws {
        let wire = try JSONDecoder.statusClient.decode(
            WireSummary.self,
            from: StatusSummaryFixtures.apiMajorOutageMultipleIncidents
        )
        let snapshot = ClaudeStatusClient.distill(wire)
        // Ordered most-recent first. We expect the newer API incident at index 0.
        XCTAssertEqual(snapshot.activeIncidents.first?.name, "Widespread connectivity issues on Claude API")
        XCTAssertEqual(snapshot.activeIncidents.last?.name, "Older unrelated noise")
    }
}

// MARK: - Decoder helper

private extension JSONDecoder {
    /// Exposes the client's decoder configuration to tests without making it
    /// public on the type itself.
    static let statusClient: JSONDecoder = ClaudeStatusClient.makeDecoder()
}
