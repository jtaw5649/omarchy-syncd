#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(
  cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd -P
)"

BIN="$SCRIPT_DIR/omarchy-syncd"
if [[ ! -x "$BIN" ]]; then
  BIN="omarchy-syncd"
fi

base="$(basename "$0")"
base_no_ext="${base%.sh}"

case "$base_no_ext" in
  omarchy-syncd-menu)
    exec "$BIN" menu "$@"
    ;;
  omarchy-syncd-install)
    exec "$BIN" install "$@"
    ;;
  omarchy-syncd-backup)
    exec "$BIN" backup "$@"
    ;;
  omarchy-syncd-restore)
    exec "$BIN" restore "$@"
    ;;
  omarchy-syncd-config)
    exec "$BIN" config "$@"
    ;;
  omarchy-syncd-uninstall)
    exec "$BIN" uninstall "$@"
    ;;
  *)
    exec "$BIN" "$@"
    ;;
esac
