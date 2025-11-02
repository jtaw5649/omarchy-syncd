#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=install/preflight/dependencies_lib.sh
source "$OMARCHY_SYNCD_INSTALL/preflight/dependencies_lib.sh"

omarchy_syncd_dependencies_scan

missing_required=("${OMARCHY_SYNCD_DEPS_MISSING_REQUIRED[@]}")
missing_optional=("${OMARCHY_SYNCD_DEPS_MISSING_OPTIONAL[@]}")

if ((${#missing_required[@]} == 0 && ${#missing_optional[@]} == 0)); then
	log_info "All installer dependencies are present."
	exit 0
fi

if ((${#missing_required[@]} > 0)); then
	log_warn "Missing required dependencies: ${missing_required[*]}"
	if [[ "${OMARCHY_SYNCD_AUTO_INSTALL_DEPS:-0}" == "1" ]] && command -v pacman >/dev/null 2>&1; then
		log_info "Attempting to install missing dependencies via pacman."
		if command -v sudo >/dev/null 2>&1; then
			sudo pacman -S --needed --noconfirm "${missing_required[@]}"
		else
			pacman -S --needed --noconfirm "${missing_required[@]}"
		fi
	else
		echo "error: missing dependencies: ${missing_required[*]}. Install them and re-run." >&2
		exit 1
	fi
fi

if ((${#missing_optional[@]} > 0)); then
	log_warn "Optional tools not found: ${missing_optional[*]}"
fi
