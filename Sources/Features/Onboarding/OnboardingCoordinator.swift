import Foundation
import Combine

@MainActor
final class OnboardingCoordinator: ObservableObject {
    enum State: Equatable {
        case intro
        case webLogin
        case processing
        case success
        case failure(message: String)
    }

    @Published private(set) var state: State = .intro

    private let sessionStore: any SessionStoring
    private let organizationsClient: any OrganizationsFetching

    init(
        sessionStore: any SessionStoring = SessionStore(),
        organizationsClient: any OrganizationsFetching = OrganizationsAPIClient()
    ) {
        self.sessionStore = sessionStore
        self.organizationsClient = organizationsClient
    }

    func startWebLogin() {
        state = .webLogin
    }

    func cancel() {
        state = .intro
    }

    func handleCapturedCookie(_ cookie: String) async {
        state = .processing

        do {
            let organizations = try await organizationsClient.fetchOrganizations(cookie: cookie)

            guard let chatOrg = organizations.firstSupportingChat() else {
                state = .failure(message: "Ce compte ne dispose pas d'un abonnement claude.ai actif.")
                return
            }

            let session = Session(cookie: cookie, organizationUUID: chatOrg.uuid)
            try sessionStore.save(session)
            state = .success
        } catch {
            state = .failure(message: "Unable to finalize connection: \(error.localizedDescription)")
        }
    }
}
