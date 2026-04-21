import XCTest
@testable import Meridian

final class QuotaMappingTests: XCTestCase {
    func testMapsAllWindowsFromResponse() {
        let reset = Date(timeIntervalSince1970: 1_000)
        let response = UsageResponse(
            fiveHour: UsageWindow(utilization: 60, resetsAt: reset),
            sevenDay: UsageWindow(utilization: 22, resetsAt: reset),
            sevenDaySonnet: UsageWindow(utilization: 2, resetsAt: reset),
            sevenDayOmelette: UsageWindow(utilization: 100, resetsAt: reset)
        )

        let captured = Date(timeIntervalSince1970: 500)
        let quota = Quota(from: response, capturedAt: captured)

        XCTAssertEqual(quota.session?.utilization, 60)
        XCTAssertEqual(quota.allModels?.utilization, 22)
        XCTAssertEqual(quota.sonnet?.utilization, 2)
        XCTAssertEqual(quota.claudeDesign?.utilization, 100)
        XCTAssertEqual(quota.capturedAt, captured)
    }

    func testNilWindowsAreForwarded() {
        let response = UsageResponse(
            fiveHour: nil,
            sevenDay: nil,
            sevenDaySonnet: nil,
            sevenDayOmelette: nil
        )

        let quota = Quota(from: response, capturedAt: .now)

        XCTAssertNil(quota.session)
        XCTAssertNil(quota.allModels)
        XCTAssertNil(quota.sonnet)
        XCTAssertNil(quota.claudeDesign)
    }
}
