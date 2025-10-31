#!/usr/bin/env bash

set -euo pipefail

if [[ ! -f "$OMARCHY_SYNCD_BIN_SOURCE" ]]; then
  echo "error: build artifact missing at $OMARCHY_SYNCD_BIN_SOURCE" >&2
  exit 1
fi

install -m 755 "$OMARCHY_SYNCD_BIN_SOURCE" "$OMARCHY_SYNCD_BIN_DIR/omarchy-syncd"
