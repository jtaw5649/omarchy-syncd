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
  export OMARCHY_SYNCD_CONFIG_PATH="$TMP_DIR/config.toml"
  export OMARCHY_SYNCD_STATE_DIR="$TMP_DIR/state"
  export OMARCHY_SYNCD_LOG_PATH="$TMP_DIR/activity.log"

  cat <<'EOF_CFG' > "$OMARCHY_SYNCD_CONFIG_PATH"
[repo]
url = "git@example.com/repo.git"
branch = "main"

[files]
paths = []
bundles = []
EOF_CFG

  export PATH="$PROJECT_ROOT/bin:$PATH"
}

teardown() {
  rm -rf "$TMP_DIR"
}

@test "install writes selection to config" {
  run omarchy-syncd install --force --bundle core_desktop --path "$HOME/.config/custom"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Saved selection"* ]]
  run grep -E '"core_desktop"' "$OMARCHY_SYNCD_CONFIG_PATH"
  [ "$status" -eq 0 ]
  run grep -E "$HOME/.config/custom" "$OMARCHY_SYNCD_CONFIG_PATH"
  [ "$status" -eq 0 ]
}

@test "install dry-run does not modify config" {
  before="$(cat "$OMARCHY_SYNCD_CONFIG_PATH")"
  run omarchy-syncd install --dry-run --bundle system --path "$HOME/.config/other"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dry run"* ]]
  after="$(cat "$OMARCHY_SYNCD_CONFIG_PATH")"
  [ "$before" = "$after" ]
}

@test "install without selections fails" {
  run omarchy-syncd install
  [ "$status" -ne 0 ]
  [[ "$output" == *"No bundles or paths selected"* ]]
}
