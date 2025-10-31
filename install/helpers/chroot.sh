#!/usr/bin/env bash

# Enable a unit immediately unless we are running inside a chroot install.
chrootable_systemctl_enable() {
  if [[ -n "${OMARCHY_SYNCD_CHROOT_INSTALL:-}" ]]; then
    sudo systemctl enable "$1"
  else
    sudo systemctl enable --now "$1"
  fi
}

export -f chrootable_systemctl_enable
