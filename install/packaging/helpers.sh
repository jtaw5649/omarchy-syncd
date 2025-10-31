#!/usr/bin/env bash

set -euo pipefail

helper_basenames=(
  "omarchy-syncd-menu"
  "omarchy-syncd-install"
  "omarchy-syncd-backup"
  "omarchy-syncd-restore"
  "omarchy-syncd-config"
  "omarchy-syncd-uninstall"
)

for helper in "${helper_basenames[@]}"; do
  local_src="$OMARCHY_SYNCD_ROOT/scripts/${helper}.sh"
  if [[ ! -f "$local_src" ]]; then
    echo "warning: missing helper $local_src; skipping" >&2
    continue
  fi
  install -m 755 "$local_src" "$OMARCHY_SYNCD_BIN_DIR/${helper}.sh"
  install -m 755 "$local_src" "$OMARCHY_SYNCD_BIN_DIR/$helper"
  done

if [[ -d "$OMARCHY_SYNCD_ROOT/bin" ]]; then
  while IFS= read -r -d '' file; do
    target_name=$(basename "$file")
    install -m 755 "$file" "$OMARCHY_SYNCD_BIN_DIR/$target_name"
  done < <(find "$OMARCHY_SYNCD_ROOT/bin" -type f -print0)
fi
