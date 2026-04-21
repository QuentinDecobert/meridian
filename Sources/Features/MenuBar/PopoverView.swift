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
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        content
            .onAppear {
                Task { await quotaStore.refreshIfNeeded() }
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
                FlightDeckView(snapshot: snapshot) {
                    popoverLogger.info("Preferences opened from popover")
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "settings")
                }
            } else {
                loadingShell
            }
        case .error(let message):
            errorShell(message: message)
        case .signedOut:
            signedOutShell
        }
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
