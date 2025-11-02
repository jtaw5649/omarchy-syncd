#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "${OMARCHY_SYNCD_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")")/..}/lib/core.sh"

omarchy_syncd_require_command curl

UPDATE_CHECK_URL="https://raw.githubusercontent.com/jtaw5649/omarchy-syncd/master/version"

omarchy_syncd_update_check() {
	local forced="${OMARCHY_SYNCD_FORCE_UPDATE_VERSION:-}"
	if [[ -n "$forced" ]]; then
		printf '%s\n' "$forced"
		return 0
	fi

	local current="${OMARCHY_SYNCD_INSTALLED_VERSION:-}"
	if [[ -z "$current" ]]; then
		current="$(cat "$OMARCHY_SYNCD_ROOT/version" 2>/dev/null || true)"
	fi

	local latest
	if ! latest="$(curl -fsSL "$UPDATE_CHECK_URL" 2>/dev/null | tr -d '[:space:]')" || [[ -z "$latest" ]]; then
		omarchy_syncd_warn "update: failed to fetch remote version"
		return 1
	fi

	if [[ -z "$current" ]]; then
		printf '%s\n' "$latest"
	elif [[ "$latest" != "$current" ]]; then
		printf '%s\n' "$latest"
	else
		return 1
	fi
}
