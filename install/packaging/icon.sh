#!/usr/bin/env bash

set -euo pipefail

dest="$OMARCHY_SYNCD_ICON_DIR/omarchy-syncd.png"

if [[ -f "$OMARCHY_SYNCD_ROOT/icon.png" ]]; then
	install -m 644 "$OMARCHY_SYNCD_ROOT/icon.png" "$dest"
	export ICON_DEST="$dest"
	log_info "Copied launcher icon to $dest"
else
	unset ICON_DEST
	log_warn "icon.png not found; skipping icon install"
fi
