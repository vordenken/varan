# Building Varan

Varan is a shared SwiftUI app for iOS, iPadOS, and macOS. Signed public builds
are not available yet, but the project can be built locally with Xcode.

## Requirements

- Xcode 27 or later
- Swift 6
- macOS 15 or later for Mac builds
- iOS or iPadOS 18 or later for device builds
- Access to a Komodo instance

## Open the project

Clone the repository and open `Varan.xcodeproj` in Xcode. Unsigned tests and
simulator builds do not require an Apple Development team.

## Local signing

To run Varan on a physical device or create a signed local build:

1. Copy `Configuration/Developer.xcconfig.example` to
   `Configuration/Developer.xcconfig`.
2. Replace `YOUR_TEAM_ID` with your Apple Development Team ID.
3. Select an appropriate signing certificate in Xcode if necessary.

`Configuration/Developer.xcconfig` is ignored by Git and applies to both the
app and test targets. Do not commit personal team identifiers, certificates, or
provisioning settings.

The project intentionally uses the placeholder bundle identifier
`de.example.Varan`. Replace it in your local configuration before distributing
your own build.

## Build from the command line

Build the Mac app without code signing:

```bash
xcodebuild \
  -project Varan.xcodeproj \
  -scheme Varan \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Build for the iOS Simulator:

```bash
xcodebuild \
  -project Varan.xcodeproj \
  -scheme Varan \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Run tests

Run the shared test target on macOS:

```bash
xcodebuild \
  -project Varan.xcodeproj \
  -scheme Varan \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Run the test target in an installed iOS Simulator:

```bash
xcodebuild \
  -project Varan.xcodeproj \
  -scheme Varan \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  test
```

Substitute an installed simulator and OS version when necessary. Keep simulator
ad-hoc signing enabled so Keychain tests run with valid app entitlements.

## App icon assets

Regenerate the app icon variants with the macOS system frameworks:

```bash
xcrun swift Scripts/generate-app-icon.swift
```

## Distribution

Binary distribution and App Store uploads are intentionally performed locally
through Xcode. The repository does not include CI, signing, or release
automation.
