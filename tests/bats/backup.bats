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

  export GIT_AUTHOR_NAME="Test User"
  export GIT_AUTHOR_EMAIL="test@example.com"
  export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
  export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

  PATH="$PROJECT_ROOT/bin:$PATH"
}

teardown() {
  rm -rf "$TMP_DIR"
}

@test "backup commits configured paths to origin" {
  mkdir -p "$HOME/.config/foo"
  echo "value" >"$HOME/.config/foo/file.txt"

  origin="$TMP_DIR/origin.git"
  mkdir -p "$origin"
  git -C "$origin" init --bare >/dev/null
  git -C "$origin" symbolic-ref HEAD refs/heads/main >/dev/null

  run omarchy-syncd config --write --repo-url "$origin" --branch main --path "$HOME/.config/foo"
  [ "$status" -eq 0 ]

  run omarchy-syncd backup --all --no-ui --message "Sync config"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Backup complete."* ]]

  git -C "$TMP_DIR" clone "$origin" repo-clone-backup >/dev/null
  run git -C "$TMP_DIR/repo-clone-backup" rev-list --count HEAD
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
  run cat "$TMP_DIR/repo-clone-backup/.config/foo/file.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "value" ]
}

@test "backup skips missing paths gracefully" {
  origin="$TMP_DIR/origin.git"
  mkdir -p "$origin"
  git -C "$origin" init --bare >/dev/null
  git -C "$origin" symbolic-ref HEAD refs/heads/main >/dev/null

  run omarchy-syncd config --write --repo-url "$origin" --branch main --path "$HOME/.config/missing"
  [ "$status" -eq 0 ]

  run omarchy-syncd backup --all --no-ui
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping $HOME/.config/missing"* ]]

  git -C "$TMP_DIR" clone "$origin" repo-clone-missing >/dev/null
  run git -C "$TMP_DIR/repo-clone-missing" rev-list --count HEAD
  [ "$status" -ne 0 ]
}

@test "backup rejects placeholder repo" {
  run omarchy-syncd config --write --repo-url "https://example.com/your-private-repo.git" --branch main --include-defaults
  [ "$status" -eq 0 ]

  run omarchy-syncd backup --all --no-ui
  [ "$status" -ne 0 ]
  [[ "$output" == *"placeholder repository URL"* ]]
}
