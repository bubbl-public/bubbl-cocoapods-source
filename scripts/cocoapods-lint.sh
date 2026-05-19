#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

cd "$ROOT_DIR"

if [ -n "${BUBBL_COCOAPODS_SOURCE_URL:-}" ]; then
  node scripts/prepare-cocoapods-specs.mjs

  pod spec lint build/cocoapods/BubblSDK.podspec --allow-warnings --verbose
  pod spec lint build/cocoapods/Bubbl-Sdk.podspec \
    --include-podspecs=build/cocoapods/BubblSDK.podspec \
    --allow-warnings \
    --verbose
else
  pod lib lint ios/BubblSDK.podspec --allow-warnings --verbose
  pod lib lint ios/Bubbl-Sdk.podspec \
    --include-podspecs=ios/BubblSDK.podspec \
    --allow-warnings \
    --verbose
fi
