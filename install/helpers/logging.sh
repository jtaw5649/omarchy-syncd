#!/usr/bin/env bash

set -euo pipefail

OMARCHY_SYNCD_STATE_DIR="${OMARCHY_SYNCD_STATE_DIR:-$HOME/.local/share/omarchy-syncd}"
DEFAULT_LOG_FILE="/var/log/omarchy-syncd-install.log"

if [[ -w "$(dirname "$DEFAULT_LOG_FILE")" ]]; then
  OMARCHY_SYNCD_INSTALL_LOG_FILE="${OMARCHY_SYNCD_INSTALL_LOG_FILE:-$DEFAULT_LOG_FILE}"
else
  OMARCHY_SYNCD_INSTALL_LOG_FILE="${OMARCHY_SYNCD_INSTALL_LOG_FILE:-$OMARCHY_SYNCD_STATE_DIR/install.log}"
fi
export OMARCHY_SYNCD_INSTALL_LOG_FILE

mkdir -p "$OMARCHY_SYNCD_STATE_DIR"

ANSI_HIDE_CURSOR="\033[?25l"
ANSI_SHOW_CURSOR="\033[?25h"
ANSI_SAVE_CURSOR="\0337"
ANSI_RESTORE_CURSOR="\0338"

start_log_output() {
  if [[ "${OMARCHY_SYNCD_FORCE_NO_GUM:-0}" == "1" ]]; then
    return
  fi
  if ! command -v gum >/dev/null 2>&1; then
    return
  fi
  if [[ ! -t 1 ]]; then
    return
  fi

  printf '%s%s' "$ANSI_SAVE_CURSOR" "$ANSI_HIDE_CURSOR"
  (
    local log_lines=20
    local max_width=$(( LOGO_WIDTH > 4 ? LOGO_WIDTH - 4 : 76 ))
    local log_margin=${OMARCHY_SYNCD_LOG_MARGIN:-2}
    while true; do
      mapfile -t current_lines < <(tail -n "$log_lines" "$OMARCHY_SYNCD_INSTALL_LOG_FILE" 2>/dev/null)
      printf '\033[H\033[J'
      if [[ -f "$OMARCHY_SYNCD_LOGO_PATH" ]]; then
        gum style --foreground 2 "$(<"$OMARCHY_SYNCD_LOGO_PATH")"
        echo
      fi
      for line in "${current_lines[@]}"; do
        if (( ${#line} > max_width )); then
          line="${line:0:max_width}..."
        fi
        gum style --align left --margin "0 0 0 ${log_margin}" "$line"
      done
      sleep 1
    done
  ) &
  OMARCHY_SYNCD_LOG_STREAM_PID=$!
}

stop_log_output() {
  local restored=0
  if [[ -n "${OMARCHY_SYNCD_LOG_STREAM_PID:-}" ]]; then
    kill "$OMARCHY_SYNCD_LOG_STREAM_PID" >/dev/null 2>&1 || true
    wait "$OMARCHY_SYNCD_LOG_STREAM_PID" 2>/dev/null || true
    unset OMARCHY_SYNCD_LOG_STREAM_PID
    restored=1
  fi
  if (( restored == 1 )); then
    printf '%s%s' "$ANSI_RESTORE_CURSOR" "$ANSI_SHOW_CURSOR"
  fi
}

run_logged() {
  local script="$1"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] Starting: $script" >>"$OMARCHY_SYNCD_INSTALL_LOG_FILE"
  bash -c "source '$script'" </dev/null >>"$OMARCHY_SYNCD_INSTALL_LOG_FILE" 2>&1
  local exit_code=$?
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  if [[ $exit_code -eq 0 ]]; then
    echo "[$timestamp] Completed: $script" >>"$OMARCHY_SYNCD_INSTALL_LOG_FILE"
  else
    echo "[$timestamp] Failed: $script (exit code $exit_code)" >>"$OMARCHY_SYNCD_INSTALL_LOG_FILE"
  fi
  return $exit_code
}

start_install_log() {
  if [[ "$OMARCHY_SYNCD_INSTALL_LOG_FILE" == "$DEFAULT_LOG_FILE" ]]; then
    sudo install -m 666 -D /dev/null "$OMARCHY_SYNCD_INSTALL_LOG_FILE"
  else
    install -m 600 -D /dev/null "$OMARCHY_SYNCD_INSTALL_LOG_FILE"
  fi
  local start_time
  start_time=$(date '+%Y-%m-%d %H:%M:%S')
  {
    echo "=== omarchy-syncd install started: $start_time ==="
    echo
  } >>"$OMARCHY_SYNCD_INSTALL_LOG_FILE"
  if [[ "${OMARCHY_SYNCD_SHOW_INSTALL_LOG:-0}" == "1" ]]; then
    start_log_output
  fi
}

stop_install_log() {
  if [[ -n "${OMARCHY_SYNCD_SHOW_INSTALL_LOG:-}" ]]; then
    stop_log_output
  fi
  if [[ -n "${OMARCHY_SYNCD_INSTALL_LOG_FILE:-}" ]]; then
    local end_time
    end_time=$(date '+%Y-%m-%d %H:%M:%S')
    {
      echo
      echo "=== omarchy-syncd install finished: $end_time ==="
      echo
    } >>"$OMARCHY_SYNCD_INSTALL_LOG_FILE"
  fi
}
