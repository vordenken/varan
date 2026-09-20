# AGENTS.md

Guidance for coding agents working on Varan.

- Write code, identifiers, comments, documentation, and Gherkin features in English.
- Keep the shared SwiftUI app compatible with iOS, iPadOS, and macOS.
- Never log credentials or persist them outside the system Keychain.
- Keep external server connections on HTTPS; HTTP is permitted only for local addresses.
- Preserve Komodo's API semantics: use `/read` for queries, `/write` for configuration mutations, and `/execute` for runtime actions. Prefer typed requests and partial update payloads, and reload canonical server state after every successful mutation.
- Treat container configuration as part of its owning stack. Do not model an ephemeral Docker container as an independent configuration source.
- Preserve the placeholder `de.example.*` bundle identifiers and do not add personal signing settings to the project file. Local signing belongs in the ignored `Configuration/Developer.xcconfig` file.
- Do not add GitHub Actions, CI builds, release automation, or third-party dependencies without explicit maintainer approval.
- Add user-facing strings to `Varan/Resources/Localizable.xcstrings` in English and German; English is the fallback language.
- Keep `main` stable. Make changes on a focused `feature/<short-kebab-name>` branch and open pull requests against `main`.
- Treat `semver.txt` as the source of truth for the planned app version and current release notes. Preserve its history and keep Xcode's `MARKETING_VERSION` aligned when intentionally changing versions.
- Run the relevant local XCTest target before submitting code changes:

```bash
xcodebuild -project Varan.xcodeproj -scheme Varan \
  -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test
```
