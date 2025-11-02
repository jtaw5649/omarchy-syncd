#!/usr/bin/env bash

set -euo pipefail

OMARCHY_SYNCD_STATE_DIR="${OMARCHY_SYNCD_STATE_DIR:-$HOME/.local/share/omarchy-syncd}"
DEFAULT_LOG_FILE="${OMARCHY_SYNCD_STATE_DIR}/install.log"

OMARCHY_SYNCD_INSTALL_LOG_FILE="${OMARCHY_SYNCD_INSTALL_LOG_FILE:-$DEFAULT_LOG_FILE}"
export OMARCHY_SYNCD_INSTALL_LOG_FILE

mkdir -p "$OMARCHY_SYNCD_STATE_DIR"

_omarchy_syncd_ensure_log_file() {
	if [[ -z "${OMARCHY_SYNCD_INSTALL_LOG_FILE:-}" ]]; then
		return 1
	fi
	local log_dir
	log_dir=$(dirname "$OMARCHY_SYNCD_INSTALL_LOG_FILE")
	mkdir -p "$log_dir"
	if [[ ! -e "$OMARCHY_SYNCD_INSTALL_LOG_FILE" ]]; then
		install -m 600 -D /dev/null "$OMARCHY_SYNCD_INSTALL_LOG_FILE"
	fi
}

_omarchy_syncd_log_line() {
	local level="$1"
	shift || true
	local message="$*"
	[[ -z "${message}" ]] && return 0
	if ! _omarchy_syncd_ensure_log_file; then
		return 0
	fi
	local timestamp
	timestamp=$(date '+%Y-%m-%d %H:%M:%S')
	printf '[%s] [%s] %s\n' "$timestamp" "$level" "$message" >>"$OMARCHY_SYNCD_INSTALL_LOG_FILE"
}

log_info() {
	_omarchy_syncd_log_line "INFO" "$@"
}

log_warn() {
	_omarchy_syncd_log_line "WARN" "$@"
}

log_error() {
	_omarchy_syncd_log_line "ERROR" "$@"
}

run_logged() {
	local script="$1"
	local script_name
	script_name="$(basename "$script")"
	log_info "Starting stage ${script_name}"

	local preserve_stdin="${RUN_LOGGED_PRESERVE_STDIN:-0}"
	local -a bash_cmd
	bash_cmd=(
		bash -euo pipefail -c
		"source \"$OMARCHY_SYNCD_INSTALL/helpers/logging.sh\"; source \"\$1\""
		run_logged
		"$script"
	)

	local exit_code
	if [[ "$preserve_stdin" == "1" && -n "${RUN_LOGGED_TTY:-}" && -e "${RUN_LOGGED_TTY}" ]]; then
		"${bash_cmd[@]}" <>"$RUN_LOGGED_TTY" 2>&0
		exit_code=$?
	else
		"${bash_cmd[@]}" </dev/null >>"$OMARCHY_SYNCD_INSTALL_LOG_FILE" 2>&1
		exit_code=$?
	fi
	unset RUN_LOGGED_PRESERVE_STDIN
	unset RUN_LOGGED_TTY
	if [[ $exit_code -eq 0 ]]; then
		log_info "Completed stage ${script_name}"
	else
		log_error "Stage ${script_name} failed with exit code $exit_code"
	fi
	return $exit_code
}

start_install_log() {
	_omarchy_syncd_ensure_log_file
	local start_time
	start_time=$(date '+%Y-%m-%d %H:%M:%S')
	{
		echo
		echo "=== omarchy-syncd install started: $start_time ==="
		echo
	} >>"$OMARCHY_SYNCD_INSTALL_LOG_FILE"
	log_info "Install log initialised at $OMARCHY_SYNCD_INSTALL_LOG_FILE"
}

stop_install_log() {
	if [[ -n "${OMARCHY_SYNCD_INSTALL_LOG_FILE:-}" ]]; then
		local end_time
		end_time=$(date '+%Y-%m-%d %H:%M:%S')
		{
			echo
			echo "=== omarchy-syncd install finished: $end_time ==="
			echo
		} >>"$OMARCHY_SYNCD_INSTALL_LOG_FILE"
		log_info "Install log closed"
	fi
}
