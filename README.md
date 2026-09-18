# Varan - Companion for Komodo

Varan is an independent native client for self-hosted Komodo instances
on iPhone, iPad, and Mac.

> This project is not affiliated with or endorsed by the Komodo project. It does
> not use upstream trademarks, brand assets, or source code.

## Current Status

The current MVP includes:

- a shared SwiftUI target for iOS, iPadOS, and macOS;
- persistent server profiles with adaptive profile navigation;
- a secure connection editor for API key or JWT authentication;
- HTTPS validation with a limited HTTP exception for local addresses;
- searchable, refreshable, and paginated stack listings;
- stack details with service and container states;
- confirmed start and stop actions for stacks and individual services;
- searchable, selectable, automatically refreshed logs;
- an actor-isolated `URLSession` client for read and execute requests;
- distinct messages for invalid tokens, offline states, and timeouts;
- an actor-isolated Keychain abstraction; and
- unit tests for URL, authentication, request, decoding, and error handling.

Credentials are never logged and are stored exclusively in the system Keychain.
SwiftData stores only the display name, server address, authentication type, and a
non-secret Keychain reference.

## Requirements

- Xcode 27 or later
- Swift 6
- iOS/iPadOS 18 or macOS 15 minimum deployment target

Before creating a signed build, replace the placeholder bundle identifier
`de.example.Varan` in the Xcode project and select your own development
team.

## Local Signing

Unsigned tests and simulator builds work without a development team. For local
signing, copy `Configuration/Developer.xcconfig.example` to
`Configuration/Developer.xcconfig` and replace `YOUR_TEAM_ID` with your Apple
Development Team ID. The local file is ignored by Git and applies to the app and
test targets.

## Build and Test Locally

```bash
xcodebuild \
  -project Varan.xcodeproj \
  -scheme Varan \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test

xcodebuild \
  -project Varan.xcodeproj \
  -scheme Varan \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Binary distribution and App Store uploads are performed locally through Xcode.
This repository intentionally has no GitHub build or release automation.

## Localization

Varan follows the system language. German and English are maintained in
`Varan/Resources/Localizable.xcstrings`; unsupported languages fall back to
English. Add every new user-facing string to this catalog. System permission
texts are maintained separately in `Varan/Resources/{en,de}.lproj/InfoPlist.strings`.

## Generate the App Icon

The generator uses only macOS system frameworks and writes all iOS, Dark, Tinted,
and macOS variants to the asset catalog:

```bash
xcrun swift Scripts/generate-app-icon.swift
```

## License

Varan is licensed under the GNU General Public License v3.0 only. See
[LICENSE](LICENSE) for details.
