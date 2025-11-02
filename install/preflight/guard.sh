#!/usr/bin/env bash

set -euo pipefail

if [[ $EUID -eq 0 ]]; then
	echo "error: omarchy-syncd installer must be run as a normal user." >&2
	exit 1
fi
