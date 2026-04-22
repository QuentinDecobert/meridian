import SwiftUI
import AppKit

/// Body of the popover when the user has clicked the "update available" chip.
///
/// Replaces the dashboard (hero / reset / horizon / breakdown) with :
///   · title + version bump (e.g. `0.1.4 → 0.2.0` or `0.1.4 → abc1234`)
///   · "Pulled from GitHub · N new commits since your build"
///   · runnable command (`git pull && make install`) + COPY button
///   · BACK link + `Release notes ↗` external link
///
/// Header (MERIDIAN + chip) and footer (LIVE/plan + SETTINGS) stay identical
/// to the dashboard — the panel is slotted *inside* the existing popover
/// shell so the user still sees where they are.
///
/// Visual source of truth : `designs/update-indicator-flow.html` state 3/4.
struct UpdatePanel: View {
    /// Current local marketing version (e.g. `0.1.4`). Pulled from
    /// `CFBundleShortVersionString`. Falls back to `—` if absent.
    let localVersion: String
    /// Remote version, when resolvable. When `nil`, we display the first 7
    /// characters of the remote SHA as the bump target — the user still
    /// has a useful "something changed" signal without a full semver string.
    let remoteVersion: String?
    /// First-7 SHA shown as a fallback when we don't have a remote version.
    let remoteSHA: String
    /// Number of commits on `main` ahead of the local build. `0` is a valid
    /// value (force-pushed branch, compare call failed) — we just drop the
    /// count from the subtitle then.
    let aheadCount: Int
    /// Dismiss the panel and go back to the dashboard.
    let onBack: () -> Void

    @State private var copied: Bool = false
    @State private var copyResetTask: Task<Void, Never>?

    /// Command printed in the code box. Constant — any future change should
    /// update the README too.
    private static let installCommand = "git pull && make install"

    /// Fully-qualified URL to the latest release on GitHub. Tests rely on
    /// this being a compile-time constant (no runtime format).
    private static let releaseNotesURL = URL(string: "https://github.com/QuentinDecobert/meridian/releases/latest")!

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleRow
                .padding(.top, 14)
                .padding(.horizontal, 24)

            Text(subtitle)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(MeridianColors.ink3)
                .padding(.top, 4)
                .padding(.horizontal, 24)
                .padding(.bottom, 14)

            commandLabel
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

            commandBox
                .padding(.horizontal, 24)
                .padding(.bottom, 14)

            links
                .padding(.horizontal, 24)
                .padding(.bottom, 6)
        }
        // Escape = back, matching macOS popover conventions.
        .background(
            Button("Back") { onBack() }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
                .accessibilityHidden(true)
        )
        .onDisappear {
            copyResetTask?.cancel()
        }
    }

    // MARK: - Subviews

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Update available")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(MeridianColors.ink)
            Spacer()
            Text(bumpText)
                .font(FlightDeckType.caps10)
                .tracking(1.2)
                .foregroundStyle(MeridianColors.updateBlue)
                .monospacedDigit()
        }
    }

    private var commandLabel: some View {
        Text("RUN IN YOUR MERIDIAN FOLDER")
            .font(FlightDeckType.caps10)
            .tracking(2.2)
            .foregroundStyle(MeridianColors.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var commandBox: some View {
        HStack(spacing: 0) {
            Text(Self.installCommand)
                .font(.custom("JetBrainsMono-Medium", size: 12))
                .foregroundStyle(MeridianColors.ink)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .frame(width: 1)
                .overlay(MeridianColors.hair)

            Button(action: copyCommand) {
                HStack(spacing: 5) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9, weight: .semibold))
                    Text(copied ? "COPIED" : "COPY")
                        .font(FlightDeckType.caps10)
                        .tracking(1.8)
                }
                .foregroundStyle(copied ? MeridianColors.green : MeridianColors.updateBlue)
                .padding(.horizontal, 14)
                .frame(maxHeight: .infinity)
                .background(
                    Rectangle()
                        .fill(copied
                              ? Color(hex: 0x7AC99A, alpha: 0.14)
                              : MeridianColors.updateBlueBG)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copied ? "Copied" : "Copy install command")
        }
        .frame(height: 36)
        .background(Color(hex: 0x08151E, alpha: 0.55))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(MeridianColors.hair, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var links: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .semibold))
                    Text("BACK")
                        .font(FlightDeckType.caps10)
                        .tracking(2.0)
                }
                .foregroundStyle(MeridianColors.ink3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to dashboard")

            Spacer()

            Button(action: openReleaseNotes) {
                HStack(spacing: 3) {
                    Text("Release notes")
                        .font(.system(size: 11, weight: .medium))
                    Text("↗")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(MeridianColors.updateBlue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open release notes on GitHub")
        }
    }

    // MARK: - Copy / open helpers

    private func copyCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Self.installCommand, forType: .string)

        copied = true
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            if Task.isCancelled { return }
            copied = false
        }
    }

    private func openReleaseNotes() {
        NSWorkspace.shared.open(Self.releaseNotesURL)
    }

    // MARK: - Derived text

    /// `0.1.4 → 0.2.0` when we have a remote version, otherwise `0.1.4 → abc1234`.
    private var bumpText: String {
        let target = remoteVersion ?? String(remoteSHA.prefix(7))
        return "\(localVersion) → \(target)"
    }

    /// `Pulled from GitHub · 3 new commits since your build.` — drop the
    /// count when the compare call couldn't give us one.
    private var subtitle: String {
        if aheadCount > 0 {
            let noun = aheadCount == 1 ? "commit" : "commits"
            return "Pulled from GitHub · \(aheadCount) new \(noun) since your build."
        } else {
            return "Pulled from GitHub · new commits since your build."
        }
    }
}

#Preview("UpdatePanel · default") {
    UpdatePanel(
        localVersion: "0.1.4",
        remoteVersion: "0.2.0",
        remoteSHA: "abc1234def567",
        aheadCount: 3,
        onBack: {}
    )
    .frame(width: 360)
    .background(MeridianColors.bg1)
}

#Preview("UpdatePanel · SHA fallback") {
    UpdatePanel(
        localVersion: "0.1.4",
        remoteVersion: nil,
        remoteSHA: "abc1234def567",
        aheadCount: 0,
        onBack: {}
    )
    .frame(width: 360)
    .background(MeridianColors.bg1)
}

#Preview("UpdatePanel · single commit") {
    UpdatePanel(
        localVersion: "0.1.4",
        remoteVersion: "0.1.5",
        remoteSHA: "abc1234def567",
        aheadCount: 1,
        onBack: {}
    )
    .frame(width: 360)
    .background(MeridianColors.bg1)
}
