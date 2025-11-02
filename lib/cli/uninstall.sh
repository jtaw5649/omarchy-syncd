#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "${OMARCHY_SYNCD_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")")/../..}/lib/core.sh"
source "$OMARCHY_SYNCD_ROOT/lib/config.sh"

usage() {
	cat <<'USAGE'
Usage: omarchy-syncd uninstall [options]

Options:
      --yes   Skip confirmation prompt.
  -h, --help  Show this help message.
USAGE
}

confirm() {
	local prompt="$1"
	if [[ ! -t 0 ]]; then
		return 1
	fi
	read -r -p "$prompt [y/N] " answer || return 1
	case "${answer,,}" in
	y | yes) return 0 ;;
	*) return 1 ;;
	esac
}

remove_if_exists() {
	local path="$1"
	if [[ -e "$path" || -L "$path" ]]; then
		rm -rf -- "$path"
		omarchy_syncd_info "uninstall: removed $path"
	fi
}

stop_elephant() {
	if ! command -v pgrep >/dev/null 2>&1 || ! command -v pkill >/dev/null 2>&1; then
		return 0
	fi
	if pgrep -x elephant >/dev/null 2>&1; then
		if pkill -x elephant >/dev/null 2>&1; then
			omarchy_syncd_info "uninstall: stopped Elephant process"
		else
			omarchy_syncd_warn "uninstall: failed to stop Elephant process; please restart it manually"
		fi
	fi
}

remove_elephant_menu() {
	local menu_path="$HOME/.config/elephant/menus/omarchy-syncd.toml"
	if [[ -f "$menu_path" ]]; then
		rm -f -- "$menu_path"
		omarchy_syncd_info "uninstall: removed Elephant menu at $menu_path"
	fi
	local menu_dir
	menu_dir="$(dirname "$menu_path")"
	if [[ -d "$menu_dir" ]]; then
		rmdir "$menu_dir" >/dev/null 2>&1 || true
	fi
}

remove_icon() {
	local icon_path="${OMARCHY_SYNCD_ICON_DIR:-$HOME/.local/share/icons}/omarchy-syncd.png"
	if [[ -f "$icon_path" ]]; then
		rm -f -- "$icon_path"
		omarchy_syncd_info "uninstall: removed icon at $icon_path"
	fi
}

cleanup_state() {
	local runtime_dir="${OMARCHY_SYNCD_RUNTIME_DIR:-${OMARCHY_SYNCD_STATE_DIR:-$HOME/.local/share/omarchy-syncd}/runtime}"
	remove_if_exists "$runtime_dir"
	if [[ -n "${OMARCHY_SYNCD_LOG_PATH:-}" ]]; then
		rm -f -- "$OMARCHY_SYNCD_LOG_PATH"
	fi
	if [[ -n "${OMARCHY_SYNCD_INSTALL_LOG_FILE:-}" ]]; then
		rm -f -- "$OMARCHY_SYNCD_INSTALL_LOG_FILE"
	fi
	if [[ -n "${OMARCHY_SYNCD_STATE_DIR:-}" ]]; then
		remove_if_exists "$OMARCHY_SYNCD_STATE_DIR"
	fi
}

reload_hypr() {
	if command -v hyprctl >/dev/null 2>&1; then
		if hyprctl reload >/dev/null 2>&1; then
			omarchy_syncd_info "uninstall: triggered hyprctl reload"
		else
			omarchy_syncd_warn "uninstall: hyprctl reload failed"
		fi
	fi
}

main() {
	local assume_yes=false

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--yes) assume_yes=true ;;
		-h | --help)
			usage
			return 0
			;;
		*)
			omarchy_syncd_die "unknown option '$1'"
			;;
		esac
		shift
	done

	if [[ "$assume_yes" == "false" ]]; then
		if ! confirm "This will remove omarchy-syncd completely. Continue?"; then
			printf 'Uninstall cancelled.\n'
			omarchy_syncd_info "uninstall: cancelled by user"
			return 0
		fi
	fi

	stop_elephant

	local bin_dir="${OMARCHY_SYNCD_INSTALL_PREFIX}"
	local helpers=(
		"omarchy-syncd-menu"
		"omarchy-syncd-install"
		"omarchy-syncd-backup"
		"omarchy-syncd-restore"
		"omarchy-syncd-config"
		"omarchy-syncd-uninstall"
		"omarchy-syncd-menu.sh"
		"omarchy-syncd-install.sh"
		"omarchy-syncd-backup.sh"
		"omarchy-syncd-restore.sh"
		"omarchy-syncd-config.sh"
		"omarchy-syncd-uninstall.sh"
		"omarchy-syncd-show-logo"
		"omarchy-syncd-show-done"
		"omarchy-syncd-launcher"
		"omarchy-syncd-update"
	)
	local helper
	for helper in "${helpers[@]}"; do
		remove_if_exists "$bin_dir/$helper"
	done
	remove_if_exists "$bin_dir/omarchy-syncd"

	local config_dir
	config_dir="$(omarchy_syncd_config_path)"
	remove_if_exists "$config_dir"

	local config_parent
	config_parent="$(dirname "$config_dir")"
	if [[ "$(basename "$config_parent")" == "omarchy-syncd" ]]; then
		remove_if_exists "$config_parent"
	fi

	remove_if_exists "$HOME/.config/omarchy-syncd"
	remove_elephant_menu
	remove_icon
	cleanup_state
	reload_hypr

	printf 'omarchy-syncd has been uninstalled.\n'
	omarchy_syncd_info "uninstall: completed"
}

main "$@"
