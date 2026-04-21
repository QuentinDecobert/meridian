import Foundation

protocol UsageFetching: Sendable {
    func fetchUsage(organizationUUID: String, cookie: String) async throws -> UsageResponse
}

struct UsageAPIClient: UsageFetching {
    let apiClient: any APIClient

    init(apiClient: any APIClient = URLSessionAPIClient()) {
        self.apiClient = apiClient
    }

    func fetchUsage(organizationUUID: String, cookie: String) async throws -> UsageResponse {
        let url = URL(string: "https://claude.ai/api/organizations/\(organizationUUID)/usage")!
        return try await apiClient.get(url, cookie: cookie)
    }
}
