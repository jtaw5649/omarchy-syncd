#!/usr/bin/env bash

set -euo pipefail

legacy_dir="$HOME/.config/syncd"
target_dir="$HOME/.config/omarchy-syncd"

if [[ -d "$legacy_dir" && ! -e "$target_dir/config.toml" ]]; then
  mkdir -p "$target_dir"
  if [[ -f "$legacy_dir/config.toml" ]]; then
    mv "$legacy_dir/config.toml" "$target_dir/config.toml"
    echo "Migrated legacy config.toml from $legacy_dir"
  fi
  if [[ -d "$legacy_dir" && -z "$(ls -A "$legacy_dir")" ]]; then
    rmdir "$legacy_dir" || true
  fi
fi
