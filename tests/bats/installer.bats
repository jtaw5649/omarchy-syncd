#!/usr/bin/env bats

load './support/assertions'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PROJECT_ROOT

  TMP_DIR="$(mktemp -d)"
  export TMP_DIR

  export HOME="$TMP_DIR/home"
  mkdir -p "$HOME"
}

teardown() {
  rm -rf "$TMP_DIR"
}

make_release_tarball() {
  local tarball="$1"
  local work="$TMP_DIR/release-src/omarchy-syncd"
  mkdir -p "$work"
  cp -R "$PROJECT_ROOT/bin" "$work/bin"
  cp -R "$PROJECT_ROOT/lib" "$work/lib"
  if [[ -d "$PROJECT_ROOT/data" ]]; then
    cp -R "$PROJECT_ROOT/data" "$work/data"
  fi
  cp -R "$PROJECT_ROOT/install" "$work/install"
  cp "$PROJECT_ROOT/install.sh" "$work/install.sh"
  cp "$PROJECT_ROOT/logo.txt" "$work/logo.txt" 2>/dev/null || true
  cp "$PROJECT_ROOT/version" "$work/version" 2>/dev/null || true
  (cd "$TMP_DIR/release-src" && tar -czf "$tarball" omarchy-syncd)
}

prepare_stage_root() {
  local stage="$1"
  mkdir -p "$stage/install"
  cp "$PROJECT_ROOT/install.sh" "$stage/install.sh"
  cp -R "$PROJECT_ROOT/install/." "$stage/install/"
}

@test "bootstrap hydrates runtime from release tarball" {
  stage_root="$TMP_DIR/stage-release"
  prepare_stage_root "$stage_root"

  release_tar="$TMP_DIR/release.tar.gz"
  make_release_tarball "$release_tar"

  run env \
    OMARCHY_SYNCD_ROOT="$stage_root" \
    OMARCHY_SYNCD_INSTALL="$stage_root/install" \
    OMARCHY_SYNCD_STATE_DIR="$TMP_DIR/state" \
    OMARCHY_SYNCD_INSTALL_LOG_FILE="$TMP_DIR/install.log" \
    OMARCHY_SYNCD_RELEASE_URL="file://$release_tar" \
    bash -c 'set -euo pipefail; source "$OMARCHY_SYNCD_INSTALL/helpers/errors.sh"; source "$OMARCHY_SYNCD_INSTALL/helpers/logging.sh"; source "$OMARCHY_SYNCD_INSTALL/preflight/bootstrap.sh"'

  [ "$status" -eq 0 ]
  assert_file_exists "$stage_root/bin/omarchy-syncd"
  assert_file_exists "$stage_root/lib/core.sh"
}

@test "bootstrap falls back to git clone when release unavailable" {
  stage_root="$TMP_DIR/stage-source"
  prepare_stage_root "$stage_root"

  origin="$TMP_DIR/origin.git"
  git init --bare "$origin" >/dev/null
  work="$TMP_DIR/origin-work"
  git clone "$origin" "$work" >/dev/null
  cp -R "$PROJECT_ROOT/bin" "$work/bin"
  cp -R "$PROJECT_ROOT/lib" "$work/lib"
  cp -R "$PROJECT_ROOT/install" "$work/install"
  cp "$PROJECT_ROOT/install.sh" "$work/install.sh"
  cp "$PROJECT_ROOT/logo.txt" "$work/logo.txt" 2>/dev/null || true
  cp "$PROJECT_ROOT/version" "$work/version" 2>/dev/null || true
  (
    cd "$work"
    git add . >/dev/null
    git commit -m "seed" >/dev/null
    git push origin HEAD >/dev/null
  )
  rm -rf "$work"

  run env \
    OMARCHY_SYNCD_ROOT="$stage_root" \
    OMARCHY_SYNCD_INSTALL="$stage_root/install" \
    OMARCHY_SYNCD_STATE_DIR="$TMP_DIR/state" \
    OMARCHY_SYNCD_INSTALL_LOG_FILE="$TMP_DIR/install.log" \
    OMARCHY_SYNCD_RELEASE_URL="file://$TMP_DIR/missing.tar.gz" \
    OMARCHY_SYNCD_SOURCE_URL="$origin" \
    bash -c 'set -euo pipefail; source "$OMARCHY_SYNCD_INSTALL/helpers/errors.sh"; source "$OMARCHY_SYNCD_INSTALL/helpers/logging.sh"; source "$OMARCHY_SYNCD_INSTALL/preflight/bootstrap.sh"'

  [ "$status" -eq 0 ]
  assert_file_exists "$stage_root/bin/omarchy-syncd"
  assert_file_exists "$stage_root/lib/core.sh"
}
