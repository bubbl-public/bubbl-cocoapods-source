#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DERIVED_DATA_PATH="${IOS_CANARY_DERIVED_DATA:-/tmp/bubbl-ios-canary-derived-data}"
DESTINATION="${IOS_CANARY_DESTINATION:-platform=iOS Simulator,name=iPhone 17,OS=latest}"

xcodebuild test \
  -project "$SCRIPT_DIR/BubblIOSCanary.xcodeproj" \
  -scheme BubblIOSCanary \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  "$@"
