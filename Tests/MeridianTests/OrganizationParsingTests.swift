import XCTest
@testable import Meridian

final class OrganizationParsingTests: XCTestCase {
    func testParsesMultiOrgRealWorldResponse() throws {
        let json = """
        [
            {
                "id": 32564867,
                "uuid": "631972a6-f5c1-452a-838f-e7713f861d09",
                "name": "user@example.com's Organization",
                "capabilities": ["chat", "claude_max"],
                "parent_organization_uuid": null,
                "rate_limit_tier": "default_claude_max_5x",
                "billing_type": "stripe_subscription"
            },
            {
                "id": 161494520,
                "uuid": "7564efdd-1fa9-4b50-b261-1d69b6bb72f7",
                "name": "User's Individual Org",
                "capabilities": ["api", "api_individual"],
                "parent_organization_uuid": null,
                "rate_limit_tier": "auto_api_evaluation",
                "billing_type": null
            }
        ]
        """.data(using: .utf8)!

        let orgs = try JSONDecoder.claudeAI.decode([Organization].self, from: json)

        XCTAssertEqual(orgs.count, 2)

        let claudeOrg = orgs[0]
        XCTAssertEqual(claudeOrg.uuid, "631972a6-f5c1-452a-838f-e7713f861d09")
        XCTAssertTrue(claudeOrg.supportsChat)
        XCTAssertEqual(claudeOrg.planLabel, "Max 5×")

        let apiOrg = orgs[1]
        XCTAssertFalse(apiOrg.supportsChat)
        XCTAssertNil(apiOrg.planLabel)
    }

    func testFirstSupportingChatPicksCorrectOrg() throws {
        let chatOrg = Organization(
            uuid: "aaa", name: "Claude", capabilities: ["chat", "claude_max"],
            rateLimitTier: "default_claude_max_5x"
        )
        let apiOrg = Organization(
            uuid: "bbb", name: "API", capabilities: ["api"],
            rateLimitTier: nil
        )

        XCTAssertEqual([apiOrg, chatOrg].firstSupportingChat()?.uuid, "aaa")
        XCTAssertNil([apiOrg].firstSupportingChat())
    }

    func testPlanLabelMapping() {
        XCTAssertEqual(makeOrg(tier: "default_claude_max_20x").planLabel, "Max 20×")
        XCTAssertEqual(makeOrg(tier: "default_claude_max_5x").planLabel, "Max 5×")
        XCTAssertEqual(makeOrg(tier: "default_claude_pro").planLabel, "Pro")
        XCTAssertEqual(makeOrg(tier: "default_claude_free").planLabel, "Free")
        XCTAssertNil(makeOrg(tier: "unknown_tier").planLabel)
        XCTAssertNil(makeOrg(tier: nil).planLabel)
    }

    private func makeOrg(tier: String?) -> Organization {
        Organization(uuid: "x", name: "x", capabilities: ["chat"], rateLimitTier: tier)
    }
}
