import XCTest
@testable import Meridian

final class UsageResponseParsingTests: XCTestCase {
    func testParsesCompleteRealWorldResponse() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 60.0,
                "resets_at": "2026-04-20T14:00:00.656479+00:00"
            },
            "seven_day": {
                "utilization": 22.0,
                "resets_at": "2026-04-24T07:00:00.656499+00:00"
            },
            "seven_day_oauth_apps": null,
            "seven_day_opus": null,
            "seven_day_sonnet": {
                "utilization": 2.0,
                "resets_at": "2026-04-24T07:00:00.656508+00:00"
            },
            "seven_day_cowork": null,
            "seven_day_omelette": {
                "utilization": 100.0,
                "resets_at": "2026-04-25T09:00:00.656527+00:00"
            },
            "iguana_necktie": null,
            "omelette_promotional": null,
            "extra_usage": {
                "is_enabled": true,
                "monthly_limit": 2000,
                "used_credits": 0.0,
                "utilization": null,
                "currency": "EUR"
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.claudeAI.decode(UsageResponse.self, from: json)

        XCTAssertEqual(response.fiveHour?.utilization, 60.0)
        XCTAssertEqual(response.sevenDay?.utilization, 22.0)
        XCTAssertEqual(response.sevenDaySonnet?.utilization, 2.0)
        XCTAssertEqual(response.sevenDayOmelette?.utilization, 100.0)
    }

    func testPartialWindowFallsBackToNilInsteadOfFailingWholeResponse() throws {
        // After periods of inactivity, claude.ai has been observed serving
        // windows that are present but missing fields (e.g. `utilization`
        // alone with no `resets_at`). Before the per-window tolerance, this
        // collapsed the whole decode into a generic "Unexpected format"
        // popover. Now the broken window is dropped to nil and the healthy
        // ones still surface.
        let json = """
        {
            "five_hour": {
                "utilization": 60.0,
                "resets_at": "2026-04-20T14:00:00.656479+00:00"
            },
            "seven_day": { "utilization": 22.0 },
            "seven_day_sonnet": null,
            "seven_day_omelette": {
                "utilization": 100.0,
                "resets_at": "2026-04-25T09:00:00.656527+00:00"
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.claudeAI.decode(UsageResponse.self, from: json)

        XCTAssertEqual(response.fiveHour?.utilization, 60.0)
        XCTAssertNil(response.sevenDay, "partial window without resets_at should drop to nil")
        XCTAssertNil(response.sevenDaySonnet)
        XCTAssertEqual(response.sevenDayOmelette?.utilization, 100.0)
    }

    func testNullWindowsAreOptional() throws {
        let json = """
        {
            "five_hour": null,
            "seven_day": null,
            "seven_day_sonnet": null,
            "seven_day_omelette": null
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.claudeAI.decode(UsageResponse.self, from: json)

        XCTAssertNil(response.fiveHour)
        XCTAssertNil(response.sevenDay)
        XCTAssertNil(response.sevenDaySonnet)
        XCTAssertNil(response.sevenDayOmelette)
    }

    func testUnknownFieldsAreIgnored() throws {
        let json = """
        {
            "five_hour": { "utilization": 10.0, "resets_at": "2026-04-20T14:00:00.656479+00:00" },
            "some_future_field": { "nested": [1, 2, 3] },
            "another_codename": null
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.claudeAI.decode(UsageResponse.self, from: json)
        XCTAssertEqual(response.fiveHour?.utilization, 10.0)
    }

    func testDatesAreParsedAsUTC() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 50.0,
                "resets_at": "2026-04-20T14:00:00.656479+00:00"
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.claudeAI.decode(UsageResponse.self, from: json)
        let components = Calendar(identifier: .gregorian)
            .dateComponents(in: TimeZone(identifier: "UTC")!, from: response.fiveHour!.resetsAt)

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 4)
        XCTAssertEqual(components.day, 20)
        XCTAssertEqual(components.hour, 14)
        XCTAssertEqual(components.minute, 0)
    }

    func testDatesWithoutFractionalSecondsStillParse() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 50.0,
                "resets_at": "2026-04-20T14:00:00+00:00"
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.claudeAI.decode(UsageResponse.self, from: json)
        XCTAssertNotNil(response.fiveHour?.resetsAt)
    }
}

final class UsageWindowTests: XCTestCase {
    func testRemainingPercentClampsToValidRange() {
        let ref = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(UsageWindow(utilization: 0, resetsAt: ref).remainingPercent, 100)
        XCTAssertEqual(UsageWindow(utilization: 40, resetsAt: ref).remainingPercent, 60)
        XCTAssertEqual(UsageWindow(utilization: 100, resetsAt: ref).remainingPercent, 0)
        XCTAssertEqual(UsageWindow(utilization: 110, resetsAt: ref).remainingPercent, 0)
        XCTAssertEqual(UsageWindow(utilization: -10, resetsAt: ref).remainingPercent, 100)
    }

    func testTimeUntilResetIsRelativeToReference() {
        let reset = Date(timeIntervalSince1970: 1_000)
        let window = UsageWindow(utilization: 50, resetsAt: reset)

        let ref = Date(timeIntervalSince1970: 400)
        XCTAssertEqual(window.timeUntilReset(relativeTo: ref), 600, accuracy: 0.001)
    }
}
