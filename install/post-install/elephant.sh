#!/usr/bin/env bash

set -euo pipefail

menu_dir="$HOME/.config/elephant/menus"
menu_path="$menu_dir/omarchy-syncd.toml"
mkdir -p "$menu_dir"

tmp=$(mktemp)
cat >"$tmp" <<EOF_MENU
# Managed by omarchy-syncd
name = "omarchy-syncd"
name_pretty = "Omarchy Syncd"
icon = "${ICON_DEST}"
global_search = true
action = "launch"

[actions]
launch = "${OMARCHY_SYNCD_BIN_DIR}/omarchy-syncd-menu"

[[entries]]
text = "Omarchy Syncd"
keywords = ["backup", "restore", "install", "config"]
terminal = true
EOF_MENU

if [[ -f "$menu_path" && ! $(grep -q "# Managed by omarchy-syncd" "$menu_path") ]]; then
  log_warn "Overwriting unmanaged Elephant menu at $menu_path"
fi

if ! cmp -s "$tmp" "$menu_path" >/dev/null 2>&1; then
  mv "$tmp" "$menu_path"
  log_info "Elephant menu updated at $menu_path"
else
  rm -f "$tmp"
  log_info "Elephant menu already up to date at $menu_path"
fi

if pgrep -x elephant >/dev/null 2>&1; then
  if command -v elephant >/dev/null 2>&1; then
    if pkill -x elephant >/dev/null 2>&1; then
      nohup elephant >/dev/null 2>&1 &
      log_info "Restarted Elephant to reload menu entries"
    else
      log_warn "Failed to stop running Elephant process; please restart it manually"
    fi
  else
    log_warn "Elephant process detected but executable not found in PATH; skipping automatic restart"
  fi
else
  log_info "Elephant not running; no reload necessary"
fi
