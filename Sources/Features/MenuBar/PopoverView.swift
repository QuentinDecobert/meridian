import SwiftUI
import AppKit
import OSLog

private let popoverLogger = Logger(subsystem: "com.quentindecobert.meridian", category: "popover")

/// Root popover content — dispatches on `QuotaStore.state` and renders either
/// the Flight Deck (when data is loaded) or one of the non-loaded states
/// (loading, error, signed out).
///
/// The Flight Deck itself lives in `FlightDeckView.swift`. This file's only
/// job is state dispatch + non-loaded fallbacks.
struct PopoverView: View {
    @EnvironmentObject var quotaStore: QuotaStore
    @EnvironmentObject var updateChecker: UpdateChecker
    @EnvironmentObject var statusChecker: StatusChecker
    @Environment(\.openWindow) private var openWindow

    /// Local swap toggle — whether the user is currently looking at the
    /// update detail panel or the dashboard. Not persisted: reopening the
    /// popover always lands on the dashboard, per the interaction spec.
    @State private var isShowingUpdateDetail: Bool = false

    var body: some View {
        content
            .onAppear {
                Task { await quotaStore.refreshIfNeeded() }
            }
            .onChange(of: isAvailable) { newValue in
                // If the update status flips away from .available while the
                // user is still on the detail panel (e.g. they just ran the
                // install and the next check matches), return to the
                // dashboard silently.
                if !newValue { isShowingUpdateDetail = false }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch quotaStore.state {
        case .initial, .loading:
            loadingShell
        case .loaded(let quota):
            if let snapshot = FlightDeckAdapter.snapshot(
                from: quota,
                now: .now,
                isLive: !quotaStore.hasTransientError
            ) {
                FlightDeckView(
                    snapshot: snapshot,
                    onOpenSettings: openSettings,
                    updateContext: updateContext,
                    statusContext: statusContext
                )
            } else {
                loadingShell
            }
        case .error(let message):
            // Bonus wire : when the quota fetch is failing AND the status
            // feed says Claude API is in a major outage, we trade the
            // generic error shell for a FlightDeckView that spells out the
            // correlation. This preserves the header chip / status section
            // the user already trusts and makes it obvious that the
            // missing data is not Meridian's fault.
            if statusChecker.status.isClaudeAPIMajorOutage {
                FlightDeckView(
                    snapshot: blockedSnapshot,
                    onOpenSettings: openSettings,
                    statusContext: statusContext,
                    bonusWireContext: .init(
                        lastRefreshedAt: quotaStore.lastSuccessfulRefreshAt
                    )
                )
            } else {
                errorShell(message: message)
            }
        case .signedOut:
            signedOutShell
        }
    }

    /// Shared `onOpenSettings` closure used by both the normal and the
    /// bonus-wire Flight Deck branches. Centralising it avoids repeating
    /// the NSApp activation + openWindow dance twice.
    private func openSettings() {
        popoverLogger.info("Preferences opened from popover")
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "settings")
    }

    /// Placeholder snapshot used as the carrier for the bonus-wire branch.
    /// The bonus-wire dashboard body never reads the quota / session fields
    /// (hero / reset / horizon / breakdown are all hidden) — we still need
    /// a value because the footer and header pull `capturedAt` and
    /// `heroStatus` from it. `.unused` keeps the header pip quiet (no
    /// amber / red pulse competing with the red chip).
    private var blockedSnapshot: FlightDeckSnapshot {
        let zeroWindow = SessionWindow(
            startedAt: .now,
            resetsAt: .now,
            percent: 0
        )
        return FlightDeckSnapshot(
            allModels:    QuotaBreakdown(name: "All models",  used: 0, total: 1, percent: 0),
            sonnet:       QuotaBreakdown(name: "Sonnet only", used: 0, total: 1, percent: 0),
            claudeDesign: QuotaBreakdown(name: "Claude design", used: 0, total: 1, percent: 0),
            session: zeroWindow,
            planLabel: "PLAN MAX",
            isLive: false,
            capturedAt: .now
        )
    }

    // MARK: - Update wiring

    /// `true` iff the checker currently has an `.available(...)` status.
    private var isAvailable: Bool {
        if case .available = updateChecker.status { return true }
        return false
    }

    /// Build the update context handed to `FlightDeckView`. Returns `nil`
    /// when no update is available — the Flight Deck then renders the
    /// normal timestamped header.
    private var updateContext: FlightDeckView.UpdateContext? {
        guard case .available(let remoteSHA, let ahead, let remoteVersion) = updateChecker.status else {
            return nil
        }
        let local = localMarketingVersion
        return FlightDeckView.UpdateContext(
            chipTitle: chipTitle(remoteVersion: remoteVersion),
            isShowingDetail: isShowingUpdateDetail,
            panelBuilder: {
                UpdatePanel(
                    localVersion: local,
                    remoteVersion: remoteVersion,
                    remoteSHA: remoteSHA,
                    aheadCount: ahead,
                    onBack: { self.isShowingUpdateDetail = false }
                )
            },
            onToggleDetail: { isShowingUpdateDetail.toggle() }
        )
    }

    /// `V0.2.0 AVAILABLE` when a version string is known, otherwise just
    /// `UPDATE AVAILABLE` — never ship a meaningless placeholder.
    private func chipTitle(remoteVersion: String?) -> String {
        if let remoteVersion { return "V\(remoteVersion) AVAILABLE" }
        return "UPDATE AVAILABLE"
    }

    /// `CFBundleShortVersionString` — local app version. Fallback `—` keeps
    /// the layout stable if the key is ever missing.
    private var localMarketingVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
    }

    // MARK: - Status wiring

    /// Build the status context handed to `FlightDeckView`. Returns `nil`
    /// when the status is `.allClear` / `.unknown` — the Flight Deck then
    /// preserves its existing header/footer behaviour.
    private var statusContext: FlightDeckView.StatusContext? {
        guard case .degraded = statusChecker.status else { return nil }
        return FlightDeckView.StatusContext(status: statusChecker.status)
    }

    // MARK: - Non-Flight-Deck fallback shells
    // These intentionally share the Flight Deck's width & corner treatment
    // so the popover never jumps when the state changes.

    private var loadingShell: some View {
        FallbackFrame {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading…")
                    .font(FlightDeckType.caps11)
                    .tracking(2.2)
                    .foregroundStyle(MeridianColors.ink3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading quota")
        }
    }

    private func errorShell(message: String) -> some View {
        FallbackFrame {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    StatusGlyph(status: .watch, size: 11, color: MeridianColors.amber)
                    Text("ERROR")
                        .font(FlightDeckType.caps10)
                        .tracking(2.2)
                        .foregroundStyle(MeridianColors.amber)
                }
                Text(message)
                    .font(FlightDeckType.rowName)
                    .foregroundStyle(MeridianColors.ink)
                Button("Retry") {
                    Task { await quotaStore.refresh() }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(24)
        }
    }

    private var signedOutShell: some View {
        FallbackFrame {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    StatusGlyph(status: .unused, size: 11, color: MeridianColors.ink2)
                    Text("NOT SIGNED IN")
                        .font(FlightDeckType.caps10)
                        .tracking(2.2)
                        .foregroundStyle(MeridianColors.ink3)
                }
                Text("Connect your claude.ai account to display your quota.")
                    .font(FlightDeckType.rowName)
                    .foregroundStyle(MeridianColors.ink)
                Button("Sign in") {
                    popoverLogger.info("Sign-in button clicked")
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "onboarding")
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityHint("Opens the claude.ai sign-in window")
            }
            .padding(24)
        }
    }
}

/// Shared framing for the non-Flight-Deck states so the popover keeps its
/// shape (360 pt wide · rounded · ivory-on-teal gradient · corner ticks).
private struct FallbackFrame<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(width: 360)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0x0C1E1C, alpha: 0.97),
                                Color(hex: 0x0A1715, alpha: 0.97),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(MeridianColors.hair, lineWidth: 1)
            )
            .overlay(
                CornerTicks()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            )
            .shadow(color: .black.opacity(0.45), radius: 30, x: 0, y: 14)
    }
}
