# Changelog

## 0.1.4 - Unreleased

- Check published GitHub Releases from the application and display the installed and latest versions.
- Download Android updates with progress and verify their checksum, package identity, version code, and signing certificate before opening the system installer.
- Keep the macOS application sandbox enabled and use Sparkle for signed update downloads, installation, and relaunch.
- Publish the macOS update feed alongside release packages and keep same-version workflow artifacts outside the update channel.

## 0.1.3 - Unreleased

- Replace the default Flutter application icons on Android, iOS, macOS, and Windows with the TwistCast landscape-and-portrait screen mark.
- Check tag references before resolving release commits so new versions without tags can build and publish.

## 0.1.2 - Unreleased

- Pace Android internal-audio and silent buffers at their PCM frame duration to prevent unbounded delivery into WebRTC.
- Release failed playback recorders and enable internal audio only after recording starts successfully.

## 0.1.1 - Unreleased

- Build signed Android APKs and a universal macOS DMG in parallel through GitHub Actions, and publish the packages to GitHub Releases after checks pass.
- Use a dedicated Android release signing key and reject release builds when signing credentials are missing.
- Cache build dependencies, validate release versions, and include package checksums and third-party notices.
- Document release configuration and installation with direct links to repository secrets, workflow runs, and downloads.
- Build Android architectures in parallel and support focused platform or architecture rebuilds as workflow artifacts.
- Cache the Android toolchain and compilation outputs, avoid competing Flutter cache writers, and report per-step build durations.
- Fix macOS architecture verification, cache Flutter's actual Swift package directory, and save prepared caches before packaging checks.
- Automatically run the full release workflow on pushes to main, while retaining manual platform rebuilds and version-tag triggers.
- Trim unused platform artifacts from Flutter SDK caches and repair Android toolchain cache extraction over preinstalled SDK files.
- Preserve unchanged macOS build input timestamps and key native caches by build inputs to reduce unnecessary recompilation and cache uploads.
- Build same-version commits as workflow artifacts without replacing published releases, and publish only unpublished versions after checks pass.

## 0.1.0 - Unreleased

- Establish a native Flutter client for one-to-one phone screen sharing over a local network.
- Add QR pairing, on-demand device discovery, explicit approval on both devices, and encrypted signaling and media transport.
- Implement Android screen and internal-audio capture, an iOS ReplayKit broadcast extension, and desktop screen and audio receivers.
- Add an optional internal-audio switch without substituting microphone capture.
- Provide English as the default interface language and support Simplified Chinese.
- Include the MIT license, English documentation, vendored native media patches, and third-party source notices.

Phone capture, internal audio, and cross-device operation still require real-device verification. Android and macOS source builds have compiled successfully; iOS, Windows, and Linux native builds remain unverified.
