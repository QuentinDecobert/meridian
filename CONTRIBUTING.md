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

| Command          | What it does                                              |
| ---------------- | --------------------------------------------------------- |
| `make generate`  | Regenerate `Meridian.xcodeproj` from `project.yml`        |
| `make build`     | Release build into `build/Build/Products/Release/`        |
| `make install`   | Build and copy `Meridian.app` into `/Applications/`       |
| `make clean`     | Wipe generated project and build artefacts                |

Run the tests from Xcode (`⌘U`) or from the command line:

```bash
xcodebuild test -scheme Meridian -destination 'platform=macOS'
```

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

Prerequisites : [`gh`](https://cli.github.com) (`brew install gh` then `gh auth login`) and a clean working copy on `main`.

```bash
make release VERSION=0.2.0
```

This :

1. Bumps `MARKETING_VERSION` in `project.yml` and regenerates `Meridian.xcodeproj`
2. Commits `chore(release): v0.2.0`
3. Creates an annotated tag `v0.2.0`
4. Pushes the commit and the tag to `origin/main`
5. Creates the GitHub release with auto-generated notes (`gh release create v0.2.0 --generate-notes`)

Version numbers follow semver (`MAJOR.MINOR.PATCH`, no leading `v` — the tag adds it). The target aborts early if `VERSION` is missing, malformed, `gh` is not installed, the working copy is dirty, or the tag already exists. Nothing is pushed until every local step has succeeded.

## Opening an issue

- Use the **Bug report** template if something is broken.
- Use the **Feature request** template to propose a new behavior.
- For security issues, see [`SECURITY.md`](./SECURITY.md) — do not open a public issue.

## License

By contributing, you agree that your contributions will be licensed under the MIT license of the project.
