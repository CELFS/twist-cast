# Changelog

## 0.1.17 - Unreleased

- Reconnect to a recently paired phone or computer by name, check which devices are ready to receive, or wait for a specific sender.
- Resolve the current receiver on demand and verify its saved identity before asking both devices to approve the session.

## 0.1.16 - Unreleased

- Paste computer clipboard text into the focused Android field during an authorized control session using Command-V or Ctrl-V.

## 0.1.15 - Unreleased

- Share a desktop screen with an Android phone or iPhone over a paired LAN connection.
- Allow touch and keyboard control per session, with a separate pan and zoom mode for viewing.

## 0.1.14 - Unreleased

- Add a Windows x64 installer for the desktop receiver to GitHub Releases and focused workflow builds.

## 0.1.13 - Unreleased

- Turn desktop trackpad pans into continuous Android touch gestures and add Back, Home, and Recent apps controls to the receiver.
- Improve the receiver tools icon contrast, lighten inactive macOS window controls, and round the shared screen corners.

## 0.1.12 - Unreleased

- Prefer the latest Android update over an older downloaded package and remove the APK after installation succeeds.
- Simplify update version details and give progress, success, and error messages distinct styles.

## 0.1.11 - Unreleased

- Store the macOS build revision in the application bundle so changes to the revision do not invalidate the Dart build cache.
- Reduce the gap above the shared screen and compact the receiver panel title on macOS.

## 0.1.10 - Unreleased

- Control an Android phone with the desktop mouse after granting accessibility access and enabling control for the session.
- Turn off and restore a compatible Android phone's physical display from the receiver through authorized ADB while sharing.

## 0.1.9 - Unreleased

- Include texture timing counters and the unrotated frame fast path in macOS Swift Package builds.
- Pause Android audio packet transmission when device audio is off while keeping the in-session audio toggle available.

## 0.1.8 - Unreleased

- Provide a macOS PKG installer that installs TwistCast in Applications without mounting a disk image or requiring drag-and-drop installation.
- Check installed versions, require TwistCast to close before replacement, and open the installed application in the active user's session after installation.
- Verify the application identity and signature inside the finished installer while retaining signed DMG archives for existing Sparkle clients.

## 0.1.7 - Unreleased

- Retain bounded per-device media diagnostics across session shutdown and export JSON reports through the Android and macOS system save dialogs.
- Sample audio and video statistics every second, including interval throughput, loss, keyframe requests, encoding, decoding, buffering, and audio compensation counters.
- Record Android capture cadence and callback counters alongside macOS texture conversion, pending-frame drops, and raster handoff counters without changing the rendering policy.
- Add manual issue markers to correlate observed stalls with local session metrics without recording screen or audio content.

## 0.1.6 - Unreleased

- Move macOS receiver controls into a titlebar button and an on-demand overlay, keeping the shared screen free of a separate toolbar.
- Allow update checks during screen sharing while keeping downloads and installation disabled until the session ends.
- Distinguish update connection failures, GitHub rate limits, service errors, and invalid release metadata, and bound each request by a total timeout.
- Avoid an unnecessary full-frame rotation copy when rendering unrotated video on Apple platforms.

## Unreleased

- Publish same-version builds under independent release tags with increasing CI build numbers and commit metadata, preserving previous releases.
- Detect same-version updates on Android and macOS, display build identities, and validate downloaded Android build metadata before installation.
- Keep retried older builds from replacing newer releases as Latest.

- Reuse downloaded Swift packages across project configuration changes within the same Xcode toolchain, while retaining native compilation cache compatibility checks.
- Avoid new macOS compilation cache entries for workflow-only and packaging-helper changes.
- Validate release inputs before starting platform builds, provide a local preflight command, and report job waiting time separately from execution time.

- Enable low-delay video playout on macOS receivers and log interval encoding, sending, decoding, buffering, and network timing metrics for latency diagnosis.

- Enforce the Android screen video source frame rate before encoding and allow resolution adaptation to preserve motion under load.
- Preserve the correct capture dimensions when screen sharing starts in landscape orientation.

- Add rounded corners and transparent padding to macOS application icons while preserving the original artwork.
- Hide the receiver title and language selector by default and provide a control to show or hide them during a session.
- Hide the footer during screen reception and refit the receiver window when the header visibility changes.

## 0.1.5 - Unreleased

- Fit desktop receiver windows to the shared screen aspect ratio, including orientation changes.
- Keep receiver controls above the shared screen and hide setup guidance during a session.
- Display the application icon beside the left-aligned header title.
- Anchor the copyright, author, and version footer to the bottom of the window.

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
