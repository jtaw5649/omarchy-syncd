#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=install/helpers/errors.sh
source "$OMARCHY_SYNCD_INSTALL/helpers/errors.sh"
# shellcheck source=install/helpers/logging.sh
source "$OMARCHY_SYNCD_INSTALL/helpers/logging.sh"
if [[ -f "$OMARCHY_SYNCD_INSTALL/helpers/presentation.sh" ]]; then
	# shellcheck source=install/helpers/presentation.sh
	source "$OMARCHY_SYNCD_INSTALL/helpers/presentation.sh"
fi
