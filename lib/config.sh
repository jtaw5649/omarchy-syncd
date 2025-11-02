#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "${OMARCHY_SYNCD_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")")/..}/lib/core.sh"

omarchy_syncd_require_command python3

OMARCHY_SYNCD_PLACEHOLDER_REPO="${OMARCHY_SYNCD_PLACEHOLDER_REPO:-https://example.com/your-private-repo.git}"

omarchy_syncd_config_path() {
	printf '%s\n' "$OMARCHY_SYNCD_CONFIG_PATH"
}

omarchy_syncd_config_manifest_json() {
	local tmp_err
	tmp_err="$(mktemp)"
	local manifest
	if ! manifest="$(python3 "$OMARCHY_SYNCD_ROOT/lib/python/config_tool.py" \
		--root "$OMARCHY_SYNCD_ROOT" \
		manifest 2>"$tmp_err")"
	then
		local err
		err="$(<"$tmp_err")"
		rm -f "$tmp_err"
		omarchy_syncd_die "${err:-failed to load configuration manifest}"
	fi
	rm -f "$tmp_err"
	printf '%s\n' "$manifest"
}

omarchy_syncd_config_create() {
	local path="$OMARCHY_SYNCD_CONFIG_PATH"
	if [[ -f "$path" ]]; then
		return 1
	fi
	omarchy_syncd_ensure_parent_dir "$path"
	umask 077
	printf '# omarchy-syncd configuration\n' >"$path"
	omarchy_syncd_info "created config at $path"
	return 0
}

omarchy_syncd_config_write() {
	local repo_url="$1"
	local branch="$2"
	local include_defaults="$3"
	local verify_remote="$4"
	local force="$5"
	local bundles_ref="$6"
	local paths_ref="$7"

	if [[ -z "$repo_url" ]]; then
		omarchy_syncd_die "--repo-url is required"
	fi

	if [[ "$verify_remote" == "true" ]]; then
		omarchy_syncd_require_command git
		if ! git ls-remote --exit-code "$repo_url" "$branch" >/dev/null 2>&1; then
			omarchy_syncd_die "remote verification failed for ${repo_url} ${branch}"
		fi
	fi

	local -a bundle_args=()
	local -n bundles_target="$bundles_ref"
	local bundle
	for bundle in "${bundles_target[@]}"; do
		bundle_args+=(--bundle "$bundle")
	done

	local -a path_args=()
	local -n paths_target="$paths_ref"
	local path
	for path in "${paths_target[@]}"; do
		path_args+=(--path "$path")
	done

	local tmp_err
	tmp_err="$(mktemp)"
	local -a cmd=(
		python3 "$OMARCHY_SYNCD_ROOT/lib/python/config_tool.py"
		--root "$OMARCHY_SYNCD_ROOT"
		write
		--repo-url "$repo_url"
		--branch "$branch"
	)
	cmd+=("${bundle_args[@]}")
	cmd+=("${path_args[@]}")
	if [[ "$include_defaults" == "true" ]]; then
		cmd+=(--include-defaults)
	fi

	local toml err
	if ! toml="$("${cmd[@]}" 2>"$tmp_err")"; then
		err="$(<"$tmp_err")"
		rm -f "$tmp_err"
		omarchy_syncd_die "${err:-failed to generate configuration}"
	fi
	rm -f "$tmp_err"

	local config_path="$OMARCHY_SYNCD_CONFIG_PATH"
	if [[ -f "$config_path" && "$force" != "true" ]]; then
		omarchy_syncd_die "config already exists at $config_path (use --force to overwrite)"
	fi

	omarchy_syncd_ensure_parent_dir "$config_path"
	umask 077
	printf '%s\n' "$toml" >"$config_path"
	omarchy_syncd_info "wrote config to $config_path"
	printf 'Wrote config to %s\n' "$config_path"
}

omarchy_syncd_config_select_editor() {
	local preferred="$1"
	if [[ -n "$preferred" ]]; then
		printf '%s\n' "$preferred"
		return
	fi
	if [[ -n "${EDITOR:-}" ]]; then
		printf '%s\n' "$EDITOR"
		return
	fi
	if [[ -n "${VISUAL:-}" ]]; then
		printf '%s\n' "$VISUAL"
		return
	fi
	local candidate
	for candidate in nvim vim nano; do
		if command -v "$candidate" >/dev/null 2>&1; then
			printf '%s\n' "$candidate"
			return
		fi
	done
	omarchy_syncd_die "no editor available; set \$EDITOR or pass --editor <cmd>"
}

omarchy_syncd_config_open_editor() {
	local preferred="$1"
	local path="$OMARCHY_SYNCD_CONFIG_PATH"
	omarchy_syncd_config_create || true
	local editor
	editor="$(omarchy_syncd_config_select_editor "$preferred")"
	omarchy_syncd_info "opening config via editor '${editor}'"
	if ! "$editor" "$path"; then
		omarchy_syncd_die "editor '${editor}' exited with non-zero status"
	fi
}

omarchy_syncd_config_require() {
	if [[ ! -f "$OMARCHY_SYNCD_CONFIG_PATH" ]]; then
		omarchy_syncd_die "config not found at $OMARCHY_SYNCD_CONFIG_PATH (run 'omarchy-syncd config --write …' first)"
	fi
}

omarchy_syncd_config_read_field() {
	local field="$1"
	omarchy_syncd_config_require
	python3 "$OMARCHY_SYNCD_ROOT/lib/python/config_tool.py" \
		--root "$OMARCHY_SYNCD_ROOT" \
		read-config \
		--config-path "$OMARCHY_SYNCD_CONFIG_PATH" \
		--field "$field"
}

omarchy_syncd_config_read_json() {
	omarchy_syncd_config_require
	python3 "$OMARCHY_SYNCD_ROOT/lib/python/config_tool.py" \
		--root "$OMARCHY_SYNCD_ROOT" \
		read-config \
		--config-path "$OMARCHY_SYNCD_CONFIG_PATH"
}

omarchy_syncd_config_repo_url() {
	omarchy_syncd_config_read_field "repo.url"
}

omarchy_syncd_config_repo_is_placeholder() {
	local url
	url="$(omarchy_syncd_config_repo_url)"
	[[ "$url" == "$OMARCHY_SYNCD_PLACEHOLDER_REPO" ]] || [[ -z "$url" ]]
}

omarchy_syncd_config_repo_branch() {
	local branch
	branch="$(omarchy_syncd_config_read_field "repo.branch")"
	if [[ -z "$branch" ]]; then
		branch="master"
	fi
	printf '%s\n' "$branch"
}

omarchy_syncd_config_resolved_paths() {
	omarchy_syncd_config_read_field "resolved_paths"
}

omarchy_syncd_config_bundle_options() {
	omarchy_syncd_config_read_field "bundle_options"
}
