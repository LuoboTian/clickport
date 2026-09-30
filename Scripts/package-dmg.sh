#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-Release}"
case "$configuration" in
  Debug|Release) ;;
  *) echo 'Usage: package-dmg.sh [Debug|Release]' >&2; exit 1 ;;
esac
source_app="build/DerivedData/Build/Products/$configuration/Clickport.app"
[[ -d "$source_app" ]] || { echo 'Build the selected configuration first.' >&2; exit 1; }
codesign --verify --deep --strict "$source_app"
mkdir -p build/packages
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
ditto "$source_app" "$stage/Clickport.app"
ln -s /Applications "$stage/Applications"
output="build/packages/Clickport-local-$(date +%Y%m%d-%H%M%S).dmg"
hdiutil create -quiet -volname Clickport -srcfolder "$stage" -format UDZO "$output"
hdiutil verify -quiet "$output"
printf 'Created local test image: %s\n' "$output"
echo 'This script does not notarize or publish. Local development signing is not a public release.'
