#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --package-path Packages/ClickportCore
core_bin=$(swift build --package-path Packages/ClickportCore --show-bin-path)
mkdir -p build/appkit-tests
xcrun swiftc -swift-version 6 -parse-as-library -I "$core_bin/Modules" \
  Shared/LaunchHelper/LaunchHelperProtocol.swift Apps/Clickport/Services/LaunchHelperClient.swift \
  Apps/Clickport/Actions/SystemActions.swift Tests/AppKit/SharingLifecycle.swift \
  "$core_bin"/ClickportCore.build/*.o -o build/appkit-tests/sharing-lifecycle
build/appkit-tests/sharing-lifecycle
