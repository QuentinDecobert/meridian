# Security Policy

Meridian stores your `claude.ai` session cookie in the macOS Keychain and talks to a single third-party endpoint (`claude.ai/api/organizations/{id}/usage`). We take security reports seriously.

## Supported versions

The project is pre-1.0. Only the latest `main` branch is supported.

| Version | Supported |
| ------- | --------- |
| main    | ✅        |
| < 0.1   | ❌        |

## Reporting a vulnerability

**Please do not open a public issue for security vulnerabilities.**

Instead, report them privately via [GitHub Security Advisories](https://github.com/QuentinDecobert/meridian/security/advisories/new). This opens a private channel with the maintainers.

We will:

- Acknowledge your report within **72 hours**
- Provide an initial assessment within **7 days**
- Credit you in the advisory once a fix is published (unless you prefer to stay anonymous)

## Scope

In scope:

- Authentication / cookie handling (Keychain storage, cookie transmission)
- Data leakage (telemetry, logs, crash reports)
- Supply-chain issues (font files, build scripts, CI)
- Any bypass of `App Sandbox` or the `Hardened Runtime`

Out of scope:

- Vulnerabilities in `claude.ai` itself — report those to Anthropic
- Issues requiring privileged local access already granted by the user
- Missing defense-in-depth in an otherwise non-exploitable code path

## Disclosure philosophy

We practice coordinated disclosure. Public release of details follows the fix by at least **7 days**, unless the reporter requests a shorter embargo and the fix is shipped.
