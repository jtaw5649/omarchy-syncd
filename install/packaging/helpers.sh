#!/usr/bin/env bash

set -euo pipefail

wrapper_src="$OMARCHY_SYNCD_ROOT/scripts/omarchy-syncd-wrapper.sh"
if [[ ! -f "$wrapper_src" ]]; then
  log_error "CLI wrapper missing at $wrapper_src; cannot deploy helper shims"
  exit 1
fi

helper_basenames=(
  "omarchy-syncd-menu"
  "omarchy-syncd-install"
  "omarchy-syncd-backup"
  "omarchy-syncd-restore"
  "omarchy-syncd-config"
  "omarchy-syncd-uninstall"
)

for helper in "${helper_basenames[@]}"; do
  install -m 755 "$wrapper_src" "$OMARCHY_SYNCD_BIN_DIR/$helper"
  install -m 755 "$wrapper_src" "$OMARCHY_SYNCD_BIN_DIR/${helper}.sh"
  log_info "Installed helper wrapper $helper (and .sh shim) to $OMARCHY_SYNCD_BIN_DIR"
done

if [[ -d "$OMARCHY_SYNCD_ROOT/bin" ]]; then
  while IFS= read -r -d '' file; do
    target_name=$(basename "$file")
    install -m 755 "$file" "$OMARCHY_SYNCD_BIN_DIR/$target_name"
    log_info "Deployed packaged binary helper $target_name to $OMARCHY_SYNCD_BIN_DIR"
  done < <(find "$OMARCHY_SYNCD_ROOT/bin" -type f -print0)
fi
