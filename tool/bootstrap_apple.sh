#!/usr/bin/env bash
set -euo pipefail

flutter config --enable-macos-desktop --no-enable-swift-package-manager
flutter create --platforms=ios,macos --project-name digitor .
flutter pub get

python3 - <<'PY'
from pathlib import Path
import re

for path, key, version in [
    (Path('ios/Runner.xcodeproj/project.pbxproj'), 'IPHONEOS_DEPLOYMENT_TARGET', '13.0'),
    (Path('macos/Runner.xcodeproj/project.pbxproj'), 'MACOSX_DEPLOYMENT_TARGET', '11.0'),
]:
    text = path.read_text()
    text = re.sub(rf'{key} = [^;]+;', f'{key} = {version};', text)
    path.write_text(text)

for path, platform, version in [
    (Path('ios/Podfile'), 'ios', '13.0'),
    (Path('macos/Podfile'), 'osx', '11.0'),
]:
    text = path.read_text()
    pattern = rf'^#?\s*platform\s+:{platform},\s*[\'\"][^\'\"]+[\'\"]'
    replacement = f"platform :{platform}, '{version}'"
    if re.search(pattern, text, flags=re.MULTILINE):
        text = re.sub(pattern, replacement, text, flags=re.MULTILINE)
    else:
        text = replacement + '\n' + text
    path.write_text(text)

entitlement = '<key>com.apple.security.files.user-selected.read-write</key>\n\t<true/>'
for path in [Path('macos/Runner/DebugProfile.entitlements'), Path('macos/Runner/Release.entitlements')]:
    text = path.read_text()
    if 'com.apple.security.files.user-selected.read-write' not in text:
        text = text.replace('</dict>', f'\t{entitlement}\n</dict>')
        path.write_text(text)
PY

printf 'iOS and macOS hosts are ready.\n'
