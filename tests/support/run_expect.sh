#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$PROJECT_ROOT/tests/support/utils.bash"
setup_install_env
export PATH="$PROJECT_ROOT/bin:$PATH"

cleanup() {
  if [[ -n "${HOME:-}" && -d "$HOME" ]]; then
    rm -rf "$HOME"
  fi
}
trap cleanup EXIT

script="$1"
shift
expect "$script" "$PROJECT_ROOT" "$@"
