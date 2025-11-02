#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

readonly OMARCHY_SYNCD_EXIT_CANCELLED=130

source "${OMARCHY_SYNCD_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")")/../..}/lib/core.sh"

source "$OMARCHY_SYNCD_ROOT/lib/config.sh"
source "$OMARCHY_SYNCD_ROOT/lib/ui.sh"

omarchy_syncd_cancel() {
	printf 'notice: %s\n' "$1" >&2
	exit "$OMARCHY_SYNCD_EXIT_CANCELLED"
}

usage() {
	cat <<'USAGE'
Usage: omarchy-syncd install [options]

Options:
      --bundle <id>     Include bundle (repeatable).
      --path <path>     Include explicit path (repeatable).
      --no-ui           Disable interactive selector even if running in a TTY.
      --dry-run         Show the resulting configuration without saving.
      --force           Overwrite an existing configuration.
  -h, --help            Show this help message.
USAGE
}

build_bundle_choices() {
	local manifest_json
	manifest_json="$(omarchy_syncd_config_manifest_json)" || return 1
	python3 - "$manifest_json" <<'PY'
import json, sys

manifest = json.loads(sys.argv[1])
bundles = manifest.get("bundle", [])
width = max((len(bundle["name"]) for bundle in bundles), default=0)
for bundle in bundles:
    label = f"{bundle['name']:<{width}}  {bundle['description']}"
    print(f"{bundle['id']}|{label}")
PY
}

resolve_bundle_paths() {
	local bundle_ids="$1"
	python3 - "$bundle_ids" <<'PY'
import json, os, sys, tomllib

root = os.environ["OMARCHY_SYNCD_ROOT"]
with open(os.path.join(root, "data", "bundles.toml"), "rb") as fh:
    manifest = tomllib.load(fh)
requested = {item for item in sys.argv[1].split("\n") if item}
paths = set()
for bundle in manifest.get("bundle", []):
    if bundle["id"] in requested:
        paths.update(bundle.get("paths", []))
for path in sorted(paths):
    print(path)
PY
}

default_bundle_ids() {
	local manifest_json
	manifest_json="$(omarchy_syncd_config_manifest_json)" || return 1
	python3 - "$manifest_json" <<'PY'
import json, sys
manifest = json.loads(sys.argv[1])
defaults = manifest.get("defaults", {}).get("bundle_ids", [])
for item in defaults:
    print(item)
PY
}

all_manifest_paths() {
	local manifest_json
	manifest_json="$(omarchy_syncd_config_manifest_json)" || return 1
	python3 - "$manifest_json" <<'PY'
import json, sys
manifest = json.loads(sys.argv[1])
seen = set()
ordered = []
for bundle in manifest.get("bundle", []):
    for path in bundle.get("paths", []):
        if path not in seen:
            seen.add(path)
            ordered.append(path)
for path in ordered:
    print(path)
PY
}

print_selection() {
    if [[ "${OMARCHY_SYNCD_SUPPRESS_SELECTION:-0}" == "1" ]]; then
        return
    fi
    local -n bundles_ref="$1"
    local -n paths_ref="$2"
	printf 'Selected bundles:\n'
	if [[ ${#bundles_ref[@]} -eq 0 ]]; then
		printf '  (none)\n'
	else
		printf '  %s\n' "${bundles_ref[@]}"
	fi
	printf 'Selected paths:\n'
	if [[ ${#paths_ref[@]} -eq 0 ]]; then
		printf '  (none)\n'
	else
		printf '  %s\n' "${paths_ref[@]}"
	fi
}

main() {
	local no_ui=false
	local dry_run=false
	local force=false
	local -a bundles=()
	local -a paths=()
	local selection_mode=""

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--bundle)
			[[ $# -ge 2 ]] || omarchy_syncd_die "--bundle requires a value"
			bundles+=("$2")
			shift
			;;
		--path)
			[[ $# -ge 2 ]] || omarchy_syncd_die "--path requires a value"
			paths+=("$2")
			shift
			;;
		--no-ui) no_ui=true ;;
		--dry-run) dry_run=true ;;
		--force) force=true ;;
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

	omarchy_syncd_normalize_list bundles
	omarchy_syncd_normalize_list paths

	local is_tty=false
	if [[ -t 0 && -t 1 ]]; then
		is_tty=true
	fi

	if [[ "$is_tty" == "true" ]]; then
		omarchy_syncd_ui_apply_theme
	fi

	if [[ "$no_ui" == "false" && "$is_tty" == "true" ]]; then
		if omarchy_syncd_ui_confirm --default=true "Add default config?"; then
			local defaults_tmp
			defaults_tmp="$(mktemp)"
			if ! default_bundle_ids >"$defaults_tmp"; then
				rm -f "$defaults_tmp"
				omarchy_syncd_die "Failed to read default bundle list"
			fi
			mapfile -t bundles <"$defaults_tmp"
			rm -f "$defaults_tmp"
			if [[ ${#bundles[@]} -gt 0 ]]; then
				local resolved_tmp
				resolved_tmp="$(mktemp)"
				if ! resolve_bundle_paths "$(printf '%s\n' "${bundles[@]}")" >"$resolved_tmp"; then
					rm -f "$resolved_tmp"
					omarchy_syncd_die "Failed to resolve bundle paths"
				fi
				mapfile -t paths <"$resolved_tmp"
				rm -f "$resolved_tmp"
			else
				paths=()
			fi
			selection_mode="defaults"
		else
			local paths_tmp
			paths_tmp="$(mktemp)"
			if ! all_manifest_paths >"$paths_tmp"; then
				rm -f "$paths_tmp"
				omarchy_syncd_die "Failed to load manifest paths"
			fi
			local -a path_choices=()
			mapfile -t path_choices <"$paths_tmp"
			rm -f "$paths_tmp"
			if [[ ${#path_choices[@]} -eq 0 ]]; then
				omarchy_syncd_die "No configurable paths available."
			fi
			local selection_output
			if ! selection_output="$(printf '%s\n' "${path_choices[@]}" | gum filter --no-limit --prompt "> " --placeholder "Search dotfiles" --header "Select dotfiles to configure (Tab toggles, Enter confirms)")"; then
				omarchy_syncd_cancel "No dotfiles selected. Rerun the installer to choose configuration paths."
			fi
			local -a path_selection=()
			while IFS= read -r line; do
				[[ -z "$line" ]] && continue
				path_selection+=("$line")
			done <<<"$selection_output"
			if [[ ${#path_selection[@]} -eq 0 ]]; then
				omarchy_syncd_cancel "No dotfiles selected. Rerun the installer to choose configuration paths."
			fi
			paths=("${path_selection[@]}")
			bundles=()
			selection_mode="manual"
		fi
	fi

	omarchy_syncd_normalize_list bundles
	omarchy_syncd_normalize_list paths

	if [[ ${#bundles[@]} -eq 0 && ${#paths[@]} -eq 0 ]]; then
		omarchy_syncd_cancel "No bundles or paths selected. Use --bundle/--path or run interactively."
	fi

	if [[ "$dry_run" == "true" ]]; then
		print_selection bundles paths
		printf 'Dry run: configuration not written.\n'
		return 0
	fi

	local repo_url
	repo_url="$(omarchy_syncd_config_repo_url || true)"
	local branch
	branch="$(omarchy_syncd_config_repo_branch 2>/dev/null || echo "master")"

	if [[ -z "$repo_url" ]]; then
		omarchy_syncd_die "Existing configuration missing. Run 'omarchy-syncd config --write --repo-url <url> ...' first."
	fi

	omarchy_syncd_config_write \
		"$repo_url" \
		"$branch" \
		false \
		false \
		"$force" \
		bundles \
		paths >/dev/null

	print_selection bundles paths
	if [[ "${OMARCHY_SYNCD_SUPPRESS_SELECTION:-0}" != "1" ]]; then
		printf 'Saved selection to %s\n' "$(omarchy_syncd_config_path)"
	fi

	if [[ -n "${OMARCHY_SYNCD_SELECTION_FILE:-}" ]]; then
		{
			if [[ "$selection_mode" == "defaults" ]]; then
				echo "Default bundles applied"
			else
				echo "Manual selection applied"
			fi
			echo
			if [[ ${#bundles[@]} -gt 0 ]]; then
				echo "Bundles:"
				for bundle_id in "${bundles[@]}"; do
					echo "  • $bundle_id"
				done
				echo
			fi
		} >"$OMARCHY_SYNCD_SELECTION_FILE"
	fi
}

main "$@"
