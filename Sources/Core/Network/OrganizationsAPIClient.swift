import Foundation

protocol OrganizationsFetching: Sendable {
    func fetchOrganizations(cookie: SessionCookie) async throws -> [Organization]
}

struct OrganizationsAPIClient: OrganizationsFetching {
    let apiClient: any APIClient

    init(apiClient: any APIClient = URLSessionAPIClient()) {
        self.apiClient = apiClient
    }

    func fetchOrganizations(cookie: SessionCookie) async throws -> [Organization] {
        try await apiClient.get(ClaudeAIEndpoints.organizations, cookie: cookie)
    }
}

extension Array where Element == Organization {
    func firstSupportingChat() -> Organization? {
        first(where: { $0.supportsChat })
    }
}
