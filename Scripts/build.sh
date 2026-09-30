#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-Debug}"
case "$configuration" in Debug|Release) ;; *) echo 'Usage: Scripts/build.sh [Debug|Release] [--unsigned]' >&2; exit 2 ;; esac
mkdir -p build
options=()
# Optional public links are injected locally; unset values keep the UI placeholders.
options+=("CLICKPORT_GITHUB_URL=${CLICKPORT_GITHUB_URL:-}" "CLICKPORT_UPDATES_URL=${CLICKPORT_UPDATES_URL:-}" "CLICKPORT_FEEDBACK_URL=${CLICKPORT_FEEDBACK_URL:-}")
if [[ "${2:-}" == '--unsigned' ]]; then
  options+=(CODE_SIGNING_ALLOWED=NO)
else
  identity="${CLICKPORT_SIGN_IDENTITY:-}"
  if [[ -z "$identity" ]]; then
    identities=$(security find-identity -v -p codesigning | awk '/"Apple Development:/{print $2}')
    count=$(printf '%s\n' "$identities" | awk 'NF {n++} END {print n+0}')
    [[ "$count" == 1 ]] || { echo 'Set CLICKPORT_SIGN_IDENTITY to select one local development certificate.' >&2; exit 1; }
    identity="$identities"
  fi
  team="${CLICKPORT_TEAM_ID:-}"
  if [[ -z "$team" ]]; then
    probe=$(mktemp -d)
    trap 'rm -rf "$probe"' EXIT
    cp /usr/bin/true "$probe/signing-probe"
    codesign --force --sign "$identity" --timestamp=none "$probe/signing-probe" > "$probe/signing.log" 2>&1 || { echo 'Local certificate signing failed.' >&2; exit 1; }
    team=$(codesign -dv "$probe/signing-probe" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2}')
    [[ -n "$team" && "$team" != 'not set' ]] || { echo 'Set CLICKPORT_TEAM_ID for local signing.' >&2; exit 1; }
  fi
  options+=("CODE_SIGN_IDENTITY=$identity" "DEVELOPMENT_TEAM=$team" "CODE_SIGN_STYLE=Manual")
fi
# Keep build output local; signing metadata is never written to tracked configuration.
actions=(build)
# Release artifacts must not inherit stale embedded SwiftPM resource signatures.
if [[ "$configuration" == 'Release' ]]; then actions=(clean build); fi
if ! xcodebuild -quiet -project Clickport.xcodeproj -scheme Clickport -configuration "$configuration" -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData "${options[@]}" "${actions[@]}" > build/build.log 2>&1; then
  echo 'Build failed. Inspect build/build.log locally.' >&2
  exit 1
fi
if [[ "${2:-}" != '--unsigned' ]]; then
  app="build/DerivedData/Build/Products/$configuration/Clickport.app"
  extension="$app/Contents/PlugIns/FinderExtension.appex"
  # Xcode can update a shared SwiftPM resource bundle after reusing the outer
  # extension seal during an incremental build. Seal inside out only after all
  # copies finish, preserving the entitlements produced by this build.
  for product in "$extension" "$app"; do
    if ! codesign --force --sign "$identity" --timestamp=none --preserve-metadata=identifier,entitlements,flags,runtime "$product" >> build/build.log 2>&1; then
      echo 'Final local signing failed. Inspect build/build.log.' >&2
      exit 1
    fi
  done
  if ! codesign --verify --deep --strict "$app" >> build/build.log 2>&1; then
    echo 'Signature verification failed. Inspect build/build.log; this artifact must not be installed or packaged.' >&2
    exit 1
  fi
fi
printf 'Built: build/DerivedData/Build/Products/%s/Clickport.app\n' "$configuration"
