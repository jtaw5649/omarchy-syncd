#!/usr/bin/env bash

set -euo pipefail

if [[ -f "$OMARCHY_SYNCD_ROOT/logo.txt" ]]; then
  install -m 644 "$OMARCHY_SYNCD_ROOT/logo.txt" "$OMARCHY_SYNCD_STATE_DIR/logo.txt"
else
  echo "warning: logo.txt not found; skipping logo install" >&2
fi
