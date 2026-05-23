#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VERSION="$(node -p "require('./package.json').version")"
SOURCE_URL="${BUBBL_COCOAPODS_SOURCE_URL:-https://github.com/bubbl-platform/renewed-sdk.git}"
SOURCE_TAG="${BUBBL_COCOAPODS_SOURCE_TAG:-$VERSION}"
REQUIRE_PUBLIC_SOURCE="${BUBBL_COCOAPODS_REQUIRE_PUBLIC_SOURCE:-true}"
export BUBBL_COCOAPODS_SOURCE_TAG="$SOURCE_TAG"

cd "$ROOT_DIR"

node scripts/prepare-cocoapods-specs.mjs

if [ "${BUBBL_PUBLIC_REGISTRY_RELEASE:-false}" != "true" ]; then
  echo "BUBBL_PUBLIC_REGISTRY_RELEASE must be true to publish CocoaPods trunk artifacts."
  exit 1
fi

if [ "${BUBBL_COCOAPODS_TRUNK_RELEASE:-false}" != "true" ]; then
  echo "BUBBL_COCOAPODS_TRUNK_RELEASE must be true to publish CocoaPods trunk artifacts."
  exit 1
fi

if [ -z "${COCOAPODS_TRUNK_TOKEN:-}" ]; then
  echo "Missing COCOAPODS_TRUNK_TOKEN."
  exit 1
fi

if [ "$REQUIRE_PUBLIC_SOURCE" != "false" ]; then
  if ! git ls-remote "$SOURCE_URL" "refs/tags/$SOURCE_TAG" >/dev/null 2>&1; then
    echo "CocoaPods trunk needs a publicly readable podspec source URL and tag."
    echo "Could not read refs/tags/$SOURCE_TAG from: $SOURCE_URL"
    echo "Set BUBBL_COCOAPODS_SOURCE_URL to the final public source URL, or set"
    echo "BUBBL_COCOAPODS_REQUIRE_PUBLIC_SOURCE=false for a private specs workflow."
    exit 1
  fi
fi

pod trunk me
pod trunk push build/cocoapods/BubblSDK.podspec --allow-warnings --verbose

if [ "${BUBBL_COCOAPODS_ALIAS_RELEASE:-false}" = "true" ]; then
  pod trunk push build/cocoapods/Bubbl-Sdk.podspec --synchronous --allow-warnings --verbose
else
  echo "Skipping Bubbl-Sdk alias publish. Set BUBBL_COCOAPODS_ALIAS_RELEASE=true after alias ownership is sorted."
fi
