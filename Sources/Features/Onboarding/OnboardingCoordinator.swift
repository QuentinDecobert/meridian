import Foundation
import Combine
import OSLog

private let logger = Logger(subsystem: "com.quentindecobert.meridian", category: "onboarding")

@MainActor
final class OnboardingCoordinator: ObservableObject {
    /// Onboarding flow states. The flow is optional at each step : the user
    /// can skip claude.ai sign-in, skip the Admin Key, and still reach
    /// `.success` — Meridian just shows nothing in the popover until they
    /// add at least one connection from Settings.
    enum State: Equatable {
        case intro
        case webLogin
        case processing
        /// The claude.ai connection either succeeded or was skipped — we
        /// now prompt the user to (optionally) paste an Anthropic Admin
        /// Key. Skippable, leads straight to `.success`.
        case adminKeyPrompt
        case success
        case failure(message: String)
    }

    @Published private(set) var state: State = .intro

    private let sessionStore: any SessionStoring
    private let organizationsClient: any OrganizationsFetching
    private let adminKeyStore: any AnthropicAdminKeyStoring

    init(
        sessionStore: any SessionStoring = SessionStore(),
        organizationsClient: any OrganizationsFetching = OrganizationsAPIClient(),
        adminKeyStore: any AnthropicAdminKeyStoring = AnthropicAdminKeyStore()
    ) {
        self.sessionStore = sessionStore
        self.organizationsClient = organizationsClient
        self.adminKeyStore = adminKeyStore
    }

    func startWebLogin() {
        state = .webLogin
    }

    func cancel() {
        state = .intro
    }

    /// Skip the claude.ai step and move directly to the Admin Key prompt.
    /// Matches the "each connection is optional" onboarding spec.
    func skipClaudeAI() {
        state = .adminKeyPrompt
    }

    /// Skip the Admin Key step — the user can always add it later from
    /// Settings. Lands on `.success` so the window can close itself.
    func skipAdminKey() {
        state = .success
    }

    /// Persist the pasted Admin Key (stripped / trimmed) to the Keychain
    /// and advance to `.success`. Returns on the `.adminKeyPrompt` state
    /// with an error banner when the save fails (Keychain denied, disk
    /// full — rare but surfaced clearly).
    func saveAdminKey(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .failure(message: "Paste your Admin Key or tap Skip.")
            return
        }
        do {
            try adminKeyStore.saveKey(trimmed)
            state = .success
        } catch {
            logger.error("Admin key save failed: \(String(describing: error), privacy: .private)")
            state = .failure(message: "Couldn't save the key to Keychain. Please try again.")
        }
    }

    func handleCapturedCookie(_ cookie: SessionCookie) async {
        state = .processing

        do {
            let organizations = try await organizationsClient.fetchOrganizations(cookie: cookie)

            guard let chatOrg = organizations.firstSupportingChat() else {
                state = .failure(message: "This account has no active claude.ai subscription.")
                return
            }

            let session = Session(cookie: cookie.rawValue, organizationUUID: chatOrg.uuid)
            try sessionStore.save(session)
            // claude.ai is now connected — the flow proceeds to the Admin
            // Key step, not straight to success, so the user sees both
            // connection options even when they entered via the subscription
            // path first.
            state = .adminKeyPrompt
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
