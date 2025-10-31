#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"

source "$SCRIPT_DIR/chroot.sh"
source "$SCRIPT_DIR/presentation.sh"
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/errors.sh"
