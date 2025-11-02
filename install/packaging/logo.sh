#!/usr/bin/env bash

set -euo pipefail

if [[ -f "$OMARCHY_SYNCD_ROOT/logo.txt" ]]; then
	install -m 644 "$OMARCHY_SYNCD_ROOT/logo.txt" "$OMARCHY_SYNCD_STATE_DIR/logo.txt"
	log_info "Copied Omarchy logo to $OMARCHY_SYNCD_STATE_DIR/logo.txt"
else
	log_warn "logo.txt not found; skipping logo install"
fi
