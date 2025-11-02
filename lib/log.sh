#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "${OMARCHY_SYNCD_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")")/..}/lib/core.sh"

omarchy_syncd_activity_log_dir() {
	printf '%s\n' "$OMARCHY_SYNCD_STATE_DIR"
}

omarchy_syncd_activity_log_path() {
	printf '%s\n' "$OMARCHY_SYNCD_LOG_PATH"
}
