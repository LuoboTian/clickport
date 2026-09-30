#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# This fixture never reads or writes product configuration. GUI execution is manual.
configuration="${1:-Debug}"
source_app="build/DerivedData/Build/Products/$configuration/Clickport.app"
[[ -d "$source_app/Contents/XPCServices/LaunchHelper.xpc" ]] || { echo 'Build Clickport first.'; exit 1; }
identity="${CLICKPORT_SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identities=$(security find-identity -v -p codesigning | awk '/"Apple Development:/{print $2}')
  [[ $(printf '%s\n' "$identities" | awk 'NF {n++} END {print n+0}') == 1 ]] || exit 1
  identity="$identities"
fi
swift build --package-path Packages/ClickportCore
core_bin=$(swift build --package-path Packages/ClickportCore --show-bin-path)
bash Scripts/build-launch-receiver.sh
mkdir -p build/launch-helper-probe
for variant in trusted rejected; do
  target="build/launch-helper-probe/$variant.app"
  mkdir -p "$target/Contents/MacOS" "$target/Contents/Resources" "$target/Contents/XPCServices"
  xcrun swiftc -swift-version 6 -parse-as-library -target arm64-apple-macos15.0 -I "$core_bin/Modules" \
    Shared/LaunchHelper/LaunchHelperProtocol.swift Apps/Clickport/Services/LaunchHelperClient.swift \
    Tests/Fixtures/LaunchHelperProbe.swift "$core_bin"/ClickportCore.build/*.o -o "$target/Contents/MacOS/Probe"
  ditto "$source_app/Contents/XPCServices/LaunchHelper.xpc" "$target/Contents/XPCServices/LaunchHelper.xpc"
  ditto build/test-fixtures/LaunchReceiver.app "$target/Contents/Resources/LaunchReceiver.app"
  python3 - "$target" "$variant" <<'PY'
import plistlib,sys
from pathlib import Path
p=Path(sys.argv[1]); trusted=sys.argv[2]=='trusted'
(p/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier='org.clickport.app' if trusted else 'org.clickport.rejectedprobe', CFBundleExecutable='Probe', CFBundleName='Launch Helper Probe', CFBundlePackageType='APPL', CFBundleVersion='1', LSMinimumSystemVersion='15.0')))
for name in ['alpha.txt','two words.txt','中文%20.txt']: (p/'Contents/Resources'/name).write_text('Launch helper fixture\n')
Path('build/launch-helper-probe/sandbox.plist').write_bytes(plistlib.dumps({'com.apple.security.app-sandbox':True}))
PY
  codesign --force --sign "$identity" --options runtime --timestamp=none --entitlements build/launch-helper-probe/sandbox.plist "$target" >> build/launch-helper-probe/signing.log 2>&1
  codesign --verify --deep --strict "$target" >> build/launch-helper-probe/signing.log 2>&1
done
echo 'Built trusted and rejected sandboxed probe applications in build/launch-helper-probe.'
