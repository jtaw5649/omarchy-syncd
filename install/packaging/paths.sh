#!/usr/bin/env bash

set -euo pipefail

mkdir -p "$OMARCHY_SYNCD_BIN_DIR"
mkdir -p "$OMARCHY_SYNCD_STATE_DIR"
mkdir -p "$OMARCHY_SYNCD_ICON_DIR"
log_info "Ensured install directories: bin=$OMARCHY_SYNCD_BIN_DIR state=$OMARCHY_SYNCD_STATE_DIR icon=$OMARCHY_SYNCD_ICON_DIR"
