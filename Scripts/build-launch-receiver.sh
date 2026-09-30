#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
target='build/test-fixtures/LaunchReceiver.app'
mkdir -p "$target/Contents/MacOS"
xcrun swiftc -swift-version 6 -parse-as-library -target arm64-apple-macos15.0 \
  Tests/Fixtures/LaunchReceiver.swift -o "$target/Contents/MacOS/LaunchReceiver"
python3 - "$target/Contents/Info.plist" <<'PY'
import plistlib
import sys
from pathlib import Path
info = {
    'CFBundleIdentifier': 'org.clickport.testreceiver',
    'CFBundleName': 'LaunchReceiver',
    'CFBundleExecutable': 'LaunchReceiver',
    'CFBundlePackageType': 'APPL',
    'CFBundleVersion': '1',
    'CFBundleShortVersionString': '1.0',
    'LSMinimumSystemVersion': '15.0',
    'NSPrincipalClass': 'NSApplication',
    'CFBundleDocumentTypes': [{
        'CFBundleTypeName': 'Test files and directories',
        'CFBundleTypeRole': 'Viewer',
        'LSHandlerRank': 'None',
        'LSItemContentTypes': ['public.data', 'public.folder'],
    }],
}
Path(sys.argv[1]).write_bytes(plistlib.dumps(info))
PY
codesign --force --sign - "$target"
codesign --verify --strict "$target"
echo 'Built local integration fixture: build/test-fixtures/LaunchReceiver.app'
