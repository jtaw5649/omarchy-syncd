#!/usr/bin/env bash
set -euo pipefail

#
# Wrapper used by launchers (Walker, Hyprland bindings, etc.) to open the
# interactive dotfile selector introduced by `omarchy-syncd install`.
#

BIN_NAME=${OMARCHY_SYNCD_BIN:-omarchy-syncd}

if ! command -v "$BIN_NAME" >/dev/null 2>&1; then
  echo "error: $BIN_NAME not found on PATH. Install omarchy-syncd first." >&2
  exit 1
fi

exec "$BIN_NAME" install "$@"
