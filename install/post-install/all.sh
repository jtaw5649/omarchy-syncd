#!/usr/bin/env bash
set -euo pipefail

if [[ -f "$OMARCHY_SYNCD_INSTALL/post-install/elephant.sh" ]]; then
	run_logged "$OMARCHY_SYNCD_INSTALL/post-install/elephant.sh"
fi
run_logged "$OMARCHY_SYNCD_INSTALL/post-install/summary.sh"
