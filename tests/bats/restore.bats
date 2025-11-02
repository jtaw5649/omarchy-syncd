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

make_origin() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init --bare >/dev/null
  git -C "$dir" symbolic-ref HEAD refs/heads/main >/dev/null
}

seed_backup_repo() {
  local origin="$1"
  make_origin "$origin"

  mkdir -p "$HOME/.config/foo"
  echo "value" >"$HOME/.config/foo/file.txt"
  ln -s file.txt "$HOME/.config/foo/link.txt"

  run omarchy-syncd config --write --repo-url "$origin" --branch main --path "$HOME/.config/foo"
  [ "$status" -eq 0 ]

  run omarchy-syncd backup --all --no-ui --message "Seed"
  [ "$status" -eq 0 ]
}

@test "restore copies files and recreates symlinks" {
  origin="$TMP_DIR/origin.git"
  seed_backup_repo "$origin"

  rm -rf "$HOME/.config/foo"

  run omarchy-syncd restore --all --no-ui
  [ "$status" -eq 0 ]
  [[ "$output" == *"Restore complete."* ]]

  [ -f "$HOME/.config/foo/file.txt" ]
  [ "$(cat "$HOME/.config/foo/file.txt")" = "value" ]
  [ -L "$HOME/.config/foo/link.txt" ]
  [[ "$(basename "$(readlink "$HOME/.config/foo/link.txt")")" = "file.txt" ]]
  [ -f "$HOME/.config/omarchy-syncd/symlinks.json" ]
}

@test "restore skips missing repo paths" {
  origin="$TMP_DIR/origin.git"
  make_origin "$origin"

  run omarchy-syncd config --write --repo-url "$origin" --branch main --path "$HOME/.config/missing"
  [ "$status" -eq 0 ]

  run omarchy-syncd restore --all --no-ui
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping $HOME/.config/missing"* ]]
}

@test "restore rejects placeholder repo" {
  run omarchy-syncd config --write --repo-url "https://example.com/your-private-repo.git" --branch main --include-defaults
  [ "$status" -eq 0 ]

  run omarchy-syncd restore --all --no-ui
  [ "$status" -ne 0 ]
  [[ "$output" == *"placeholder repository URL"* ]]
}

@test "restore overwrites existing files" {
  origin="$TMP_DIR/origin.git"
  seed_backup_repo "$origin"

  echo "local" >"$HOME/.config/foo/file.txt"

  run omarchy-syncd restore --all --no-ui

  [ "$status" -eq 0 ]
  [[ "$(cat "$HOME/.config/foo/file.txt")" == "value" ]]
}

@test "restore triggers hyprctl reload when available" {
  origin="$TMP_DIR/origin.git"
  seed_backup_repo "$origin"

  stub_dir="$TMP_DIR/bin"
  mkdir -p "$stub_dir"
  stub_log="$TMP_DIR/hyprctl.log"
  cat >"$stub_dir/hyprctl" <<EOF
#!/usr/bin/env bash
echo "\$@" >>"$stub_log"
EOF
  chmod +x "$stub_dir/hyprctl"

  PATH="$stub_dir:$PATH"
  run omarchy-syncd restore --all --no-ui

  [ "$status" -eq 0 ]
  assert_file_exists "$stub_log"
  run cat "$stub_log"
  [ "$status" -eq 0 ]
  assert_output_contains "reload"
}
