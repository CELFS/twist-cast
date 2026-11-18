#!/usr/bin/env python3
# Release metadata and packaging helpers (Python 3, standard library only).
# Usage from the repository root:
#   python3 tool/release.py metadata
#   python3 tool/release.py notices
#   python3 tool/release.py checksums
# Outputs go to build/release; metadata also writes GitHub Actions job outputs.

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import zipfile

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / 'build' / 'release'


def metadata():
    match = re.search(r'^version: (\d+\.\d+\.\d+)\+([1-9]\d*)$',
                      (ROOT / 'pubspec.yaml').read_text(), re.MULTILINE)
    if not match:
        raise SystemExit('Expected version: major.minor.patch+build in pubspec.yaml.')
    version, build_number = match.groups()
    for locale in ('en', 'zh'):
        strings = json.loads((ROOT / f'lib/l10n/app_{locale}.arb').read_text())
        if strings['versionLabel'] != f'TwistCast {version}':
            raise SystemExit(f'The {locale} interface version does not match pubspec.yaml.')
    with (ROOT / 'ios/BroadcastExtension/Info.plist').open('rb') as stream:
        extension = plistlib.load(stream)
    if (extension['CFBundleShortVersionString'], extension['CFBundleVersion']) != (version, build_number):
        raise SystemExit('The broadcast extension version does not match pubspec.yaml.')
    tag = f'v{version}'
    if os.environ.get('GITHUB_REF_TYPE') == 'tag' and os.environ.get('GITHUB_REF_NAME') != tag:
        raise SystemExit('The release tag does not match pubspec.yaml.')
    return {'version': version, 'build_number': build_number, 'tag': tag}


def notices():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    paths = [ROOT / 'LICENSE', ROOT / 'THIRD_PARTY_NOTICES.md',
             ROOT / 'packages/flutter_webrtc/LICENSE',
             ROOT / 'packages/flutter_webrtc/NOTICE',
             ROOT / 'packages/flutter_webrtc/TWISTCAST_PATCHES.md',
             ROOT / 'packages/flutter_webrtc/third_party/svpng/LICENSE']
    paths.extend(sorted((ROOT / 'packages/flutter_webrtc/third_party/licenses').rglob('*')))
    with zipfile.ZipFile(OUTPUT / 'THIRD_PARTY_NOTICES.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in paths:
            if path.is_file():
                archive.write(path, path.relative_to(ROOT))
        # Preserve Flutter's generated package notices from the actual APK build.
        apk_dir = ROOT / 'build/app/outputs/flutter-apk'
        apks = sorted(apk_dir.glob('app-*-release.apk'))
        if apks:
            with zipfile.ZipFile(apks[0]) as apk:
                name = 'assets/flutter_assets/NOTICES.Z'
                archive.writestr('flutter/NOTICES.Z', apk.read(name))
    print(OUTPUT / 'THIRD_PARTY_NOTICES.zip')


def checksums():
    files = sorted(path for path in OUTPUT.iterdir()
                   if path.is_file() and path.name != 'SHA256SUMS.txt')
    if not files:
        raise SystemExit('No release assets found.')
    with (OUTPUT / 'SHA256SUMS.txt').open('w') as stream:
        for path in files:
            with path.open('rb') as asset:
                digest = hashlib.file_digest(asset, 'sha256').hexdigest()
            stream.write(f'{digest}  {path.name}\n')
    print(f'Wrote checksums for {len(files)} assets.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['metadata', 'notices', 'checksums'])
    command = parser.parse_args().command
    if command == 'metadata':
        values = metadata()
        output = os.environ.get('GITHUB_OUTPUT')
        if output:
            with open(output, 'a') as stream:
                stream.writelines(f'{key}={value}\n' for key, value in values.items())
        print(json.dumps(values))
    elif command == 'notices':
        notices()
    else:
        checksums()


if __name__ == '__main__':
    main()
