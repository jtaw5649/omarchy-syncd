#!/usr/bin/env bats

load './support/assertions'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PROJECT_ROOT
  TMP_DIR="$(mktemp -d)"
  export TMP_DIR

  export OMARCHY_SYNCD_ROOT="$PROJECT_ROOT"
  export OMARCHY_SYNCD_CONFIG_PATH="$TMP_DIR/config.toml"
  export OMARCHY_SYNCD_STATE_DIR="$TMP_DIR/state"
  export OMARCHY_SYNCD_LOG_PATH="$TMP_DIR/activity.log"

  export GIT_AUTHOR_NAME="Test User"
  export GIT_AUTHOR_EMAIL="test@example.com"
  export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
  export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

  PATH="$PROJECT_ROOT/bin:$PATH"
}

teardown() {
  rm -rf "$TMP_DIR"
}

make_origin_with_branch() {
  local dir="$1"
  local work="$TMP_DIR/worktree"
  mkdir -p "$dir"
  git init --bare "$dir" >/dev/null
  git init "$work" >/dev/null
  pushd "$work" >/dev/null
  git remote add origin "$dir"
  git branch -M main >/dev/null 2>&1 || git checkout -b main >/dev/null
  echo "init" >README.md
  git add README.md
  git commit -m "Initial commit" >/dev/null
  git push origin main >/dev/null
  popd >/dev/null
  rm -rf "$work"
}

@test "config --print-path uses override" {
  run omarchy-syncd config --print-path
  [ "$status" -eq 0 ]
  [ "$output" = "$OMARCHY_SYNCD_CONFIG_PATH" ]
}

@test "config --create initializes file with header" {
  run omarchy-syncd config --create
  [ "$status" -eq 0 ]
  [[ "$output" == "Created config at "* ]]
  [ -f "$OMARCHY_SYNCD_CONFIG_PATH" ]
  run cat "$OMARCHY_SYNCD_CONFIG_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == "# omarchy-syncd configuration"* ]]
}

@test "config --write with defaults writes bundle list" {
  run omarchy-syncd config --write --repo-url git@example.com/repo.git --branch main --include-defaults
  [ "$status" -eq 0 ]
  [[ "$output" == "Wrote config to "* ]]
  run grep -E '^url = "git@example.com/repo.git"$' "$OMARCHY_SYNCD_CONFIG_PATH"
  [ "$status" -eq 0 ]
  run grep -E '^bundles = \[$' "$OMARCHY_SYNCD_CONFIG_PATH"
  [ "$status" -eq 0 ]
  run grep -E '"core_desktop"' "$OMARCHY_SYNCD_CONFIG_PATH"
  [ "$status" -eq 0 ]
}

@test "config --write prunes duplicate paths from bundles" {
  run omarchy-syncd config --write \
    --repo-url git@example.com/repo.git \
    --bundle core_desktop \
    --path ~/.config/hypr
  [ "$status" -eq 0 ]
  run grep -E '"core_desktop"' "$OMARCHY_SYNCD_CONFIG_PATH"
  [ "$status" -eq 0 ]
  run grep -E '^paths = \[$' "$OMARCHY_SYNCD_CONFIG_PATH"
  [ "$status" -eq 0 ]
  # Paths array should be empty block.
  ! grep -E '"~/.config/hypr"' "$OMARCHY_SYNCD_CONFIG_PATH"
}

@test "config --write rejects unknown bundle ids" {
  run omarchy-syncd config --write --repo-url git@example.com/repo.git --bundle not_real
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown bundle ids"* ]]
}

@test "config --write with verify-remote validates git refs" {
  make_origin_with_branch "$TMP_DIR/origin.git"
  run omarchy-syncd config --write \
    --repo-url "$TMP_DIR/origin.git" \
    --branch main \
    --verify-remote \
    --bundle system
  [ "$status" -eq 0 ]
}
