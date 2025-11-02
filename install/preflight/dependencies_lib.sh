#!/usr/bin/env bash
set -euo pipefail

omarchy_syncd_dependencies_scan() {
	local line kind pkg
	local -a required=()
	local -a optional=()

	while IFS= read -r line; do
		[[ -z "$line" || "$line" =~ ^# ]] && continue
		IFS=':' read -r kind pkg <<<"$line"
		case "$kind" in
		required) required+=("$pkg") ;;
		optional) optional+=("$pkg") ;;
		esac
	done <"$OMARCHY_SYNCD_INSTALL/preflight/dependencies.packages"

	if [[ -n "${OMARCHY_SYNCD_EXTRA_PACKAGES:-}" ]]; then
		IFS=',' read -ra extras <<<"$OMARCHY_SYNCD_EXTRA_PACKAGES"
		required+=("${extras[@]}")
	fi

	local -a missing_required=()
	local -a missing_optional=()
	for pkg in "${required[@]}"; do
		if ! command -v "$pkg" >/dev/null 2>&1; then
			missing_required+=("$pkg")
		fi
	done

	for pkg in "${optional[@]}"; do
		if ! command -v "$pkg" >/dev/null 2>&1; then
			missing_optional+=("$pkg")
		fi
	done

	OMARCHY_SYNCD_DEPS_REQUIRED=("${required[@]}")
	OMARCHY_SYNCD_DEPS_OPTIONAL=("${optional[@]}")
	OMARCHY_SYNCD_DEPS_MISSING_REQUIRED=("${missing_required[@]}")
	OMARCHY_SYNCD_DEPS_MISSING_OPTIONAL=("${missing_optional[@]}")
}
