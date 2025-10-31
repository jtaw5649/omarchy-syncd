#!/usr/bin/env bash

clear
if [[ -f "${OMARCHY_SYNCD_LOGO_PATH:-$HOME/.local/share/omarchy-syncd/logo.txt}" ]]; then
  echo -e "\033[32m"
  cat "${OMARCHY_SYNCD_LOGO_PATH:-$HOME/.local/share/omarchy-syncd/logo.txt}"
  echo -e "\033[0m"
  echo
fi
