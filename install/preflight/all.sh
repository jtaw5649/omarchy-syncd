#!/usr/bin/env bash

set -euo pipefail

source "$OMARCHY_SYNCD_INSTALL/preflight/guard.sh"
source "$OMARCHY_SYNCD_INSTALL/preflight/begin.sh"
run_logged "$OMARCHY_SYNCD_INSTALL/preflight/show-env.sh"
run_logged "$OMARCHY_SYNCD_INSTALL/preflight/dependencies.sh"
