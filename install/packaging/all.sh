#!/usr/bin/env bash
set -euo pipefail

run_logged "$OMARCHY_SYNCD_INSTALL/packaging/paths.sh"
run_logged "$OMARCHY_SYNCD_INSTALL/packaging/runtime.sh"
run_logged "$OMARCHY_SYNCD_INSTALL/packaging/binary.sh"
run_logged "$OMARCHY_SYNCD_INSTALL/packaging/helpers.sh"
if [[ -f "$OMARCHY_SYNCD_INSTALL/packaging/icon.sh" ]]; then
	run_logged "$OMARCHY_SYNCD_INSTALL/packaging/icon.sh"
fi
