import Foundation
import Combine
import OSLog

private let logger = Logger(subsystem: "com.quentindecobert.meridian", category: "onboarding")

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

    func handleCapturedCookie(_ cookie: SessionCookie) async {
        state = .processing

        do {
            let organizations = try await organizationsClient.fetchOrganizations(cookie: cookie)

            guard let chatOrg = organizations.firstSupportingChat() else {
                state = .failure(message: "Ce compte ne dispose pas d'un abonnement claude.ai actif.")
                return
            }

            let session = Session(cookie: cookie.rawValue, organizationUUID: chatOrg.uuid)
            try sessionStore.save(session)
            state = .success
        } catch let apiError as APIError {
            // Technical detail stays in the logs; UI gets a redacted message
            // (MER-SEC-004).
            logger.error("Onboarding failed: \(String(describing: apiError), privacy: .private)")
            state = .failure(message: apiError.userFacingMessage)
        } catch {
            logger.error("Onboarding failed: \(String(describing: error), privacy: .private)")
            state = .failure(message: "Unable to finalize connection. Please try again.")
        }
    }
}
