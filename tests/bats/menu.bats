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
paths = [
  "/tmp/path"
]
bundles = []
EOF_CFG

  PATH="$PROJECT_ROOT/bin:$PATH"
}

teardown() {
  rm -rf "$TMP_DIR"
}

@test "menu honours OMARCHY_SYNCD_MENU_CHOICE" {
  OMARCHY_SYNCD_MENU_CHOICE=backup run omarchy-syncd menu
  [ "$status" -ne 0 ]
  [[ "$output" == *"error:"* && "$output" == *"git clone failed"* ]]
}

@test "menu --help prints usage" {
  run omarchy-syncd menu --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: omarchy-syncd menu"* ]]
}

@test "menu update entry triggers update helper" {
  tmp_helper="$TMP_DIR/bin/omarchy-syncd-update"
  mkdir -p "$TMP_DIR/bin"
  cat <<'EOF_HELPER' > "$tmp_helper"
#!/usr/bin/env bash
printf 'update helper invoked\n'
EOF_HELPER
  chmod +x "$tmp_helper"
  PATH="$TMP_DIR/bin:$PATH"
  OMARCHY_SYNCD_MENU_CHOICE=update OMARCHY_SYNCD_FORCE_UPDATE_VERSION=2.0.0 run omarchy-syncd menu
  [ "$status" -eq 0 ]
}
