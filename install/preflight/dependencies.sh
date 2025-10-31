#!/usr/bin/env bash

set -euo pipefail

missing=()
for cmd in git tar curl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    missing+=("$cmd")
  fi
done

if ((${#missing[@]} > 0)); then
  echo "Missing required commands: ${missing[*]}" >&2
  echo "Install them with 'sudo pacman -S ${missing[*]}' and rerun the installer." >&2
  exit 1
fi

if [[ "${OMARCHY_SYNCD_FORCE_NO_GUM:-0}" != "1" ]] && ! command -v gum >/dev/null 2>&1; then
  echo "gum not found; UI will degrade gracefully. Install with 'sudo pacman -S gum' for full experience." >&2
fi
