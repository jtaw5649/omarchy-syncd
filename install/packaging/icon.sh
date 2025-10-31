#!/usr/bin/env bash

set -euo pipefail

if [[ -f "$OMARCHY_SYNCD_ROOT/icon.png" ]]; then
  install -m 644 "$OMARCHY_SYNCD_ROOT/icon.png" "$OMARCHY_SYNCD_ICON_DIR/omarchy-syncd.png"
  log_info "Copied launcher icon to $OMARCHY_SYNCD_ICON_DIR/omarchy-syncd.png"
else
  log_warn "icon.png not found; skipping icon install"
fi
