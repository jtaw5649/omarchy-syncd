#!/usr/bin/env bash

set -euo pipefail

run_logged "$OMARCHY_SYNCD_INSTALL/config/paths.sh"
run_logged "$OMARCHY_SYNCD_INSTALL/config/legacy.sh"
