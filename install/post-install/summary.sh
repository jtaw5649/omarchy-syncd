#!/usr/bin/env bash
set -euo pipefail

summary_lines=(
	"omarchy-syncd binaries installed to $OMARCHY_SYNCD_BIN_DIR"
	"State directory: $OMARCHY_SYNCD_STATE_DIR"
	"Run 'omarchy-syncd menu' to get started."
)

summary_text=$(printf '%s\n' "${summary_lines[@]}")

if [[ "${OMARCHY_SYNCD_SKIP_POST_SUMMARY:-0}" == "1" ]]; then
	log_info "post-install: summary skipped"
	exit 0
fi

if [[ "${GUM_NO_COLOR:-0}" == "1" ]]; then
	printf '\nInstall Complete\n\n'
	printf '%s\n' "$summary_text"
else
	gum style --border normal --border-foreground 6 --padding "1 2" --margin "1 0" "Install Complete" "$summary_text"
fi

gum spin --spinner globe --title "Done! Press any key to close..." -- bash -lc 'read -n 1 -s'

log_info "post-install: summary delivered"
