#!/usr/bin/env bash

codemagic_slack_step="${1:-Codemagic step}"

notify_codemagic_slack_failure() {
  local exit_code="$?"
  STATUS=failure \
  CI_PROVIDER=Codemagic \
  TITLE="Bubbl iOS SDK release" \
  STEP_NAME="$codemagic_slack_step" \
  RUN_URL="https://codemagic.io/app/${CM_PROJECT_ID:-}/build/${CM_BUILD_ID:-}" \
  REF_NAME="${CM_TAG:-${CM_BRANCH:-}}" \
  SHA="${CM_COMMIT:-}" \
  node scripts/notify-slack.mjs || true
  exit "$exit_code"
}

trap notify_codemagic_slack_failure ERR
