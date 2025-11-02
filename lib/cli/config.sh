#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "${OMARCHY_SYNCD_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")")/../..}/lib/core.sh"

source "$OMARCHY_SYNCD_ROOT/lib/config.sh"

usage() {
	cat <<'USAGE'
Usage: omarchy-syncd config [options]

Options:
  --print-path            Display the configuration path.
  --create                Create the configuration file if missing.
  --write                 Write configuration using the provided flags.
      --repo-url <url>    Remote repository URL (required with --write).
      --branch <name>     Remote branch (default: master).
      --bundle <id>       Include bundle (repeatable).
      --path <path>       Include explicit path (repeatable).
      --include-defaults  Include Omarchy default bundles.
      --verify-remote     Run `git ls-remote` before writing.
      --force             Overwrite existing configuration.
  --edit                  Open the configuration in an editor.
      --editor <cmd>      Override editor command.
  -h, --help              Show this help message.
USAGE
}

main() {
	local print_path=false
	local create=false
	local write=false
	local include_defaults=false
	local verify_remote=false
	local force=false
	local edit=false
	local branch="master"
	local repo_url=""
	local editor_override=""
	local -a bundles=()
	local -a paths=()

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--print-path) print_path=true ;;
		--create) create=true ;;
		--write) write=true ;;
		--repo-url)
			[[ $# -ge 2 ]] || omarchy_syncd_die "--repo-url requires a value"
			repo_url="$2"
			shift
			;;
		--branch)
			[[ $# -ge 2 ]] || omarchy_syncd_die "--branch requires a value"
			branch="$2"
			shift
			;;
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
		--include-defaults) include_defaults=true ;;
		--verify-remote) verify_remote=true ;;
		--force) force=true ;;
		--edit) edit=true ;;
		--editor)
			[[ $# -ge 2 ]] || omarchy_syncd_die "--editor requires a value"
			editor_override="$2"
			shift
			;;
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

	local executed=false

	if "$write"; then
		omarchy_syncd_config_write \
			"$repo_url" \
			"$branch" \
			"$include_defaults" \
			"$verify_remote" \
			"$force" \
			bundles \
			paths
		executed=true
	fi

	if "$print_path"; then
		omarchy_syncd_config_path
		executed=true
	fi

	if "$create"; then
		if omarchy_syncd_config_create; then
			printf 'Created config at %s\n' "$OMARCHY_SYNCD_CONFIG_PATH"
		else
			printf 'Config already exists at %s\n' "$OMARCHY_SYNCD_CONFIG_PATH"
		fi
		executed=true
	fi

	if "$edit" || [[ -n "$editor_override" && "$write" == "false" && "$print_path" == "false" && "$create" == "false" ]]; then
		omarchy_syncd_config_open_editor "$editor_override"
		executed=true
	fi

	if ! "$executed"; then
		usage >&2
		omarchy_syncd_die "no config action requested"
	fi
}

main "$@"
