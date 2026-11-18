# Changelog

## 0.1.1 - Unreleased

- Build signed Android APKs and a universal macOS DMG in parallel through GitHub Actions, and publish the packages to GitHub Releases after checks pass.
- Use a dedicated Android release signing key and reject release builds when signing credentials are missing.
- Cache build dependencies, validate release versions, and include package checksums and third-party notices.
- Document release configuration and installation with direct links to repository secrets, workflow runs, and downloads.
- Build Android architectures in parallel and support focused platform or architecture rebuilds as workflow artifacts.
- Cache the Android toolchain and compilation outputs, avoid competing Flutter cache writers, and report per-step build durations.
- Fix macOS architecture verification, cache Flutter's actual Swift package directory, and save prepared caches before packaging checks.

## 0.1.0 - Unreleased

- Establish a native Flutter client for one-to-one phone screen sharing over a local network.
- Add QR pairing, on-demand device discovery, explicit approval on both devices, and encrypted signaling and media transport.
- Implement Android screen and internal-audio capture, an iOS ReplayKit broadcast extension, and desktop screen and audio receivers.
- Add an optional internal-audio switch without substituting microphone capture.
- Provide English as the default interface language and support Simplified Chinese.
- Include the MIT license, English documentation, vendored native media patches, and third-party source notices.

Phone capture, internal audio, and cross-device operation still require real-device verification. Android and macOS source builds have compiled successfully; iOS, Windows, and Linux native builds remain unverified.
