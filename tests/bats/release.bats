#!/usr/bin/env bats

load './support/assertions'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PROJECT_ROOT

  TMP_DIR="$(mktemp -d)"
  export TMP_DIR
}

teardown() {
  rm -rf "$TMP_DIR"
}

@test "build-release packages runtime layout" {
  run bash -c 'cd "$PROJECT_ROOT" && ./scripts/build-release.sh'

  [ "$status" -eq 0 ]
  version="$(cat "$PROJECT_ROOT/version" 2>/dev/null || echo dev)"
  tarball="$PROJECT_ROOT/dist/omarchy-syncd-$version.tar.gz"
  assert_file_exists "$tarball"

  run tar -tzf "$tarball"
  [ "$status" -eq 0 ]
  assert_output_contains "omarchy-syncd/bin/omarchy-syncd"
  assert_output_contains "omarchy-syncd/lib/core.sh"
  assert_output_contains "omarchy-syncd/install/preflight/bootstrap.sh"
  assert_output_contains "omarchy-syncd/install.sh"
}
