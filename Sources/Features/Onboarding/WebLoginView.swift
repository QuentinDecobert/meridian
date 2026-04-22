import SwiftUI
@preconcurrency import WebKit

struct WebLoginView: NSViewRepresentable {
    let onCookieCaptured: @MainActor (String) -> Void

    static let loginURL = URL(string: "https://claude.ai/login")!

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
                  let host = url.host,
                  host.hasSuffix("claude.ai")
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

            let claudeCookies = cookies.filter { $0.domain.hasSuffix("claude.ai") }
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
