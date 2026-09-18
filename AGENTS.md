# AGENTS.md

Guidance for coding agents working on Varan.

- Write code, identifiers, comments, documentation, and Gherkin features in English.
- Keep the shared SwiftUI app compatible with iOS, iPadOS, and macOS.
- Never log credentials or persist them outside the system Keychain.
- Keep external server connections on HTTPS; HTTP is permitted only for local addresses.
- Preserve the placeholder `de.example.*` bundle identifiers and do not add personal signing settings to the project file. Local signing belongs in the ignored `Configuration/Developer.xcconfig` file.
- Do not add GitHub Actions, CI builds, release automation, or third-party dependencies without explicit maintainer approval.
- Add user-facing strings to `Varan/Resources/Localizable.xcstrings` in English and German; English is the fallback language.
- Run the relevant local XCTest target before submitting code changes:

```bash
xcodebuild -project Varan.xcodeproj -scheme Varan \
  -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test
```
