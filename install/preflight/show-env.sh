#!/usr/bin/env bash

set -euo pipefail

log_info "User: $(whoami)"
log_info "Home: $HOME"
log_info "State dir: $OMARCHY_SYNCD_STATE_DIR"
log_info "Binary dir: $OMARCHY_SYNCD_BIN_DIR"
log_info "Installer log path: $OMARCHY_SYNCD_INSTALL_LOG_FILE"
