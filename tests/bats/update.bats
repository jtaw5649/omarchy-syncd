#!/usr/bin/env bats

load './support/assertions'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PROJECT_ROOT

  TMP_DIR="$(mktemp -d)"
  export TMP_DIR

  export HOME="$TMP_DIR/home"
  mkdir -p "$HOME"

  export OMARCHY_SYNCD_ROOT="$PROJECT_ROOT"
  export OMARCHY_SYNCD_STATE_DIR="$TMP_DIR/state"
  export OMARCHY_SYNCD_LOG_PATH="$TMP_DIR/activity.log"

  PATH="$PROJECT_ROOT/bin:$PATH"
}

teardown() {
  rm -rf "$TMP_DIR"
}

@test "update helper runs custom command when OMARCHY_SYNCD_UPDATE_COMMAND set" {
  export OMARCHY_SYNCD_ALLOW_NON_INTERACTIVE=1
  export OMARCHY_SYNCD_ASSUME_YES=1
  export OMARCHY_SYNCD_LAUNCHED_WITH_PRESENTATION=1
  export OMARCHY_SYNCD_UPDATE_COMMAND="printf 'custom update'"

  run omarchy-syncd-update

  [ "$status" -eq 0 ]
  assert_output_contains "custom update"
}

@test "update helper fails gracefully when curl missing" {
  export OMARCHY_SYNCD_ALLOW_NON_INTERACTIVE=1
  export OMARCHY_SYNCD_ASSUME_YES=1
  export OMARCHY_SYNCD_LAUNCHED_WITH_PRESENTATION=1
  export OMARCHY_SYNCD_UPDATE_URL="https://example.com/install.sh"

  stub_path="$TMP_DIR/no-curl"
  mkdir -p "$stub_path"
  for cmd in env bash cat printf echo rm mkdir; do
    if command -v "$cmd" >/dev/null 2>&1; then
      ln -sf "$(command -v "$cmd")" "$stub_path/$cmd"
    fi
  done
  ln -sf "$PROJECT_ROOT/bin/omarchy-syncd-update" "$stub_path/omarchy-syncd-update"
  ORIG_PATH="$PATH"
  PATH="$stub_path"

  run omarchy-syncd-update

  [ "$status" -ne 0 ]
  assert_output_contains "error: curl is required"

  PATH="$ORIG_PATH"
}
