#!/usr/bin/env bash

set -euo pipefail

OMARCHY_SYNCD_LOGO_PATH="${OMARCHY_SYNCD_LOGO_PATH:-$OMARCHY_SYNCD_ROOT/logo.txt}"

ensure_gum() {
  if [[ "${OMARCHY_SYNCD_FORCE_NO_GUM:-0}" == "1" ]]; then
    return 1
  fi

  if command -v gum >/dev/null 2>&1; then
    return 0
  fi

  if command -v sudo >/dev/null 2>&1 && command -v pacman >/dev/null 2>&1; then
    sudo pacman -S --needed --noconfirm gum >/dev/null 2>&1 || true
  fi

  command -v gum >/dev/null 2>&1
}

if ensure_gum; then
  if [[ -e /dev/tty ]]; then
    term_size=$(stty size </dev/tty 2>/dev/null || echo "")
  else
    term_size=""
  fi

  if [[ -n "$term_size" ]]; then
    export TERM_HEIGHT=$(echo "$term_size" | cut -d' ' -f1)
    export TERM_WIDTH=$(echo "$term_size" | cut -d' ' -f2)
  else
    export TERM_WIDTH=120
    export TERM_HEIGHT=36
  fi

  export LOGO_WIDTH=$(awk '{ if (length > max) max = length } END { print max+0 }' "$OMARCHY_SYNCD_LOGO_PATH" 2>/dev/null || echo 0)
  export LOGO_HEIGHT=$(wc -l <"$OMARCHY_SYNCD_LOGO_PATH" 2>/dev/null || echo 0)

  export PADDING_LEFT=$(((TERM_WIDTH - LOGO_WIDTH) / 2))
  if (( PADDING_LEFT < 0 )); then
    PADDING_LEFT=0
  fi
  printf -v PADDING_LEFT_SPACES "%*s" "$PADDING_LEFT" ""

  export GUM_CONFIRM_PROMPT_FOREGROUND="6"
  export GUM_CONFIRM_SELECTED_FOREGROUND="0"
  export GUM_CONFIRM_SELECTED_BACKGROUND="2"
  export GUM_CONFIRM_UNSELECTED_FOREGROUND="7"
  export GUM_CONFIRM_UNSELECTED_BACKGROUND="0"
  export PADDING="0 0 0 0"
  export GUM_CONFIRM_PADDING="$PADDING"
  export GUM_CHOOSE_PADDING="$PADDING"
  export GUM_INPUT_PADDING="$PADDING"
  export GUM_FILTER_PADDING="$PADDING"
  export GUM_SPIN_PADDING="$PADDING"
else
  export LOGO_WIDTH=0
  export LOGO_HEIGHT=0
  export PADDING_LEFT=0
  export PADDING_LEFT_SPACES=""
  export PADDING="0 0 0 0"
  export GUM_CONFIRM_PADDING="$PADDING"
  export GUM_CHOOSE_PADDING="$PADDING"
  export GUM_INPUT_PADDING="$PADDING"
  export GUM_FILTER_PADDING="$PADDING"
  export GUM_SPIN_PADDING="$PADDING"
  unset GUM_CONFIRM_PROMPT_WIDTH
fi

clear_logo() {
  if [[ "${OMARCHY_SYNCD_FORCE_NO_GUM:-0}" == "1" ]]; then
    return
  fi

  printf '\033[H\033[2J\033[32m'
  if [[ -f "$OMARCHY_SYNCD_LOGO_PATH" ]]; then
    cat "$OMARCHY_SYNCD_LOGO_PATH"
  fi
  printf '\033[0m\n'
}

gum_panel() {
  local message=("$@")
  if [[ "${OMARCHY_SYNCD_FORCE_NO_GUM:-0}" == "1" ]] || ! command -v gum >/dev/null 2>&1; then
    printf '%s\n' "${message[@]}"
    return
  fi

  gum style --border normal --border-foreground 6 --padding "1 2" --margin "1 0" --align left "${message[@]}"
}

gum_section() {
  local message=("$@")
  if [[ "${OMARCHY_SYNCD_FORCE_NO_GUM:-0}" == "1" ]] || ! command -v gum >/dev/null 2>&1; then
    printf '%s\n' "${message[@]}"
    return
  fi

  gum style --foreground 6 --margin "1 0" --align left "${message[@]}"
}
