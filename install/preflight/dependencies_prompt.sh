#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=install/preflight/dependencies_lib.sh
source "$OMARCHY_SYNCD_INSTALL/preflight/dependencies_lib.sh"

display_dependency_warning() {
	local colour="$1"
	local heading="$2"
	shift 2
	local -a items=("$@")

	if [[ ${#items[@]} -eq 0 ]]; then
		return
	fi

	printf '\n'
	if command -v gum >/dev/null 2>&1 && [[ "${GUM_NO_COLOR:-0}" != "1" ]]; then
		local body
		body="$heading"
		for item in "${items[@]}"; do
			body+=$'\n'
			body+="• ${item}"
		done
		gum style --border normal --border-foreground "$colour" --padding "1 2" --margin "1 0" "$body"
		printf '\n'
	else
		printf '%s\n' "$heading"
		for item in "${items[@]}"; do
			printf ' - %s\n' "$item"
		done
		printf '\n'
	fi
}

prompt_yes_no() {
	local prompt="$1"
	if command -v gum >/dev/null 2>&1 && [[ -t 0 && -t 1 ]]; then
		gum confirm --default=true "$prompt"
	else
		read -r -p "$prompt [Y/n] " reply
		reply=${reply,,}
		[[ -z "$reply" || "$reply" == "y" || "$reply" == "yes" ]]
	fi
}

install_dependencies() {
	local packages=("$@")
	if [[ ${#packages[@]} -eq 0 ]]; then
		return 0
	fi

	if ! command -v pacman >/dev/null 2>&1; then
		printf 'error: pacman not available to install missing dependencies (%s)\n' "${packages[*]}" >&2
		return 1
	fi

	local cmd=(pacman -S --needed --noconfirm "${packages[@]}")
	if command -v sudo >/dev/null 2>&1; then
		cmd=(sudo "${cmd[@]}")
	fi

	"${cmd[@]}"
}

show_cancelled() {
	if command -v gum >/dev/null 2>&1 && [[ -t 0 && -t 1 ]]; then
		gum style --foreground 214 --bold "Installation cancelled"
		gum spin --spinner globe --title "Done! Press any key to close..." -- bash -lc 'read -n 1 -s'
	else
		printf 'Installation cancelled\n'
		if [[ -t 0 ]]; then
			printf 'Press any key to close...\n'
			read -r -n1 -s
		fi
	fi
}

main() {
	# Skip interactive flow when not attached to a terminal.
	if [[ ! -t 0 || ! -t 1 ]]; then
		return 0
	fi

	omarchy_syncd_dependencies_scan

	local -a missing_required=("${OMARCHY_SYNCD_DEPS_MISSING_REQUIRED[@]}")
	local -a missing_optional=("${OMARCHY_SYNCD_DEPS_MISSING_OPTIONAL[@]}")

	if ((${#missing_required[@]} == 0 && ${#missing_optional[@]} == 0)); then
		return 0
	fi

	local -a bullet_items=("${missing_required[@]}")
	local opt
	for opt in "${missing_optional[@]}"; do
		bullet_items+=("$opt (optional)")
	done

	display_dependency_warning 196 "Dependencies not installed:" "${bullet_items[@]}"

	if ! prompt_yes_no "Install dependencies?"; then
		printf 'Installation cancelled by user (dependencies missing).\n'
		show_cancelled
		exit 1
	fi

	if ! install_dependencies "${missing_required[@]}" "${missing_optional[@]}"; then
		show_cancelled
		exit 1
	fi

	# Verify again after installation.
	omarchy_syncd_dependencies_scan
	missing_required=("${OMARCHY_SYNCD_DEPS_MISSING_REQUIRED[@]}")
	missing_optional=("${OMARCHY_SYNCD_DEPS_MISSING_OPTIONAL[@]}")
	if ((${#missing_required[@]} > 0)); then
		printf 'error: still missing required dependencies: %s\n' "${missing_required[*]}" >&2
		show_cancelled
		exit 1
	fi

	return 0
}

main "$@"
