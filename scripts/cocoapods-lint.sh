#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

cd "$ROOT_DIR"

if [ -n "${BUBBL_COCOAPODS_SOURCE_URL:-}" ]; then
  node scripts/prepare-cocoapods-specs.mjs

  pod spec lint build/cocoapods/BubblSDK.podspec --allow-warnings --verbose

  if [ "${BUBBL_COCOAPODS_ALIAS_RELEASE:-false}" = "true" ]; then
    pod spec lint build/cocoapods/Bubbl-Sdk.podspec --allow-warnings --verbose
  else
    echo "Skipping public-source Bubbl-Sdk alias lint. Set BUBBL_COCOAPODS_ALIAS_RELEASE=true after alias ownership is sorted and BubblSDK is on trunk."
  fi
else
  pod lib lint ios/BubblSDK.podspec --allow-warnings --verbose
  pod lib lint ios/Bubbl-Sdk.podspec \
    --include-podspecs=ios/BubblSDK.podspec \
    --allow-warnings \
    --verbose
fi
