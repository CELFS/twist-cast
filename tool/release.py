#!/usr/bin/env python3
# Release metadata and packaging helpers (Python 3, standard library only).
# Usage from the repository root:
#   python3 tool/release.py metadata
#   PUBLISH_REQUESTED=true python3 tool/release.py release-policy
#   python3 tool/release.py notices
#   python3 tool/release.py checksums
#   gh api repos/OWNER/REPO/actions/runs/RUN_ID/jobs | python3 tool/release.py timings
#   python3 tool/release.py macos-input-key
#   python3 tool/release.py save-input-times
#   python3 tool/release.py restore-input-times
#   python3 tool/release.py appcast
# Input timestamps are saved with macOS compilation outputs and restored only for identical files.
# Outputs go to build/release; metadata also writes GitHub Actions job outputs.

import argparse
import base64
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import zipfile
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / 'build' / 'release'
INPUT_TIMES = ROOT / 'build/macos/Build/twistcast-input-times.json'


def tracked_inputs():
    paths = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
    return [ROOT / path for path in paths if path and
            not (ROOT / path).is_symlink() and (ROOT / path).is_file()]


def macos_input_key():
    digest = hashlib.sha256()
    for path in sorted(tracked_inputs()):
        name = path.relative_to(ROOT).as_posix()
        if not (name.startswith(('lib/', 'macos/', 'packages/', 'assets/', '.github/', 'tool/')) or
                name in ('pubspec.yaml', 'pubspec.lock', 'l10n.yaml')):
            continue
        digest.update(name.encode() + b'\0' + hashlib.sha256(path.read_bytes()).digest())
    print('key=' + digest.hexdigest())


def input_times(restore):
    paths = tracked_inputs()
    paths.extend(path for path in (ROOT / 'lib/l10n/generated').rglob('*')
                 if path.is_file() and not path.is_symlink())
    if restore:
        if not INPUT_TIMES.is_file():
            print('No input timestamp manifest in the restored compilation cache.')
            return
        previous = json.loads(INPUT_TIMES.read_text())
    else:
        previous = {}
    count = 0
    for path in paths:
        name = path.relative_to(ROOT).as_posix()
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        info = path.stat()
        if restore:
            saved = previous.get(name)
            # Changed files retain their new timestamps so Xcode recompiles them.
            if saved and saved['sha256'] == digest:
                os.utime(path, ns=(info.st_atime_ns, saved['mtime_ns']))
                count += 1
        else:
            previous[name] = {'sha256': digest, 'mtime_ns': info.st_mtime_ns}
    if not restore:
        INPUT_TIMES.parent.mkdir(parents=True, exist_ok=True)
        INPUT_TIMES.write_text(json.dumps(previous, separators=(',', ':')) + '\n')
    print(f'Restored timestamps for {count} unchanged inputs.' if restore else
          f'Saved timestamps for {len(previous)} build inputs.')


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
    strings = json.loads((ROOT / 'lib/l10n/app_en.arb').read_text())
    if not strings['footerLabel'].endswith(f' · v{version}'):
        raise SystemExit('The interface footer version does not match pubspec.yaml.')
    with (ROOT / 'ios/BroadcastExtension/Info.plist').open('rb') as stream:
        extension = plistlib.load(stream)
    if (extension['CFBundleShortVersionString'], extension['CFBundleVersion']) != (version, build_number):
        raise SystemExit('The broadcast extension version does not match pubspec.yaml.')
    tag = f'v{version}'
    if os.environ.get('GITHUB_REF_TYPE') == 'tag' and os.environ.get('GITHUB_REF_NAME') != tag:
        raise SystemExit('The release tag does not match pubspec.yaml.')
    targets = [
        {'abi': 'arm64-v8a', 'target': 'android-arm64'},
        {'abi': 'armeabi-v7a', 'target': 'android-arm'},
        {'abi': 'x86_64', 'target': 'android-x64'},
    ]
    selected = os.environ.get('RELEASE_TARGET', 'all')
    choices = ['all', 'android', 'macos', *(f'android-{item["abi"]}' for item in targets)]
    if selected not in choices:
        raise SystemExit('Unknown release target: ' + selected)
    android = [item for item in targets if selected in ('all', 'android', f'android-{item["abi"]}')]
    return {
        'version': version, 'build_number': build_number, 'tag': tag,
        'android': str(bool(android)).lower(),
        'macos': str(selected in ('all', 'macos')).lower(),
        'publish': str(selected == 'all').lower(),
        'android_matrix': json.dumps({'include': android}, separators=(',', ':')),
        'notices_abi': android[0]['abi'] if android else '',
    }


def github_resource(path):
    result = subprocess.run(['gh', 'api', path], capture_output=True, text=True)
    if result.returncode == 0:
        return json.loads(result.stdout)
    if '(HTTP 404)' in result.stderr:
        return None
    raise SystemExit(result.stderr.strip() or 'GitHub API request failed.')


def release_policy():
    publish = False
    reason = 'Selected packages are available as workflow artifacts only.'
    if os.environ.get('PUBLISH_REQUESTED') == 'true':
        repository = os.environ['GITHUB_REPOSITORY']
        tag = os.environ['TAG']
        sha = os.environ['GITHUB_SHA']
        release = github_resource(f'repos/{repository}/releases/tags/{tag}')
        if release and not release['draft']:
            reason = 'This version is already published; new packages remain in workflow artifacts.'
        else:
            # Missing tag references return 404; the commits endpoint returns 422.
            reference = github_resource(f'repos/{repository}/git/ref/tags/{tag}')
            commit = None
            if reference is not None:
                # Resolve annotated tags to their commit as well as lightweight tags.
                commit = github_resource(f'repos/{repository}/commits/refs/tags/{tag}')
                if commit is None:
                    raise SystemExit('Cannot resolve the existing release tag target.')
            if commit is None and release:
                commit = github_resource(f'repos/{repository}/commits/{release["target_commitish"]}')
                if commit is None:
                    raise SystemExit('Cannot resolve the existing draft release target.')
            if commit is not None and commit['sha'] != sha:
                reason = 'This version belongs to another commit; new packages remain in workflow artifacts.'
            else:
                publish = True
                reason = 'Publish this unpublished version after all checks and builds succeed.'
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with open(summary, 'a') as stream:
            stream.write(reason + '\n')
    return {'publish': str(publish).lower(), 'reason': reason}


def appcast():
    values = metadata()
    version, build_number = values['version'], values['build_number']
    filename = f'twist-cast-{version}-macos-universal.dmg'
    archive = OUTPUT / filename
    signature = subprocess.check_output(
        ['swift', 'tool/update_signing.swift', 'sign', str(archive)], cwd=ROOT, text=True).strip()
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise SystemExit('Invalid macOS update signature.')
    sparkle = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
    ElementTree.register_namespace('sparkle', sparkle)
    rss = ElementTree.Element('rss', version='2.0')
    channel = ElementTree.SubElement(rss, 'channel')
    ElementTree.SubElement(channel, 'title').text = 'TwistCast'
    ElementTree.SubElement(channel, 'link').text = 'https://github.com/CELFS/twist-cast/releases'
    item = ElementTree.SubElement(channel, 'item')
    ElementTree.SubElement(item, 'title').text = f'TwistCast {version}'
    ElementTree.SubElement(item, f'{{{sparkle}}}version').text = build_number
    ElementTree.SubElement(item, f'{{{sparkle}}}shortVersionString').text = version
    ElementTree.SubElement(item, f'{{{sparkle}}}minimumSystemVersion').text = '12.0'
    ElementTree.SubElement(item, 'enclosure', {
        'url': f'https://github.com/CELFS/twist-cast/releases/download/v{version}/{filename}',
        'length': str(archive.stat().st_size),
        'type': 'application/octet-stream',
        f'{{{sparkle}}}edSignature': signature,
    })
    ElementTree.ElementTree(rss).write(OUTPUT / 'appcast.xml', encoding='utf-8', xml_declaration=True)
    print(OUTPUT / 'appcast.xml')


def notices():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    paths = [ROOT / 'LICENSE', ROOT / 'THIRD_PARTY_NOTICES.md', ROOT / 'docs/licenses/Sparkle.txt',
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


def timings():
    payload = json.load(sys.stdin)
    print('## Release timings\n')
    print('| Job / step | Result | Duration |')
    print('| --- | --- | ---: |')
    for job in payload['jobs']:
        if job['name'] == 'timings':
            continue
        for item in [job, *job.get('steps', [])]:
            start, end = item.get('started_at'), item.get('completed_at')
            if not start or not end:
                continue
            seconds = max(0, int((datetime.fromisoformat(end.replace('Z', '+00:00')) -
                                 datetime.fromisoformat(start.replace('Z', '+00:00'))).total_seconds()))
            label = item['name'].replace('|', r'\|').replace('\n', ' ')
            if item is job:
                label = f'**{label}**'
            else:
                label = '↳ ' + label
            print(f'| {label} | {item.get("conclusion") or "running"} | {seconds // 60}m {seconds % 60}s |')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['metadata', 'release-policy', 'notices', 'checksums', 'timings', 'appcast',
                                          'macos-input-key', 'save-input-times', 'restore-input-times'])
    command = parser.parse_args().command
    if command in ('metadata', 'release-policy'):
        values = metadata() if command == 'metadata' else release_policy()
        output = os.environ.get('GITHUB_OUTPUT')
        if output:
            with open(output, 'a') as stream:
                stream.writelines(f'{key}={value}\n' for key, value in values.items())
        print(json.dumps(values))
    elif command == 'notices':
        notices()
    elif command == 'checksums':
        checksums()
    elif command == 'appcast':
        appcast()
    elif command == 'macos-input-key':
        macos_input_key()
    elif command in ('save-input-times', 'restore-input-times'):
        input_times(restore=command == 'restore-input-times')
    else:
        timings()


if __name__ == '__main__':
    main()
