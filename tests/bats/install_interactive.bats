#!/usr/bin/env bats

load './support/assertions'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PROJECT_ROOT
  TMP_DIR="$(mktemp -d)"
  export TMP_DIR
  export HOME="$TMP_DIR/home"
  mkdir -p "$HOME"
  export OMARCHY_SYNCD_NO_FLOAT=1
  export OMARCHY_SYNCD_INSTALL_PREFIX="$TMP_DIR/bin"
  export OMARCHY_SYNCD_STATE_DIR="$TMP_DIR/state"
  export OMARCHY_SYNCD_ICON_DIR="$TMP_DIR/icons"
  export OMARCHY_SYNCD_CONFIG_PATH="$TMP_DIR/config.toml"
  export PATH="$PROJECT_ROOT/bin:$PATH"
}

teardown() {
  rm -rf "$TMP_DIR"
}

@test "install creates placeholder config when none exists" {
  run bash -lc "OMARCHY_SYNCD_NON_INTERACTIVE=1 OMARCHY_SYNCD_INSTALL_ARGS='--bundle core_desktop' \"$PROJECT_ROOT/install.sh\""
  [ "$status" -eq 0 ]
  assert_file_exists "$OMARCHY_SYNCD_CONFIG_PATH"
  assert_file_contains "$OMARCHY_SYNCD_CONFIG_PATH" "core_desktop"
}

@test "non-interactive install without selection fails" {
  run bash -lc "OMARCHY_SYNCD_NON_INTERACTIVE=1 \"$PROJECT_ROOT/install.sh\""
  [ "$status" -ne 0 ]
}
