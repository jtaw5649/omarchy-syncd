#!/usr/bin/env bash
# Core bootstrap for omarchy-syncd shell rewrite.
# Sets strict shell options, resolves project paths, and exposes shared helpers.

set -euo pipefail
IFS=$'\n\t'

_omarchy_syncd_resolve_root() {
	local source="${BASH_SOURCE[0]}"
	while [[ -L "$source" ]]; do
		local dir
		dir="$(cd -P -- "$(dirname -- "$source")" && pwd)"
		source="$(readlink "$source")"
		[[ "$source" != /* ]] && source="$dir/$source"
	done
	local script_dir
	script_dir="$(cd -P -- "$(dirname -- "$source")" && pwd)"
	cd -P -- "$script_dir/.." >/dev/null && pwd
}

if [[ -z "${OMARCHY_SYNCD_ROOT:-}" ]]; then
	OMARCHY_SYNCD_ROOT="$(_omarchy_syncd_resolve_root)"
	export OMARCHY_SYNCD_ROOT
fi

export OMARCHY_PATH="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"
export OMARCHY_INSTALL="${OMARCHY_INSTALL:-$OMARCHY_PATH/install}"

export OMARCHY_SYNCD_STATE_DIR="${OMARCHY_SYNCD_STATE_DIR:-$HOME/.local/share/omarchy-syncd}"
export OMARCHY_SYNCD_CONFIG_PATH="${OMARCHY_SYNCD_CONFIG_PATH:-$HOME/.config/omarchy-syncd/config.toml}"
export OMARCHY_SYNCD_LOG_PATH="${OMARCHY_SYNCD_LOG_PATH:-$OMARCHY_SYNCD_STATE_DIR/activity.log}"
export OMARCHY_SYNCD_INSTALL_PREFIX="${OMARCHY_SYNCD_INSTALL_PREFIX:-$HOME/.local/bin}"

omarchy_syncd_require_command() {
	local cmd="$1"
	if ! command -v "$cmd" >/dev/null 2>&1; then
		printf 'error: required command \"%s\" not found in PATH\n' "$cmd" >&2
		exit 1
	fi
}

omarchy_syncd_ensure_parent_dir() {
	local path="$1"
	local dir
	dir="$(dirname -- "$path")"
	mkdir -p -- "$dir"
}

omarchy_syncd_write_log() {
	local level="$1"
	shift
	local message="$*"
	omarchy_syncd_ensure_parent_dir "$OMARCHY_SYNCD_LOG_PATH"
	umask 077
	local timestamp
	timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
	printf '[%s] [%s] %s\n' "$timestamp" "$level" "$message" >>"$OMARCHY_SYNCD_LOG_PATH"
}

omarchy_syncd_tempdir() {
	mktemp -d "${TMPDIR:-/tmp}/omarchy-syncd.XXXXXX"
}

omarchy_syncd_die() {
	local message="$1"
	omarchy_syncd_write_log "ERROR" "$message"
	printf 'error: %s\n' "$message" >&2
	exit 1
}

omarchy_syncd_info() {
	local message="$1"
	omarchy_syncd_write_log "INFO" "$message"
}

omarchy_syncd_warn() {
	local message="$1"
	omarchy_syncd_write_log "WARN" "$message"
	printf 'warning: %s\n' "$message" >&2
}

omarchy_syncd_normalize_list() {
	local ref="$1"
	local -n list_ref="$ref"
	declare -A seen=()
	local item trimmed
	local -a tmp=()
	for item in "${list_ref[@]}"; do
		trimmed="$(printf '%s' "$item" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
		[[ -z "$trimmed" ]] && continue
		if [[ -z "${seen[$trimmed]:-}" ]]; then
			seen[$trimmed]=1
			tmp+=("$trimmed")
		fi
	done
	if ((${#tmp[@]})); then
		mapfile -t tmp < <(printf '%s\n' "${tmp[@]}" | sort)
	fi
	list_ref=("${tmp[@]}")
}
