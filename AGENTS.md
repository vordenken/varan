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
- Every new `feature/*` branch starts a new minor app version: increment the version in `semver.txt`, add fresh release notes, preserve prior version history, and align `MARKETING_VERSION` in every Xcode configuration before implementation is considered commit-ready.
- Protect system resources during tests. Run UI tests on one explicitly selected simulator with Xcode parallel testing disabled (`-parallel-testing-enabled NO`); never allow cloned or concurrent simulators for a test run. Check that no prior test runner or simulator remains before starting. A temporary CPU rise while one simulator boots is expected; stop if high load is sustained or the host becomes unresponsive. Prefer the newest installed iOS runtime for UI tests; use an older runtime only to diagnose a specific failure. Bound each UI test's execution time, inspect a failed result before retrying, and shut down the simulator after the run.
- Run the relevant local XCTest target before submitting code changes:

```bash
xcodebuild -project Varan.xcodeproj -scheme Varan \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:VaranTests CODE_SIGNING_ALLOWED=NO test
```

For iOS UI tests, select one installed simulator and keep parallel testing off:

```bash
xcodebuild -project Varan.xcodeproj -scheme Varan \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  -maximum-concurrent-test-device-destinations 1 \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 60 \
  -maximum-test-execution-time-allowance 60 \
  -only-testing:VaranUITests test
```
