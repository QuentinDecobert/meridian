# Contributing to Meridian

Thanks for wanting to help. This document covers the essentials.

## Prerequisites

- macOS 13 Ventura or newer
- Xcode 15+
- [Homebrew](https://brew.sh)
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

## Getting started

```bash
git clone https://github.com/QuentinDecobert/meridian.git
cd meridian
xcodegen generate
open Meridian.xcodeproj
```

`Meridian.xcodeproj` is generated from `project.yml` by `xcodegen` — **do not edit it by hand** and **do not commit it**. It is intentionally gitignored.

## Building and testing

| Command            | What it does                                              |
| ------------------ | --------------------------------------------------------- |
| `make generate`    | Regenerate `Meridian.xcodeproj` from `project.yml`        |
| `make build`       | Release build into `build/Build/Products/Release/`        |
| `make install`     | Build and copy `Meridian.app` into `/Applications/`       |
| `make run-debug`   | Debug build + launch — exposes the in-app Debug panel     |
| `make clean`       | Wipe generated project and build artefacts                |

Run the tests from Xcode (`⌘U`) or from the command line:

```bash
xcodebuild test -scheme Meridian -destination 'platform=macOS'
```

### Visually validating the Claude status feature

Debug builds expose a **Debug** section in the Settings window (`⌘,`) that lets you force each `ClaudeStatus` state without waiting for a real incident on `status.claude.com` :

- **Mock Claude status** picker — cycle through `None (live data)`, `Degraded (API)`, `Partial outage (Code)`, `Major outage (API)`, `Under maintenance (API)`
- **Force quota fetch error** toggle — combined with `Major outage (API)`, this triggers the full "API is down — that's why" bonus wire (red banner, stale footer)

The panel is gated by `#if DEBUG` so it's **entirely stripped from Release builds** (`make build` / `make install`). Contributors validating a PR that touches `StatusChip`, `StatusSection`, the menu bar pip, or any status wiring should use `make run-debug` and walk through the picker.

## Coding conventions

- **Language**: Swift 6, strict concurrency (`SWIFT_STRICT_CONCURRENCY=complete`). Warnings are errors.
- **Architecture**: `@MainActor` `ObservableObject` stores + reactive SwiftUI views. Keep networking in `Core/Network/`, storage in `Core/Storage/`, domain in `Features/*/`.
- **No force-unwraps** outside of constants known at compile time.
- **No force-try**. Handle errors or propagate them.
- **Naming**: Swift API Design Guidelines.
- **Comments in English**, focused on *why*, not *what*. Skip them if the name already says it.

## Commit messages

Prefix with scope in parentheses, imperative mood:

```
feat(popover): add session horizon band
fix(quota): handle 429 retry-after properly
chore(fonts): drop 18 unused weights
docs(readme): clarify first-run instructions
a11y(ui): add VoiceOver labels on popover
perf(refresh): dedupe overlapping refresh tasks
```

Common prefixes: `feat`, `fix`, `refactor`, `perf`, `a11y`, `chore`, `docs`, `test`.

## Pull requests

1. Fork the repo and create a feature branch from `main`.
2. Write tests for behavior you can.
3. Run `make build` and the test suite locally before opening the PR.
4. Fill in the PR template — it keeps review fast.
5. One logical change per PR. Split big work into stacked PRs.

The CI will run a build + tests on every push to the PR. Both must be green before merge.

## Cutting a release

Releases are published manually from a maintainer's machine — no CI workflow. The `release` target in the `Makefile` handles the full cut.

> **Why tagging matters.** Meridian ships an in-app update indicator that pings `GET /repos/.../releases/latest` every few hours. **If you never tag a release, no user sees any update notification — ever.** Commits pushed to `main` without a tag are invisible to the feature. So every time you ship something a user would care about (new feature, bug fix, UX tweak), cut a release.

### When to cut — semver in this project

| Bump  | Example         | When to use                                                                                      |
| ----- | --------------- | ------------------------------------------------------------------------------------------------ |
| PATCH | `0.2.0 → 0.2.1` | Bug fix, copy change, small UX tweak, security hardening with no user-visible change             |
| MINOR | `0.2.1 → 0.3.0` | New feature, new UI surface, non-breaking behavior change                                        |
| MAJOR | `0.3.0 → 1.0.0` | Reserved for the first Developer ID-signed/notarized release, or any breaking setup/config change |

Rule of thumb : if a user running `git pull && make install` would notice the difference, cut a release.

### How to cut

Prerequisites : [`gh`](https://cli.github.com) (`brew install gh` then `gh auth login`) and a clean working copy on `main`.

```bash
make release VERSION=0.2.1
```

This :

1. Bumps `MARKETING_VERSION` in `project.yml` and regenerates `Meridian.xcodeproj`
2. Commits `chore(release): v0.2.1`
3. Creates an annotated tag `v0.2.1`
4. Pushes the commit and the tag to `origin/main`
5. Creates the GitHub release with auto-generated notes (`gh release create v0.2.1 --generate-notes`)

Version numbers follow semver (`MAJOR.MINOR.PATCH`, no leading `v` — the tag adds it). The target aborts early if `VERSION` is missing, malformed, `gh` is not installed, the working copy is dirty, or the tag already exists. Nothing is pushed until every local step has succeeded.

### After the release

- Check the release page : `https://github.com/QuentinDecobert/meridian/releases/latest`
- Edit the auto-generated notes if useful (context, migration steps). The content users see in the `Release notes ↗` link is whatever is on GitHub — keep it terse.
- Users running older builds will see the update chip within ~4 hours (next poll cycle) or immediately on their next app launch.

## Opening an issue

- Use the **Bug report** template if something is broken.
- Use the **Feature request** template to propose a new behavior.
- For security issues, see [`SECURITY.md`](./SECURITY.md) — do not open a public issue.

## License

By contributing, you agree that your contributions will be licensed under the MIT license of the project.
