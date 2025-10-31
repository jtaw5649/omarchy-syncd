#!/usr/bin/env bash

set -euo pipefail

echo "User: $(whoami)"
echo "Home: $HOME"
echo "State dir: $OMARCHY_SYNCD_STATE_DIR"
echo "Binary dir: $OMARCHY_SYNCD_BIN_DIR"
echo "Installer log: $OMARCHY_SYNCD_INSTALL_LOG_FILE"
