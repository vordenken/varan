# Contributing to Varan

Varan is currently a development preview. Contributions are welcome, but the
project does not yet publish signed builds or automated releases.

## Branches

- Keep `main` stable and work on a branch created from the latest `main`.
- Use `feature/<short-kebab-name>` for features, fixes, documentation, and other
  planned changes.
- Keep a branch focused on one coherent change and open its pull request against
  `main`.
- Do not commit directly to `main`.

For example:

```bash
git switch main
git pull --ff-only
git switch -c feature/accessibility
```

## Versions and release notes

`semver.txt` is the source of truth for the planned app version and its release
notes. Its format follows this structure:

```text
0.2.0
---
### What's New
- Current release note

## 0.1.0
- Previous release history
```

- Line 1 must be a strict `X.Y.Z` semantic version.
- `---` starts the notes for the current version.
- Preserve previous versions below headings such as `## 0.1.0`.
- Use a patch increment for compatible fixes, a minor increment for compatible
  features, and a major increment for incompatible changes.
- Keep `MARKETING_VERSION` in the Xcode project aligned when intentionally
  changing the version in `semver.txt`.
- Do not change the version merely to create another development build.

Varan has no release automation yet. Adding CI, signing, distribution, or release
workflows requires explicit maintainer approval.

## Testing

Before opening a pull request, run:

```bash
xcodebuild -project Varan.xcodeproj -scheme Varan \
  -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test

xcodebuild -project Varan.xcodeproj -scheme Varan \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' test
```

The macOS suite runs without signing. Keep simulator ad-hoc signing enabled so
the Keychain tests execute with valid application entitlements. Substitute an
installed iPhone simulator and OS version when necessary.

Include screenshots or a short recording for visible interface changes.
