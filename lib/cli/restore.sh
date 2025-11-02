#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "${OMARCHY_SYNCD_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")")/../..}/lib/core.sh"

source "$OMARCHY_SYNCD_ROOT/lib/config.sh"
source "$OMARCHY_SYNCD_ROOT/lib/git.sh"
source "$OMARCHY_SYNCD_ROOT/lib/fs.sh"
source "$OMARCHY_SYNCD_ROOT/lib/ui.sh"

usage() {
	cat <<'USAGE'
Usage: omarchy-syncd restore [options]

Options:
      --path <path>     Restore only the given path (repeatable).
      --all             Restore all configured paths without prompting.
      --no-ui           Disable interactive selector even if running in a TTY.
  -h, --help            Show this help message.
USAGE
}

validate_paths() {
	local -n resolved_ref="$1"
	local -n selected_ref="$2"

	declare -A known=()
	local item
	for item in "${resolved_ref[@]}"; do
		known["$item"]=1
	done
	for item in "${selected_ref[@]}"; do
		if [[ -z "${known[$item]:-}" ]]; then
			omarchy_syncd_die "Path $item is not part of the configured restore set. Use 'omarchy-syncd install' to add it first."
		fi
	done
}

maybe_hypr_reload() {
	if command -v hyprctl >/dev/null 2>&1; then
		hyprctl reload >/dev/null 2>&1 || omarchy_syncd_warn "restore: hyprctl reload failed"
	fi
}

main() {
	local select_all=false
	local no_ui=false
	local -a explicit_paths=()

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--path)
			[[ $# -ge 2 ]] || omarchy_syncd_die "--path requires a value"
			explicit_paths+=("$2")
			shift
			;;
		--all) select_all=true ;;
		--no-ui) no_ui=true ;;
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

	omarchy_syncd_config_require
	local repo_url
	repo_url="$(omarchy_syncd_config_repo_url)"
	if [[ -z "$repo_url" ]]; then
		omarchy_syncd_die "repository URL missing from configuration"
	fi
	if omarchy_syncd_config_repo_is_placeholder; then
		omarchy_syncd_die "configuration still uses the placeholder repository URL. Edit '$OMARCHY_SYNCD_CONFIG_PATH' and set 'repo.url' before running restore."
	fi
	local branch
	branch="$(omarchy_syncd_config_repo_branch)"

	local -a resolved_paths=()
	mapfile -t resolved_paths < <(omarchy_syncd_config_resolved_paths)
	if [[ ${#resolved_paths[@]} -eq 0 ]]; then
		omarchy_syncd_die "no configured paths found. Run 'omarchy-syncd install' or 'omarchy-syncd config --write ...' first."
	fi

	omarchy_syncd_normalize_list explicit_paths
	local -a selected_paths=()
	if [[ ${#explicit_paths[@]} -gt 0 ]]; then
		validate_paths resolved_paths explicit_paths
		selected_paths=("${explicit_paths[@]}")
	else
		selected_paths=("${resolved_paths[@]}")
	fi

	local is_tty=false
	if [[ -t 0 && -t 1 ]]; then
		is_tty=true
	fi

	if [[ ${#explicit_paths[@]} -eq 0 && "$select_all" == "false" && "$no_ui" == "false" && "$is_tty" == "true" ]]; then
		local -a choices=()
		local path
		for path in "${resolved_paths[@]}"; do
			choices+=("$path|$path")
		done
		local -a selection=()
		if mapfile -t selection < <(omarchy_syncd_ui_multi_select "Restore paths (type to filter) >" "Tab toggles, Shift+Tab selects all, Enter confirms, Esc cancels" choices); then
			if [[ ${#selection[@]} -gt 0 ]]; then
				selected_paths=("${selection[@]}")
			fi
		fi
	elif [[ "$select_all" == "true" ]]; then
		selected_paths=("${resolved_paths[@]}")
	fi

	omarchy_syncd_normalize_list selected_paths
	if [[ ${#selected_paths[@]} -eq 0 ]]; then
		selected_paths=("${resolved_paths[@]}")
	fi

	omarchy_syncd_info "restore: preparing to copy ${#selected_paths[@]} paths"

	local workspace
	workspace="$(omarchy_syncd_tempdir)"
	trap 'rm -rf "${workspace:-}"' EXIT
	local repo_dir="$workspace/repo"

	omarchy_syncd_git_clone "$repo_url" "$branch" "$repo_dir"
	omarchy_syncd_fs_restore selected_paths "$repo_dir"

	maybe_hypr_reload

	printf 'Restore complete.\n'
	omarchy_syncd_info "restore: completed successfully"
}

main "$@"
