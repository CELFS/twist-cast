# Release builds

TwistCast 0.1.7 uses Flutter 3.50.0 and Dart 3.14.0. The application version is `0.1.7`; its local development build number is `8`. `pubspec.yaml` stores these as `0.1.7+8`. CI overrides the internal build number with `10000 + GITHUB_RUN_NUMBER` for every platform; retries of the same run keep the same number.

## Direct links

- [Download published packages](https://github.com/CELFS/twist-cast/releases)
- [Run or inspect the Release workflow](https://github.com/CELFS/twist-cast/actions/workflows/release.yml)
- [Repository Actions secrets](https://github.com/CELFS/twist-cast/settings/secrets/actions)
- [Add a repository secret](https://github.com/CELFS/twist-cast/settings/secrets/actions/new)
- [Repository Actions permissions](https://github.com/CELFS/twist-cast/settings/actions)

Settings pages require repository administration access. The workflow page becomes available after `.github/workflows/release.yml` is pushed to the default branch.

## One-time Android signing setup

Android releases use a dedicated TwistCast signing key. Keep the same key for every update. The keystore, passwords, and local environment file are stored in `.secrets/`, which is ignored by Git. Back up this directory securely outside the repository; losing the key prevents updates to existing installations. Do not attach these files to a release or share their contents publicly.

Create these four repository secrets using the direct links below. Each local file contains exactly one secret value. The copy commands are for macOS and must be run from the TwistCast repository root; they put the value on the clipboard without printing it.

| Secret name | Local value file | Copy command | GitHub entry |
| --- | --- | --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `.secrets/ANDROID_KEYSTORE_BASE64.txt` | `pbcopy < .secrets/ANDROID_KEYSTORE_BASE64.txt` | [New repository secret](https://github.com/CELFS/twist-cast/settings/secrets/actions/new) |
| `ANDROID_STORE_PASSWORD` | `.secrets/ANDROID_STORE_PASSWORD.txt` | `pbcopy < .secrets/ANDROID_STORE_PASSWORD.txt` | [New repository secret](https://github.com/CELFS/twist-cast/settings/secrets/actions/new) |
| `ANDROID_KEY_ALIAS` | `.secrets/ANDROID_KEY_ALIAS.txt` | `pbcopy < .secrets/ANDROID_KEY_ALIAS.txt` | [New repository secret](https://github.com/CELFS/twist-cast/settings/secrets/actions/new) |
| `ANDROID_KEY_PASSWORD` | `.secrets/ANDROID_KEY_PASSWORD.txt` | `pbcopy < .secrets/ANDROID_KEY_PASSWORD.txt` | [New repository secret](https://github.com/CELFS/twist-cast/settings/secrets/actions/new) |

Enter the name in **Name**, paste the matching value into **Secret**, and select **Add secret** for each entry. The workflow fails with a clear error if signing secrets are missing; it never falls back to a debug key. Secret values are supplied only to the Android job, and its temporary keystore is removed when the job finishes.

## macOS update signing

Sparkle 2.10.1 is pinned in the macOS Xcode project. Swift Package Manager resolves it during the macOS build. The application retains App Sandbox and enables Sparkle's installer service. Updates use the `appcast.xml` asset from the latest published GitHub Release; new builds of the same application version also enter this channel after a successful complete release.

The public verification key is stored in `macos/Runner/Configs/Updates.xcconfig`. Its matching private key is stored locally in the ignored `.secrets/SPARKLE_PRIVATE_KEY.txt` file. Back up this private key securely; do not regenerate or replace it for routine releases.

Configure the `SPARKLE_PRIVATE_KEY` [repository secret](https://github.com/CELFS/twist-cast/settings/secrets/actions/new) using the contents of that file. With GitHub CLI, run from the repository root:

```bash
gh secret set SPARKLE_PRIVATE_KEY --repo CELFS/twist-cast < .secrets/SPARKLE_PRIVATE_KEY.txt
```

The macOS job verifies the secret against the committed public key before compiling. After packaging, `python3 tool/release.py appcast` signs the DMG with Ed25519 and writes its version, build number, size, download URL, and signature into the feed. The release is published only after the complete package set and feed are uploaded. A missing or mismatched key fails the job instead of publishing an unsigned update.

`swift tool/update_signing.swift init` is only for the initial setup of a new signing identity; it refuses to overwrite existing key files. Existing installations trust the embedded public key, so key rotation requires a separate migration.

## Build and publish

Before submitting a release, use the installed Flutter SDK and already resolved dependencies to run:

```sh
python3 tool/release.py preflight
```

This validates version fields, property lists, entitlements, and the public update key, then runs analysis and tests without fetching packages. On macOS it also checks Xcode project syntax. It does not install tools or dependencies, build native packages, or verify private signing secrets. A full macOS build still requires Xcode. The workflow runs the release input checks before starting platform jobs and repeats the preflight checks in its checks job.

Push commits to `main` using your normal Git workflow. This automatically runs the complete release workflow; no manual **Run workflow** action is needed. Every successful platform build uploads packages to that run's Artifacts. After all checks and builds succeed, each new build is published to GitHub Releases with its own tag, such as `v0.1.7-build.10015`. The application version may remain unchanged. The tag points to the selected commit, and the release includes `update.json` with the version, build number, and full commit hash. The complete release is explicitly marked Latest only after all assets are uploaded.

Manual runs remain available from the [Release workflow](https://github.com/CELFS/twist-cast/actions/workflows/release.yml). Choose a branch and **target** to run the full workflow or rebuild selected packages. Pushing a matching version tag also remains supported. Avoid manually starting or pushing a tag for the same commit while its `main` push run is already processing.

Manual dispatch requires the workflow to be present on the default branch. Published release packages, notes, and tags are never replaced. Same-version builds receive separate tags. A build tag or draft belonging to another commit fails validation. A failed draft upload can be retried for the same run and commit; an already published build is left intact. An older run cannot replace a newer build as Latest.

The workflow validates version consistency, then runs analysis/tests, Android toolchain preparation, and the macOS build in parallel. Three independent Android jobs build ARM64, ARMv7, and x86_64 after the shared toolchain is ready. A failed architecture does not cancel the other builds.

For a focused rebuild, use the same [Release workflow](https://github.com/CELFS/twist-cast/actions/workflows/release.yml) and select a **target**:

| Target | Result |
| --- | --- |
| `all` | Build every package and run checks; publish a new build even when its application version is unchanged |
| `android` | Build all three Android architectures; download them from the run's Artifacts |
| `macos` | Build only the macOS package; download it from the run's Artifacts |
| `android-arm64-v8a` | Build the ARM64 APK; download it from the run's Artifacts |
| `android-armeabi-v7a` | Build the ARMv7 APK; download it from the run's Artifacts |
| `android-x86_64` | Build the x86_64 APK; download it from the run's Artifacts |

Focused rebuilds still run analysis and tests. They do not create or replace a published release. Use **Re-run failed jobs** on a full run when retrying a transient failure without changing the source; workflow changes require a new run on the updated commit.

Only the publish job receives repository write permission. It uploads all packages and checksums to a draft before publishing. If organization or repository policy blocks this permission, review [Actions permissions](https://github.com/CELFS/twist-cast/settings/actions). A personal access token is not required.

For published builds, including same-version updates, open [Releases](https://github.com/CELFS/twist-cast/releases). For focused builds or incomplete release runs, open the completed run from the [Release workflow](https://github.com/CELFS/twist-cast/actions/workflows/release.yml) and download its **Artifacts**. Successful platform jobs retain their packages there for 14 days, even when another platform fails. Artifacts require a GitHub login; published release assets remain attached to the release.

## Build performance

- Flutter SDK and Dart package caches have one writer per shared key. They are saved immediately after successful preparation, before compilation or packaging can fail. Android jobs restore the Linux cache without competing to save it.
- Flutter SDK caches exclude unused iOS and web artifacts, and non-Android jobs also exclude Android engine artifacts. Existing SDK caches can seed the smaller caches without downloading the SDK again; host engines and Dart tools remain available for checks and compilation.
- A separate job primes the shared Android NDK, CMake, platform, and build-tools cache. Its warm-cache path only checks availability; the architecture jobs restore the cache directly. Versions live in `.github/android-toolchain.json`; the NDK and Android platform versions are checked against the pinned Flutter SDK.
- Before Android cache extraction, existing toolchain directories are made writable by the runner so preinstalled SDK files do not cause archive restoration to fail.
- Gradle uses its minimal binary distribution with an official SHA-256 checksum. `setup-gradle` restores dependencies and task outputs for each matrix job. Build caching, parallel tasks, four-worker limits, and daemon shutdown are enabled only in CI; configuration caching of signing credentials is not enabled.
- Android Flutter compilation outputs are cached separately for each architecture. macOS caches Swift packages at Flutter's actual `build/macos/SourcePackages` path and reuses native compilation outputs keyed by Xcode, Flutter, dependencies, and build inputs. Native outputs are saved after a successful compilation and before packaging checks. Swift package downloads can be restored from the latest cache for the same architecture and Xcode build when the exact dependency key changes; SwiftPM still resolves and validates the current dependency graph. Native compilation outputs retain their stricter dependency and project compatibility key.
- macOS compilation caches include an input timestamp manifest. After checkout, timestamps are restored only when file content matches the successful cached build, allowing unchanged native sources to retain incremental compilation state. Changed inputs keep their new timestamps. Documentation-only, workflow-only, and packaging-helper-only commits reuse the same native cache key; compilation and package verification still run.
- Open each job's summary for cache hits. The final **timings** job reports the duration of every job and step, including cache transfers, and reports the interval between job creation and start separately. This waiting interval can include scheduling and prerequisite waits; it is not compilation time. Compare cold and warm runs separately; cache transfer and parallel-job overhead must be included when evaluating improvements.

First builds still download large SDKs. Cache reuse and parallel builds reduce repeated work, but their actual effect must be measured in cloud runs; no fixed completion time is guaranteed. Compilation runs on GitHub-hosted machines and does not require local builds.

## Packages and installation

The updater compares internal build numbers and displays the installed and available version, build number, and short commit hash. SHA-256 validates the downloaded APK; its package name, internal build metadata, increasing Android version code, and signing certificate are also checked. macOS uses the same CI build number in `CFBundleVersion` and the signed Sparkle feed. Source hashes identify commits; build numbers determine update order.

Clients shipped before build-aware updates only recognize plain version tags. Install the first build-aware APK or DMG manually over the existing application once; subsequent same-version builds are available through Check for updates. Keep the same signing identities when publishing this transition.

| Asset | Use |
| --- | --- |
| `twist-cast-0.1.7-android-arm64-v8a.apk` | Most current Android phones, including current Redmi devices |
| `twist-cast-0.1.7-android-armeabi-v7a.apk` | Older 32-bit ARM Android devices |
| `twist-cast-0.1.7-android-x86_64.apk` | x86_64 Android devices and compatible emulators |
| `twist-cast-0.1.7-macos-universal.dmg` | Apple Silicon and Intel Macs, macOS 12 or newer |
| `THIRD_PARTY_NOTICES.zip` | Vendored source notices and Flutter-generated Android package notices |
| `SHA256SUMS.txt` | SHA-256 checksums of the release assets |
| `update.json` | Application version, CI build number, release tag, and commit hash |
| `appcast.xml` | Signed macOS update feed |

On Android, download the matching APK, open it, and allow installation from the app used to open it when prompted. Existing debug builds have a different signing key and must be uninstalled before installing the first release build. Uninstalling removes local pairing data. Subsequent release builds use the same key and can update in place.

On macOS, open the DMG and drag TwistCast to **Applications**. The application is ad-hoc signed, without an Apple Developer certificate or notarization. macOS may block the first launch; after trying to open the app, use **System Settings > Privacy & Security > Open Anyway** if available. Managed computers can prohibit this exception. Installing and running the downloaded package does not require Xcode or an Apple account.

These packages are for early device testing. A successful compilation does not verify real-device screen capture, audio, permissions, or end-to-end pairing. The workflow currently distributes Android and macOS packages; it does not distribute iOS, Windows, or Linux packages.

The notices archive preserves the scope described in [Third-party notices](../THIRD_PARTY_NOTICES.md). It is not a complete inventory of every native SDK's transitive binary dependencies.

## Local Android release build

With the local signing files already provisioned:

```sh
# Run from the TwistCast repository root.
source .secrets/release.env
# Homebrew OpenJDK 17 on Apple Silicon:
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
flutter pub get --enforce-lockfile
flutter gen-l10n
flutter build apk --release --split-per-abi --no-pub
```

The APKs are written to `build/app/outputs/flutter-apk/`. Release builds without all four `TWISTCAST_*` signing environment variables fail; debug builds remain available without the release key. `release.env` is private and machine-specific, so update its keystore path when moving the private files to another computer.

## Next version

Update `pubspec.yaml` with the next application version and a strictly larger build number. Update the displayed version in both ARB files and the English footer label, the broadcast extension's version/build number, and the version references in the documentation. Keep using the same Android signing key.

Run `python3 tool/release.py metadata` to verify the version fields. CI release tags combine the application version and assigned build number, for example `v0.1.7-build.10015`. A plain version tag can still trigger the workflow, but the resulting release uses the assigned build tag. Routine same-version CI updates do not require editing `pubspec.yaml`. Local builds retain its development build number and cannot replace a newer CI installation without an explicitly higher build number.
