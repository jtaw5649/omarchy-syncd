#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=install/preflight/guard.sh
source "$OMARCHY_SYNCD_INSTALL/preflight/guard.sh"
# shellcheck source=install/preflight/begin.sh
source "$OMARCHY_SYNCD_INSTALL/preflight/begin.sh"
run_logged "$OMARCHY_SYNCD_INSTALL/preflight/show-env.sh"
run_logged "$OMARCHY_SYNCD_INSTALL/preflight/bootstrap.sh"
run_logged "$OMARCHY_SYNCD_INSTALL/preflight/dependencies.sh"
