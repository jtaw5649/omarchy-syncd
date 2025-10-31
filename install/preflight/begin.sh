#!/usr/bin/env bash

set -euo pipefail

clear_logo || true
start_install_log
log_info "Preflight initialised; logging to $OMARCHY_SYNCD_INSTALL_LOG_FILE"
trap_handlers_setup
