import Foundation

protocol OrganizationsFetching: Sendable {
    func fetchOrganizations(cookie: String) async throws -> [Organization]
}

struct OrganizationsAPIClient: OrganizationsFetching {
    static let endpoint = URL(string: "https://claude.ai/api/organizations")!

    let apiClient: any APIClient

    init(apiClient: any APIClient = URLSessionAPIClient()) {
        self.apiClient = apiClient
    }

    func fetchOrganizations(cookie: String) async throws -> [Organization] {
        try await apiClient.get(Self.endpoint, cookie: cookie)
    }
}

extension Array where Element == Organization {
    func firstSupportingChat() -> Organization? {
        first(where: { $0.supportsChat })
    }
}
