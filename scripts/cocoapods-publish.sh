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

is_pod_version_published() {
  pod_name="$1"
  pod_version="$2"
  curl -fsSI "https://trunk.cocoapods.org/api/v1/pods/${pod_name}/specs/${pod_version}" >/dev/null 2>&1
}

push_podspec_with_retry() {
  pod_name="$1"
  podspec_path="$2"
  pod_version="$3"

  if is_pod_version_published "$pod_name" "$pod_version"; then
    echo "${pod_name} ${pod_version} is already published on CocoaPods trunk; skipping."
    return 0
  fi

  attempt=1
  max_attempts=3
  while [ "$attempt" -le "$max_attempts" ]; do
    echo "Publishing ${pod_name} ${pod_version} to CocoaPods trunk (attempt ${attempt}/${max_attempts})."
    if pod trunk push "$podspec_path" --allow-warnings --verbose; then
      return 0
    fi

    if is_pod_version_published "$pod_name" "$pod_version"; then
      echo "${pod_name} ${pod_version} is now visible on CocoaPods trunk after a failed response; treating as published."
      return 0
    fi

    if [ "$attempt" -eq "$max_attempts" ]; then
      echo "Failed to publish ${pod_name} ${pod_version} after ${max_attempts} attempts."
      return 1
    fi

    sleep_seconds=$((attempt * 20))
    echo "Retrying ${pod_name} ${pod_version} in ${sleep_seconds}s."
    sleep "$sleep_seconds"
    attempt=$((attempt + 1))
  done
}

push_podspec_with_retry "BubblSDK" "build/cocoapods/BubblSDK.podspec" "$VERSION"

if [ "${BUBBL_COCOAPODS_ALIAS_RELEASE:-false}" = "true" ]; then
  push_podspec_with_retry "Bubbl-Sdk" "build/cocoapods/Bubbl-Sdk.podspec" "$VERSION"
else
  echo "Skipping Bubbl-Sdk alias publish. Set BUBBL_COCOAPODS_ALIAS_RELEASE=true after alias ownership is sorted."
fi
