#!/usr/bin/env bash

set -euo pipefail

OMARCHY_SYNCD_QR='"'"'
█▀▀▀▀▀█▀ █▄█ ▀▀█▀▄  ▄▀▀▀▀▀█
█ ███ █▄▀▄▀▀█▀▄▀▄█▀█ ███ █
█ ▀▀▀ ████ ▄█▀▄▀▄▀█ █ ▀▀▀ █
▀▀▀▀▀▀▀ █ ▀ █▄█ ▀ █ ▀▀▀▀▀▀▀
▀▀▀█▄▄▀▄█▄ ▄▄█ ▀█▄▄ █▄█  ▀
▀█▄▀█▀ █▀▄▀▄█▄▀█▀█▀▀▀▄█▄▀▄
▀▀▀█▀█▀▀ █▄▄▄▀█▄▀█▄ ▀█▄█ █
▀ ▀ ▄█▀▀▄▀ █▄▀▄▀▀█▀█▄▀██▄█
▀ █▀▀█▀▀▀▀▄ █ █▄▀▀▀▀█▀█▄▄▄
█▀▀▀▀▀█▀▄▀█▀ ▄▄▄█▀ █▄ █▄█▀
█ ███ █ ███▀▀ ▄▄ █▀ ▄▀█▄█▄
█ ▀▀▀ █▀▀▀▀▀▀▄█▄ ▄ ▄▄▄▄▀▀█
▀▀▀▀▀▀▀ ▀▀▀ ▀▀▀▀▀▀ ▀▀▀▀▀▀▀
'"'"'

show_cursor() {
  printf '\033[?25h'
}

save_original_outputs() {
  exec 3>&1 4>&2
}

restore_outputs() {
  exec 1>&3 2>&4
}

show_failed_command() {
  local cmd="${BASH_COMMAND:-unknown}"
  local max_width=$(( LOGO_WIDTH > 4 ? LOGO_WIDTH - 4 : 76 ))
  [[ ${#cmd} -gt $max_width ]] && cmd="${cmd:0:max_width}..."
  if [[ "${OMARCHY_SYNCD_FORCE_NO_GUM:-0}" != "1" ]] && command -v gum >/dev/null 2>&1; then
    gum style "Failed command: $cmd"
  else
    echo "Failed command: $cmd"
  fi
}

catch_errors() {
  local exit_code=$?
  restore_outputs
  clear_logo || true
  show_cursor

  if [[ "${OMARCHY_SYNCD_FORCE_NO_GUM:-0}" != "1" ]] && command -v gum >/dev/null 2>&1; then
    gum style --foreground 1 --padding "1 0 1 ${PADDING_LEFT:-0}" "omarchy-syncd installation stopped!"
    show_failed_command
    gum style "See $OMARCHY_SYNCD_INSTALL_LOG_FILE for full details."
    gum style "$OMARCHY_SYNCD_QR"
    gum style "Need help? Join the community at https://omarchy.org/discord"
    if gum confirm "Retry installation now?"; then
      OMARCHY_SYNCD_BOOTSTRAPPED=1 "$OMARCHY_SYNCD_ROOT/install.sh"
    fi
  else
    echo "omarchy-syncd installation halted (exit code $exit_code)"
    show_failed_command
    echo "See $OMARCHY_SYNCD_INSTALL_LOG_FILE for full details."
  fi

  exit "$exit_code"
}

trap_handlers_setup() {
  save_original_outputs
  trap catch_errors ERR INT TERM
}
