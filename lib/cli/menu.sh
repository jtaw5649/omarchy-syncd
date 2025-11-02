#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "${OMARCHY_SYNCD_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")")/../..}/lib/core.sh"
source "$OMARCHY_SYNCD_ROOT/lib/update.sh"
source "$OMARCHY_SYNCD_ROOT/lib/ui.sh"

usage() {
	cat <<'USAGE'
Usage: omarchy-syncd menu

Launch the interactive Omarchy Syncd menu. Respects OMARCHY_SYNCD_MENU_CHOICE
for non-interactive selection.
USAGE
}

build_menu_choices() {
	local -n entries_ref="$1"
	local max_len=0
	local entry
	for entry in "${entries_ref[@]}"; do
		local title="${entry%%|*}"
		if ((${#title} > max_len)); then
			max_len=${#title}
		fi
	done

	local -a formatted=()
	for entry in "${entries_ref[@]}"; do
		local id="${entry%%|*}"
		local rest="${entry#*|}"
		local title="${rest%%|*}"
		local desc="${rest#*|}"
		formatted+=("${id}|$(printf "%-${max_len}s  %s" "$title" "$desc")")
	done
	printf '%s\n' "${formatted[@]}"
}

run_subcommand() {
	local cmd="$1"
	shift || true
	if [[ "$cmd" == "update" ]]; then
		if command -v omarchy-syncd-update >/dev/null 2>&1; then
			exec omarchy-syncd-update "$@"
		else
			omarchy_syncd_die "update helper 'omarchy-syncd-update' not found"
		fi
	else
		OMARCHY_SYNCD_INVOCATION="$cmd" exec "$OMARCHY_SYNCD_ROOT/bin/omarchy-syncd" "$cmd" "$@"
	fi
}

main() {
	if [[ $# -gt 0 ]]; then
		case "$1" in
		-h | --help)
			usage
			return 0
			;;
		*)
			omarchy_syncd_die "unknown option '$1'"
			;;
		esac
	fi

	local update_version=""
	if update_version="$(omarchy_syncd_update_check)"; then
		omarchy_syncd_info "menu: update available $update_version"
	else
		update_version=""
	fi

	local -a entries=(
		"install|Install|Configure bundles and paths"
		"backup|Backup|Snapshot configured paths to remote repo"
		"restore|Restore|Restore paths from remote repo"
		"config|Config|Inspect or edit configuration"
		"uninstall|Uninstall|Remove omarchy-syncd and config"
	)

	if [[ -n "$update_version" ]]; then
		entries=("update|Update|Upgrade to version $update_version" "${entries[@]}")
	fi

	local predefined="${OMARCHY_SYNCD_MENU_CHOICE:-}"
	if [[ -n "$predefined" ]]; then
		omarchy_syncd_info "menu: env selection $predefined"
		case "$predefined" in
		update)
			if [[ -z "$update_version" ]]; then
				omarchy_syncd_warn "menu: update requested but no update available"
				return 0
			fi
			run_subcommand "update"
			;;
		install | backup | restore | config | uninstall)
			run_subcommand "$predefined"
			;;
		*)
			omarchy_syncd_die "Unknown selection $predefined"
			;;
		esac
		return 0
	fi

	local -a formatted=()
	mapfile -t formatted < <(build_menu_choices entries)

	local selection=""
	if [[ ${#formatted[@]} -eq 0 ]]; then
		omarchy_syncd_die "No menu entries available."
	fi

	selection="$(omarchy_syncd_ui_single_select "Omarchy Syncd (type to filter) >" "Enter runs selection · Esc cancels" formatted)" || return 1
	omarchy_syncd_info "menu: user selected $selection"

	case "$selection" in
	update)
		if [[ -z "$update_version" ]]; then
			omarchy_syncd_warn "menu: update chosen but not available"
			return 0
		fi
		run_subcommand "update"
		;;
	install | backup | restore | config | uninstall)
		run_subcommand "$selection"
		;;
	*)
		omarchy_syncd_die "Unknown selection $selection"
		;;
	esac
}

main "$@"
