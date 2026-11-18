# TwistCast

Private screen sharing across your devices.

TwistCast is a Flutter client project targeting Android, iOS, Windows, macOS, and Linux. The repository currently contains the application foundation, platform runners, and English and Simplified Chinese localization. Screen sharing, audio capture, device discovery, and encrypted pairing are not implemented yet.

## Requirements

- Flutter 3.50.0 stable, including Dart 3.14.0.
- The native development tools for the platform you want to run or build. See [Flutter platform setup](https://docs.flutter.dev/platform-integration).
- Full Xcode for macOS and iOS development; Apple Command Line Tools alone are insufficient.

The application can be developed in Cursor or another Dart-compatible editor. A phone or emulator is not required to run the desktop application. Mobile capture and audio behavior require device validation.

## Getting started

Run these commands from the repository root:

```sh
flutter pub get
flutter gen-l10n
flutter analyze --no-pub
```

Run the application on the current desktop platform:

```sh
# macOS
flutter run -d macos

# Windows
flutter run -d windows

# Linux
flutter run -d linux
```

Use the command for your operating system. Each desktop target requires its corresponding native toolchain. Android and iOS require their platform tools and a device or emulator to run.

## Languages

English is the default interface language. The application also supports Simplified Chinese. The language selector changes the current application session; the selection is not persisted yet.

User-facing strings live in `lib/l10n/app_en.arb` and `lib/l10n/app_zh.arb`. English is the source language. Run `flutter gen-l10n` after changing these files. Generated localization files are excluded from version control.

Source comments and project documentation use English.

## Project structure

```text
lib/
  main.dart              Application entry point
  app.dart               Application and locale configuration
  features/home/         Initial application page
  l10n/                  English and Chinese resources
android/                 Android runner
ios/                    iOS runner
macos/                   macOS runner
windows/                 Windows runner
linux/                   Linux runner
```

The Dart package name is `twist_cast`; the application identifier is `app.twist.cast`.

## Local documents

The root `temp/` directory is ignored by Git and reserved for local documents. It is not required to run or build the application.

## License

[MIT](LICENSE).
