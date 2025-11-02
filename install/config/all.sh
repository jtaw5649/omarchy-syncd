#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${OMARCHY_SYNCD_INSTALL_TTY:-}" ]]; then
	RUN_LOGGED_TTY="$OMARCHY_SYNCD_INSTALL_TTY" RUN_LOGGED_PRESERVE_STDIN=1 run_logged "$OMARCHY_SYNCD_INSTALL/config/run-cli.sh"
else
	run_logged "$OMARCHY_SYNCD_INSTALL/config/run-cli.sh"
fi
