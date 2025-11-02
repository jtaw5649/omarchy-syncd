#!/usr/bin/env bats

load './support/assertions'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PROJECT_ROOT
}

@test "installer handles gum selection via PTY" {
  run "$PROJECT_ROOT/tests/support/run_expect.sh" "$PROJECT_ROOT/tests/interactive/install_select.exp"
  [ "$status" -eq 0 ]
}

@test "installer cancel path reports failure" {
  run "$PROJECT_ROOT/tests/support/run_expect.sh" "$PROJECT_ROOT/tests/interactive/install_cancel.exp"
  [ "$status" -eq 0 ]
}

@test "installer numeric fallback" {
  run "$PROJECT_ROOT/tests/support/run_expect.sh" "$PROJECT_ROOT/tests/interactive/install_numeric.exp"
  [ "$status" -eq 0 ]
}

@test "installer non-interactive args" {
  run "$PROJECT_ROOT/tests/support/run_expect.sh" "$PROJECT_ROOT/tests/interactive/install_noninteractive.exp"
  [ "$status" -eq 0 ]
}

@test "installer placeholder failure" {
  run "$PROJECT_ROOT/tests/support/run_expect.sh" "$PROJECT_ROOT/tests/interactive/install_missing_repo.exp"
  [ "$status" -eq 0 ]
}
