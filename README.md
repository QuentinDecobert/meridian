# Meridian

A peripheral cockpit for builders working with Claude.

Meridian is a macOS menu bar app that displays your `claude.ai` quota in real time — percent used, time until reset, weekly limits — without breaking your flow.

---

## Who it's for

Builders — entrepreneurs, developers, designers, product managers — who use Claude Code, claude.ai or Claude for Figma daily and want to keep an eye on their consumption without switching context.

## Requirements

- macOS 13 Ventura or newer
- Xcode 15+
- Homebrew

## Installation

### One-liner

```bash
git clone https://github.com/quentindecobert/meridian.git
cd meridian
brew install xcodegen
make install
```

On first launch, macOS will block Meridian (unsigned ad-hoc build). In Finder, **right-click** on `Meridian.app` → **Open** → **Open** in the dialog. One-time step.

### Manual

```bash
git clone https://github.com/quentindecobert/meridian.git
cd meridian
brew install xcodegen
xcodegen generate
open Meridian.xcodeproj
# In Xcode: ⌘R
```

## First run

1. Click the Meridian icon in the menu bar
2. Popover → **Sign in**
3. **Sign in to claude.ai** → email + password in the embedded WKWebView
4. Close the window. Meridian will display your percent used and time until reset in the menu bar.

## Usage

- **Menu bar icon** — arc + `NN% · HhMM` updated every 5 minutes and on every Claude Code interaction
- **Click the icon** — popover with the current 5-hour session, three weekly breakdowns (All models, Sonnet only, Claude design) and a link to Settings
- **Settings** — launch at login, menu bar display (session / weekly), sign out

## Privacy & security

- Your `claude.ai` session cookie is stored in the **macOS Keychain** under your user, never on disk in plaintext
- Meridian calls **one endpoint only**: `claude.ai/api/organizations/{id}/usage` — the same one that powers the *Settings → Usage* page on claude.ai
- Zero telemetry, zero tracking, zero analytics
- Source is fully public

## Known limitations

- **Google SSO not supported** — Google blocks OAuth inside embedded macOS WebViews. Workaround: set a direct password on your `claude.ai` account and sign in with email + password.
- **Undocumented `/usage` endpoint** — may break if Anthropic changes its server-side schema. Meridian surfaces the error clearly.
- **Source-only distribution for v1** — no Developer ID–signed binary yet. Local build required.

## Architecture

- SwiftUI + `MenuBarExtra`, macOS 13+
- Swift 6 strict concurrency
- Model: `QuotaStore @MainActor` + reactive views consuming `@Published` state
- Event-driven refresh: 5-minute timer + popover open + Claude Code activity (`FSEventStream` on `~/.claude/projects/`)
- Session persisted in Keychain (`kSecClassGenericPassword`)

```
Sources/
├── App/          Entry point, MenuBarExtra, AppDelegate
├── Core/         Theme, Network, Storage (Keychain), Logging
└── Features/
    ├── Quota/    Domain: Quota, UsageWindow, QuotaStore
    ├── MenuBar/  Menu bar label + popover (Flight Deck)
    ├── Settings/ Preferences window
    └── Onboarding/ claude.ai sign-in flow
```

## Development

```bash
make generate   # regenerate Meridian.xcodeproj from project.yml
make build      # build a Release .app into build/Build/Products/Release/
make install    # build and copy Meridian.app into /Applications/
make clean      # wipe generated project and build artifacts
```

Tests live in `Tests/MeridianTests/` — run them with `xcodebuild test -scheme Meridian` or from Xcode.

## Roadmap

- [ ] Google SSO support (browser cookie import or alternative flow)
- [ ] Claude server status (fetch the status page)
- [ ] Claude Code release notes surfaced in the popover
- [ ] Notarized binary distribution (requires Apple Developer Program)
- [ ] Localizations (currently English only)

## Contributing

Issues and PRs welcome.

## License

MIT — see [LICENSE](./LICENSE).
