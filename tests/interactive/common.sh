#!/usr/bin/env bash
set -euo pipefail

export TERM="xterm-256color"

function setup_install_env() {
  TMP_HOME="$(mktemp -d)"
  export HOME="$TMP_HOME"
  export OMARCHY_SYNCD_NO_FLOAT=1
  export OMARCHY_SYNCD_INSTALL_PREFIX="$TMP_HOME/.local/bin"
  export OMARCHY_SYNCD_STATE_DIR="$TMP_HOME/.local/share/omarchy-syncd"
  export OMARCHY_SYNCD_ICON_DIR="$TMP_HOME/.local/share/icons"
  export OMARCHY_SYNCD_CONFIG_PATH="$TMP_HOME/.config/omarchy-syncd/config.toml"
}

function run_expect() {
  local script="$1"
  shift
  expect "$script" "$@"
}
