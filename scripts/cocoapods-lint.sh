#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

cd "$ROOT_DIR"

if [ -n "${BUBBL_COCOAPODS_SOURCE_URL:-}" ]; then
  FINAL_SOURCE_URL="$BUBBL_COCOAPODS_SOURCE_URL"
  FINAL_SOURCE_TAG="${BUBBL_COCOAPODS_SOURCE_TAG:-}"
  LINT_SOURCE_URL="${BUBBL_COCOAPODS_LINT_SOURCE_URL:-file://$ROOT_DIR}"
  DEFAULT_LINT_SOURCE_TAG="${GITHUB_REF_NAME:-}"
  if [ -z "$DEFAULT_LINT_SOURCE_TAG" ]; then
    DEFAULT_LINT_SOURCE_TAG="$(git describe --tags --exact-match 2>/dev/null || git rev-parse --abbrev-ref HEAD)"
  fi
  LINT_SOURCE_TAG="${BUBBL_COCOAPODS_LINT_SOURCE_TAG:-$DEFAULT_LINT_SOURCE_TAG}"

  export BUBBL_COCOAPODS_SOURCE_URL="$LINT_SOURCE_URL"
  export BUBBL_COCOAPODS_SOURCE_TAG="$LINT_SOURCE_TAG"
  node scripts/prepare-cocoapods-specs.mjs

  echo "Linting CocoaPods specs against checked-out source: $LINT_SOURCE_URL"
  echo "Linting CocoaPods specs against source tag/commit: $LINT_SOURCE_TAG"
  echo "Final CocoaPods source URL remains: $FINAL_SOURCE_URL"
  if [ -n "$FINAL_SOURCE_TAG" ]; then
    echo "Final CocoaPods source tag remains: $FINAL_SOURCE_TAG"
  fi

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
