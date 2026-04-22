import SwiftUI
import OSLog
@preconcurrency import WebKit

private let logger = Logger(subsystem: "com.quentindecobert.meridian", category: "onboarding")

struct WebLoginView: NSViewRepresentable {
    let onCookieCaptured: @MainActor (String) -> Void

    static let loginURL = URL(string: "https://claude.ai/login")!

    /// Host must be exactly `claude.ai` or a strict subdomain thereof.
    /// `hasSuffix("claude.ai")` alone would match `evil-claude.ai` — this
    /// helper is the single place that encodes the allowlist (MER-SEC-006).
    nonisolated static func isClaudeAIHost(_ host: String?) -> Bool {
        guard let host else { return false }
        return host == "claude.ai" || host.hasSuffix(".claude.ai")
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Use an ephemeral data store so cookies, cache, localStorage and
        // service workers only live in RAM for the lifetime of the WebView.
        // The login cookie is extracted via `httpCookieStore.getAllCookies`
        // and handed to `SessionStore` (Keychain) — no reason to leave a
        // second latent copy of it in `~/Library/WebKit/...` on disk
        // (MER-SEC-003). As a bonus, `QuotaStore.signOut()` genuinely wipes
        // the WebView state: no resurrection of a stale cookie on next login.
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.attach(to: webView)
        webView.load(URLRequest(url: Self.loginURL))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCookieCaptured: onCookieCaptured)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onCookieCaptured: @MainActor (String) -> Void
        private var didCapture = false
        private var urlObservation: NSKeyValueObservation?
        private weak var webView: WKWebView?

        init(onCookieCaptured: @escaping @MainActor (String) -> Void) {
            self.onCookieCaptured = onCookieCaptured
            super.init()
        }

        func attach(to webView: WKWebView) {
            self.webView = webView

            urlObservation = webView.observe(\.url, options: [.new]) { [weak self] observedWebView, _ in
                MainActor.assumeIsolated {
                    self?.checkURLAndCookies(on: observedWebView)
                }
            }
        }

        func detach() {
            urlObservation?.invalidate()
            urlObservation = nil
        }

        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor [weak self] in
                self?.checkURLAndCookies(on: webView)
            }
        }

        private func checkURLAndCookies(on webView: WKWebView) {
            guard !didCapture,
                  let url = webView.url,
                  WebLoginView.isClaudeAIHost(url.host)
            else { return }

            let path = url.path
            guard path != "/login",
                  !path.hasPrefix("/auth"),
                  !path.hasPrefix("/oauth"),
                  !path.hasPrefix("/signup")
            else { return }

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                Task { @MainActor [weak self] in
                    self?.handleCookies(cookies)
                }
            }
        }

        private func handleCookies(_ cookies: [HTTPCookie]) {
            guard !didCapture else { return }

            let claudeCookies = cookies.filter {
                // HTTPCookie.domain often ships with a leading dot (e.g.
                // `.claude.ai`). Strip it before comparing so a cookie with
                // domain `attacker-claude.ai` would be rejected.
                let rawDomain = $0.domain.hasPrefix(".") ? String($0.domain.dropFirst()) : $0.domain
                return WebLoginView.isClaudeAIHost(rawDomain)
            }
            guard !claudeCookies.isEmpty else { return }

            didCapture = true
            detach()

            let header = claudeCookies
                .map { "\($0.name)=\($0.value)" }
                .joined(separator: "; ")
            onCookieCaptured(header)
        }
    }
}

// MARK: - Navigation allowlist (MER-SEC-006)

/// Block any navigation that leaves `claude.ai`. The onboarding flow only
/// needs email + password on claude.ai itself; Google SSO is already out of
/// scope (see scope doc). Restricting the allowlist here stops a compromised
/// upstream from bouncing the WebView through arbitrary third-party domains
/// where it could leak cookies, fingerprint the client, or serve malicious
/// JS.
///
/// Implemented as an extension because the optional `WKNavigationDelegate`
/// requirement `webView(_:decidePolicyFor:decisionHandler:)` overlaps in
/// Swift 6 strict concurrency with the newer async `webView(_:decidePolicyFor:)`
/// variant; keeping the method out of the main class declaration avoids the
/// "nearly matches optional requirement" diagnostic that is otherwise
/// promoted to an error by `SWIFT_TREAT_WARNINGS_AS_ERRORS`.
extension WebLoginView.Coordinator {
    nonisolated func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        // `WKNavigationAction` is `Sendable` but its `request` property is
        // declared `@MainActor`. WebKit invokes this delegate on the main
        // thread in practice, so `MainActor.assumeIsolated` is safe and
        // keeps the decision synchronous (critical for the URL to be
        // blocked *before* the network request goes out).
        MainActor.assumeIsolated {
            let url = navigationAction.request.url
            if url?.absoluteString == "about:blank" {
                decisionHandler(.allow)
                return
            }
            if WebLoginView.isClaudeAIHost(url?.host) {
                decisionHandler(.allow)
                return
            }
            // `.private` on the URL — we don't want to leak an eventual
            // attacker-controlled redirect target into centralised logs.
            logger.warning("Blocked WebView navigation outside claude.ai: \(url?.absoluteString ?? "<nil>", privacy: .private)")
            decisionHandler(.cancel)
        }
    }
}
