#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
BIN="$SCRIPT_DIR/omarchy-syncd"
if [[ ! -x "$BIN" ]]; then
  BIN="omarchy-syncd"
fi

exec "$BIN" menu "$@"
