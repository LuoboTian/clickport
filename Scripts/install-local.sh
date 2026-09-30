#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-Debug}"
case "$configuration" in Debug|Release) ;; *) echo 'Usage: Scripts/install-local.sh [Debug|Release] [--replace]' >&2; exit 2 ;; esac
source_app="build/DerivedData/Build/Products/$configuration/Clickport.app"
install_dir="${CLICKPORT_INSTALL_DIR:-$HOME/Applications}"
target="$install_dir/Clickport.app"
[[ -d "$source_app" ]] || { echo 'Run Scripts/build.sh first.' >&2; exit 1; }
codesign --verify --deep --strict "$source_app"
if [[ -e "$target" ]]; then
  [[ "${2:-}" == '--replace' ]] || { echo 'An installation exists. Quit Clickport and pass --replace to update it.' >&2; exit 1; }
  identifier=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$target/Contents/Info.plist")
  [[ "$identifier" == 'org.clickport.app' ]] || { echo 'The existing app has a different identity; refusing to replace it.' >&2; exit 1; }
fi
if pgrep -x Clickport >/dev/null; then
  echo 'Quit Clickport before installing or updating.' >&2
  exit 1
fi
mkdir -p "$install_dir"
stage=$(mktemp -d "$install_dir/.clickport-install.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "$source_app" "$stage/Clickport.app"
codesign --verify --deep --strict "$stage/Clickport.app"
backup="$stage/previous.app"
if [[ -e "$target" ]]; then mv "$target" "$backup"; fi
if ! mv "$stage/Clickport.app" "$target"; then
  if [[ -e "$backup" ]]; then mv "$backup" "$target"; fi
  echo 'Install failed; the previous app was restored.' >&2
  exit 1
fi
echo 'Installed Clickport. Settings and imported templates were preserved.'
