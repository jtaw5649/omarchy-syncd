#!/usr/bin/env bash

set -euo pipefail

runtime_bin="$OMARCHY_SYNCD_RUNTIME_DIR/bin/omarchy-syncd"
if [[ ! -x "$runtime_bin" ]]; then
	log_error "binary: runtime dispatcher missing at $runtime_bin"
	exit 1
fi

ln -sfn "$runtime_bin" "$OMARCHY_SYNCD_BIN_DIR/omarchy-syncd"
if declare -F log_info >/dev/null 2>&1; then
	log_info "binary: linked omarchy-syncd to $runtime_bin"
fi
