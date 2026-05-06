#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

if [ -x "$ROOT_DIR/android/gradlew" ]; then
  GRADLE="$ROOT_DIR/android/gradlew"
elif [ -x "$ROOT_DIR/../sdk/bubbl-android-sdk/gradlew" ]; then
  GRADLE="$ROOT_DIR/../sdk/bubbl-android-sdk/gradlew"
elif command -v gradle >/dev/null 2>&1; then
  GRADLE="$(command -v gradle)"
else
  echo "No Gradle wrapper or gradle executable found."
  echo "Expected one of:"
  echo "  - android/gradlew"
  echo "  - ../sdk/bubbl-android-sdk/gradlew"
  echo "  - gradle on PATH"
  exit 1
fi

"$GRADLE" -p "$ROOT_DIR/android" testDebugUnitTest
