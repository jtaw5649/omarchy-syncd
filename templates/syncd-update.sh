#!/usr/bin/env bash

set -euo pipefail

STATE_DIR="${OMARCHY_SYNCD_STATE_DIR:-${HOME}/.local/share/omarchy-syncd}"
LOGO_PATH="${OMARCHY_SYNCD_LOGO_PATH:-$STATE_DIR/logo.txt}"
UPDATE_URL="${OMARCHY_SYNCD_UPDATE_URL:-https://raw.githubusercontent.com/jtaw5649/omarchy-syncd/master/install.sh}"

PRESENTATION_TERMINAL="${OMARCHY_SYNCD_LAUNCHER_TERMINAL:-alacritty}"

show_logo() {
  if [[ -f "$LOGO_PATH" ]]; then
    if [[ "${OMARCHY_SYNCD_FORCE_NO_GUM:-0}" != "1" ]] && command -v gum >/dev/null 2>&1; then
      gum style --foreground 2 --margin "1 0" "$(<"$LOGO_PATH")"
    else
      printf '\033[32m'
      cat "$LOGO_PATH"
      printf '\033[0m\n\n'
    fi
  fi
}

confirm_update() {
  if [[ "${OMARCHY_SYNCD_ALLOW_NON_INTERACTIVE:-0}" != "1" && ! -t 0 ]]; then
    echo "error: update requires interaction when run outside presentation mode." >&2
    return 1
  fi
  if [[ "${OMARCHY_SYNCD_ASSUME_YES:-0}" == "1" ]]; then
    return 0
  fi
  if [[ "${OMARCHY_SYNCD_FORCE_NO_GUM:-0}" != "1" ]] && command -v gum >/dev/null 2>&1; then
    gum style --border normal --border-foreground 6 --padding "1 2" --margin "1 0" \
      "Ready to update Omarchy Syncd?" \
      "" \
      "• You cannot stop the update once you start!" \
      "• Make sure you're not on battery power or have sufficient charge"
    gum confirm --default=false "Continue with update?"
  else
    echo "Ready to update omarchy-syncd?"
    echo "• You cannot stop the update once you start!"
    echo "• Make sure you're not on battery power or have sufficient charge."
    local answer
    read -r -p "Continue with update? [y/N] " answer || return 1
    answer=${answer,,}
    [[ "$answer" == "y" || "$answer" == "yes" ]]
  fi
}

perform_update() {
  if [[ -n "${OMARCHY_SYNCD_UPDATE_COMMAND:-}" ]]; then
    OMARCHY_SYNCD_FORCE_PLATFORM="${OMARCHY_SYNCD_FORCE_PLATFORM:-}" \
      OMARCHY_SYNCD_SKIP_PLATFORM_CHECK="${OMARCHY_SYNCD_SKIP_PLATFORM_CHECK:-}" \
      OMARCHY_SYNCD_FORCE_NO_GUM="${OMARCHY_SYNCD_FORCE_NO_GUM:-}" \
      bash -c "${OMARCHY_SYNCD_UPDATE_COMMAND}"
    return
  fi
  if ! command -v curl >/dev/null 2>&1; then
    echo "error: curl is required to fetch the installer." >&2
    exit 1
  fi
  OMARCHY_SYNCD_FORCE_PLATFORM="${OMARCHY_SYNCD_FORCE_PLATFORM:-}" \
    OMARCHY_SYNCD_SKIP_PLATFORM_CHECK="${OMARCHY_SYNCD_SKIP_PLATFORM_CHECK:-}" \
    OMARCHY_SYNCD_FORCE_NO_GUM="${OMARCHY_SYNCD_FORCE_NO_GUM:-}" \
    bash -c "curl -fsSL '$UPDATE_URL' | bash"
}

if [[ -z "${OMARCHY_SYNCD_LAUNCHED_WITH_PRESENTATION:-}" ]]; then
  if [[ "${OMARCHY_SYNCD_FORCE_NO_GUM:-0}" != "1" && -n "$PRESENTATION_TERMINAL" && -z "${OMARCHY_SYNCD_INHIBIT_LAUNCH:-}" ]]; then
    exec setsid uwsm-app -- omarchy-syncd-launcher OMARCHY_SYNCD_LAUNCHED_WITH_PRESENTATION=1 "$0"
  fi
fi

show_logo

if confirm_update; then
  perform_update
else
  if [[ "${OMARCHY_SYNCD_FORCE_NO_GUM:-0}" != "1" ]] && command -v gum >/dev/null 2>&1; then
    gum style "Update cancelled"
    gum style "Done! Press any key to close..."
    if [[ -t 0 ]]; then
      read -r -n1 -s
    fi
  else
    echo "Update cancelled"
  fi
fi
