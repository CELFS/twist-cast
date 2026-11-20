<p align="center">
  <img src="assets/branding/twistcast-icon.png" width="96" alt="TwistCast icon">
</p>

# TwistCast

Private screen sharing across your devices.

TwistCast 0.1.12 is a native Flutter client for one-to-one phone screen sharing over a local network. It includes QR pairing, on-demand device discovery, explicit approval on both devices, encrypted transport, and an internal-audio switch. English is the default interface language; Simplified Chinese is also available. On macOS, receiver tools open from the titlebar button in a floating panel without shrinking the shared screen.

During a session, the receiver places its controls above the shared screen and hides setup guidance. Desktop windows fit the incoming screen aspect ratio, including orientation changes, while the picture remains fully visible. The application header includes the TwistCast icon, and the copyright and version stay at the bottom of the window.

## Platform status

| Platform | Role in 0.1.12 | Implementation |
| --- | --- | --- |
| Android | Share the full phone screen and internal audio | MediaProjection, AudioPlaybackCapture, foreground service |
| iOS | Share the full phone screen and internal audio | ReplayKit broadcast extension and App Group socket |
| Windows | Receive screen and audio | Native WebRTC renderer |
| macOS | Receive screen and audio | Native WebRTC renderer |
| Linux | Receive screen and audio | Native WebRTC renderer |

This is a development version. Source implementation is not a claim of device certification. Actual capture, rotation, background behavior, audio synchronization, and device-specific permissions still require end-to-end testing. iOS, macOS, Windows, and Linux builds must be checked on their respective operating systems before distributing a release.

Android internal audio requires Android 10 or newer. Apps may prohibit capture of protected video or playback audio; TwistCast does not bypass those restrictions or substitute microphone audio. The iOS broadcast extension ignores microphone samples.

## Updates

Android and macOS check published GitHub Releases when the application opens. The update card shows the installed and latest versions and supports a manual refresh. Same-version workflow artifacts are not offered as updates. Checking and downloading require access to GitHub.

On Android, download progress remains visible in the update card. If a newer release is available, select **Download latest** to replace an earlier downloaded package. After downloading, select **Install update** and allow installation from TwistCast when Android asks. The app removes the downloaded APK after a successful update and retains it if you cancel installation. The package checksum, application identifier, version code, and signing certificate are verified before the system installer opens. Use release-signed installations for in-place updates.

On macOS, select **Update and restart** and follow the Sparkle update window to download, install, and relaunch. The application sandbox remains enabled, and update archives are verified with the application's public signing key. Stop screen sharing before starting an update.

## Connect

1. Put the phone and computer on the same local network and open both clients.
2. On the computer, select **Start receiving**. The invitation lasts two minutes.
3. On the phone, scan the QR code or select **Find nearby devices** and choose the receiver.
4. Compare every character of the pairing code on both screens. Approve on both devices only when the codes match.
5. Approve the phone's system screen-sharing prompt. Switch to another app to share its screen.
6. Enable **Share device audio** when needed. Select **Stop** on either end to end the session.

Opening the application alone does not start a listener, advertise a device, scan the network, or capture media. A receiver stops advertising after pairing begins. Each session requires approval, including sessions with previously paired identities. Only one phone can connect to a receiver at a time.

Guest Wi-Fi, access-point isolation, VPN routing, and host firewalls can prevent devices from connecting. The receiver currently requires a private or link-local IPv4 address. If the computer has multiple network interfaces, select the address on the phone's network below the QR code. Discovery uses Bonjour/mDNS; signaling uses an ephemeral TLS port and media uses WebRTC host candidates. No public STUN, TURN, account service, or cloud relay is configured.

### Mouse control

On Android 8.0 or later, enable **Allow mouse control** on the phone once sharing starts. Enable TwistCast in Android accessibility settings when prompted, then return to TwistCast and enable the switch for this session. Use the desktop mouse to tap, press and hold, drag, or scroll within the shared screen. Mouse control turns off when the session ends.

### Turn off the phone display

On compatible Android 15 or newer devices, connect the phone to the desktop using authorized USB or wireless debugging. Start the local Android Platform Tools server with `adb start-server` and verify the phone appears as `device` in `adb devices`. While receiving an Android screen, open the receiver controls, select **Turn off phone display**, and choose the ADB serial of the phone that is sharing. This turns off the physical display without sending the lock or power key. **Restore phone display** returns display power to Android. The receiver also attempts to restore it when sharing ends. If ADB is disconnected, use the phone's power button to wake the display.

Android's sleep timeout still applies. Some devices may stop projection when they go to sleep or lack the display power commands required by this feature.

## Privacy and pairing

- Device signing keys and TLS private keys are stored through the operating system's secure-storage facility. Storage failure prevents connection.
- QR invitations contain a pinned certificate fingerprint, a 256-bit one-time secret, and an expiry time. Do not publish an active invitation.
- Discovery uses a temporary, opaque service name. Nearby network observers can see this service while receiving is enabled; service discovery itself is not a private channel.
- Device identity is established through TLS, a signed fresh challenge, and a 64-bit comparison code checked by both users. Names and IP addresses are not authorization.
- No media negotiation or capture starts before both approvals. Signaling uses TLS, and WebRTC encrypts the media transport.
- Pairing remembers cryptographic identities. It does not attest that the remote executable is an unmodified TwistCast binary.
- The application does not record or upload screen content. Pairing secrets are not written to application logs.

## Downloads

Download Android APKs and the macOS universal PKG installer from [GitHub Releases](https://github.com/CELFS/twist-cast/releases). New builds, including same-version updates, are published after the [Release workflow](https://github.com/CELFS/twist-cast/actions/workflows/release.yml) completes successfully. Each published build has its own tag and increasing build number; previous releases remain available. Focused builds are available in each run's Artifacts. See [Release builds](docs/releases.md) for signing setup, direct configuration links, and installation instructions. Update checks remain available during screen sharing; downloading or installing an update requires ending the session.

## Development

Requirements:

- Flutter 3.50.0 stable and Dart 3.14.0.
- Android: Java 17 and an Android SDK compatible with the Flutter project. The first build downloads the required Gradle, native SDK, and plugin artifacts.
- macOS and iOS: full Xcode. Apple Command Line Tools alone cannot build these applications.
- Windows: Visual Studio with Desktop development with C++.
- Linux: Flutter desktop prerequisites, GTK development files, `libsecret-1-dev`, and a running Secret Service and Avahi service.

Use Cursor or another Dart-compatible editor. A phone is not required to develop or run the desktop receiver. It is required to validate phone capture and system permissions.

```sh
flutter pub get
flutter gen-l10n
flutter analyze --no-pub
flutter test --no-pub
```

The pairing security test opens real TLS connections on a local IPv4 interface. It does not broadcast discovery and does not capture media. It checks certificate pinning and requires both approvals before sending signaling messages. The widget test checks the initial desktop interface and language switching.

Run the desktop application on its corresponding operating system:

```sh
flutter run -d macos
flutter run -d windows
flutter run -d linux
```

Build an Android package for device testing:

```sh
# Set JAVA_HOME to your JDK installation if Java is not already configured.
# Homebrew OpenJDK 17 on Apple Silicon:
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
flutter build apk --debug
```

The APK is written to `build/app/outputs/flutter-apk/app-debug.apk`. Debug builds are for testing. Release builds require the dedicated signing key described in [Release builds](docs/releases.md). They never use the debug signing key.

## iOS setup

The project contains an embedded `BroadcastExtension` target. Set the same Apple development team for the app and extension. Configure the App Group `group.app.twist.cast` for both targets and the bundle identifiers `app.twist.cast` and `app.twist.cast.broadcast`. If these identifiers are changed, update the entitlements and the `RTCAppGroupIdentifier` / `RTCScreenSharingExtension` entries together.

A physical iPhone and valid signing are needed for full-screen broadcast testing. The implementation includes a custom WebRTC audio device that receives ReplayKit PCM through the App Group socket; it never opens the microphone. Background survival and audio/video synchronization must be verified on device before considering iOS release-ready.

## Native dependency patches

`packages/flutter_webrtc` contains flutter_webrtc 1.6.3 with its upstream MIT license and a small set of native capture changes. See [the patch notes](packages/flutter_webrtc/TWISTCAST_PATCHES.md). The dependency is local so clean builds do not depend on edits to the global package cache.

Android uses one MediaProjection grant for screen and playback capture. WebRTC's default microphone recorder is disabled, and playback PCM is supplied to its external audio callback. iOS adds a ReplayKit broadcast extension and a playback-only audio device. Desktop receiver implementations use the upstream WebRTC plugin.

## Languages and project structure

English is the source language for comments and documentation. Interface strings live in `lib/l10n/app_en.arb` and `lib/l10n/app_zh.arb`. Run `flutter gen-l10n` after editing them; generated localization code is ignored. The language selection applies to the current application session.

```text
lib/core/                Device identity, invitation validation, secure signaling
lib/features/cast/       Discovery, session lifecycle, WebRTC media
lib/features/home/       Main client interface
lib/features/pairing/    QR scanner and approval interface
lib/l10n/                English and Chinese resources
packages/flutter_webrtc/ Pinned native media integration
android/                 Android runner and foreground service
ios/                     iOS runner and broadcast extension
macos/, windows/, linux/ Desktop runners
```

The package name is `twist_cast`. The application identifier is `app.twist.cast`. The version is `0.1.12`; the local development build number is `13`. CI assigns increasing build numbers independently for published updates.

Record changes in [CHANGELOG.md](CHANGELOG.md).

The root `temp/` directory is ignored by Git and reserved for local documents. It is not needed to build or run the application.

## Scope

0.1.12 shares the entire phone screen with one desktop receiver. Clipboard exchange, PC-to-phone casting, file transfer, window selection, and internet relaying are not part of this version.

## License

[MIT](LICENSE). Third-party components retain their own licenses. See [Third-party notices](THIRD_PARTY_NOTICES.md) for source attributions, complete license texts, and distribution requirements.

### Connection diagnostics

After reproducing a delay, use **Connection diagnostics → Save report** on both Android and macOS. On macOS, open the receiver titlebar tools to access the report during a session. **Mark issue** records the moment you notice a stall. Reports remain available after stopping until another media session begins or the app exits. Only the newest 1,800 records are retained; the report includes the number discarded.

Reports contain one-second interval audio/video statistics and local event timestamps, not screen content, audio recordings, peer addresses, SDP, or pairing credentials. Device clocks are not synchronized. Android reports also include capture frame counts, callback time, capture dimensions, and the longest frame interval since the previous sample. A long interval can be normal for an unchanged screen. macOS reports also include cumulative texture submissions, pending-frame drops, conversion time, and raster handoff time; these do not measure physical display presentation. Buffer and processing averages are diagnostic components, not an end-to-end latency measurement; unavailable WebRTC fields are omitted. Compare pause/resume behavior with audio enabled and disabled under the same device and network conditions.
