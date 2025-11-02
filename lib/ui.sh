#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "${OMARCHY_SYNCD_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")")/..}/lib/core.sh"

omarchy_syncd_ui_require_gum() {
	if ! command -v gum >/dev/null 2>&1; then
		omarchy_syncd_die "gum is required for interactive prompts. Install gum and re-run."
	fi
}

omarchy_syncd_ui_require_tty() {
	if [[ ! -t 0 || ! -t 1 ]]; then
		if [[ -n "${OMARCHY_SYNCD_INSTALL_TTY:-}" ]]; then
			return
		fi
		omarchy_syncd_die "interactive prompts require an attached terminal. Re-run from a TTY."
	fi
}

omarchy_syncd_ui_apply_theme() {
	unset NO_COLOR
	unset GUM_NO_COLOR

	local padding="${PADDING:-0 0 0 0}"

	export GUM_CONFIRM_PROMPT_FOREGROUND="${GUM_CONFIRM_PROMPT_FOREGROUND:-6}"
	export GUM_CONFIRM_SELECTED_FOREGROUND="${GUM_CONFIRM_SELECTED_FOREGROUND:-0}"
	export GUM_CONFIRM_SELECTED_BACKGROUND="${GUM_CONFIRM_SELECTED_BACKGROUND:-2}"
	export GUM_CONFIRM_UNSELECTED_FOREGROUND="${GUM_CONFIRM_UNSELECTED_FOREGROUND:-7}"
	export GUM_CONFIRM_UNSELECTED_BACKGROUND="${GUM_CONFIRM_UNSELECTED_BACKGROUND:-0}"
	export GUM_CONFIRM_PADDING="${GUM_CONFIRM_PADDING:-$padding}"

	export GUM_CHOOSE_CURSOR="${GUM_CHOOSE_CURSOR:-"> "}"
	export GUM_CHOOSE_CURSOR_FOREGROUND="${GUM_CHOOSE_CURSOR_FOREGROUND:-212}"
	export GUM_CHOOSE_SELECTED_PREFIX="${GUM_CHOOSE_SELECTED_PREFIX:-"• "}"
	export GUM_CHOOSE_UNSELECTED_PREFIX="${GUM_CHOOSE_UNSELECTED_PREFIX:-"  "}"
	export GUM_CHOOSE_SELECTED_FOREGROUND="${GUM_CHOOSE_SELECTED_FOREGROUND:-212}"
	export GUM_CHOOSE_PADDING="${GUM_CHOOSE_PADDING:-$padding}"

	export GUM_INPUT_PADDING="${GUM_INPUT_PADDING:-$padding}"
	export GUM_FILTER_PADDING="${GUM_FILTER_PADDING:-$padding}"
	export GUM_SPIN_PADDING="${GUM_SPIN_PADDING:-$padding}"

	export GUM_FILTER_PROMPT="${GUM_FILTER_PROMPT:-"> "}"
	export GUM_FILTER_PROMPT_FOREGROUND="${GUM_FILTER_PROMPT_FOREGROUND:-6}"
	export GUM_FILTER_INDICATOR="${GUM_FILTER_INDICATOR:-"•"}"
	export GUM_FILTER_INDICATOR_FOREGROUND="${GUM_FILTER_INDICATOR_FOREGROUND:-212}"
	export GUM_FILTER_SELECTED_PREFIX="${GUM_FILTER_SELECTED_PREFIX:-"• "}"
	export GUM_FILTER_SELECTED_PREFIX_FOREGROUND="${GUM_FILTER_SELECTED_PREFIX_FOREGROUND:-212}"
	export GUM_FILTER_UNSELECTED_PREFIX="${GUM_FILTER_UNSELECTED_PREFIX:-"  "}"
	export GUM_FILTER_UNSELECTED_PREFIX_FOREGROUND="${GUM_FILTER_UNSELECTED_PREFIX_FOREGROUND:-240}"
	export GUM_FILTER_TEXT_FOREGROUND="${GUM_FILTER_TEXT_FOREGROUND:-7}"
	export GUM_FILTER_CURSOR_TEXT_FOREGROUND="${GUM_FILTER_CURSOR_TEXT_FOREGROUND:-0}"
	export GUM_FILTER_MATCH_FOREGROUND="${GUM_FILTER_MATCH_FOREGROUND:-212}"
	export GUM_FILTER_PLACEHOLDER_FOREGROUND="${GUM_FILTER_PLACEHOLDER_FOREGROUND:-7}"
	export GUM_FILTER_HEADER_FOREGROUND="${GUM_FILTER_HEADER_FOREGROUND:-6}"

	export OMARCHY_SYNCD_UI_THEME_APPLIED=1
}

omarchy_syncd_ui_clean_label() {
	local label="$1"
	# Strip ANSI escape codes
	label="$(printf '%s' "$label" | sed -E 's/\x1B\[[0-9;?]*[[:alpha:]]//g')"
	label="${label//$'\r'/}"
	# Remove gum selection markers
	label="${label#> }"
	label="${label#• }"
	# Trim leading/trailing whitespace
	label="${label#"${label%%[![:space:]]*}"}"
	label="${label%"${label##*[![:space:]]}"}"
	printf '%s' "$label"
}

omarchy_syncd_ui_multi_select() {
	local prompt="$1"
	local header="$2"
	local choices_ref="$3"
	local -n choices="$choices_ref"
	: "$prompt"

	if [[ ${#choices[@]} -eq 0 ]]; then
		return 0
	fi

	omarchy_syncd_ui_require_gum
	omarchy_syncd_ui_require_tty
	omarchy_syncd_ui_apply_theme

	if [[ -n "$prompt" ]]; then
		printf '%s\n' "$prompt" >"${OMARCHY_SYNCD_INSTALL_TTY:-/dev/tty}"
	fi

	local selection
	selection="$(printf '%s\n' "${choices[@]}" | cut -d'|' -f2 | gum choose --no-limit --header "$header")" || return 1
	local result=()
	local label
	while IFS= read -r label; do
		[[ -z "$label" ]] && continue
		label="$(omarchy_syncd_ui_clean_label "$label")"
		[[ -z "$label" ]] && continue
		local idx
		for idx in "${choices[@]}"; do
			local id="${idx%%|*}"
			local text="${idx#*|}"
			if [[ "$text" == "$label" ]]; then
				result+=("$id")
				break
			fi
		done
	done <<<"$selection"
	printf '%s\n' "${result[@]}"
}

omarchy_syncd_ui_single_select() {
	local prompt="$1"
	local header="$2"
	local choices_ref="$3"
	local -n choices="$choices_ref"
	: "$prompt"

	if [[ ${#choices[@]} -eq 0 ]]; then
		return 1
	fi

	omarchy_syncd_ui_require_gum
	omarchy_syncd_ui_require_tty
	omarchy_syncd_ui_apply_theme

	if [[ -n "$prompt" ]]; then
		printf '%s\n' "$prompt" >"${OMARCHY_SYNCD_INSTALL_TTY:-/dev/tty}"
	fi

	local selection
	selection="$(printf '%s\n' "${choices[@]}" | cut -d'|' -f2 | gum choose --header "$header")" || return 1
	local entry
	selection="$(omarchy_syncd_ui_clean_label "$selection")"
	for entry in "${choices[@]}"; do
		local id="${entry%%|*}"
		local label="${entry#*|}"
		if [[ "$label" == "$selection" ]]; then
			printf '%s\n' "$id"
			return 0
		fi
	done
	return 1
}

omarchy_syncd_ui_info_panel() {
	local title="$1"
	local body="$2"
	omarchy_syncd_ui_require_gum
	omarchy_syncd_ui_apply_theme
	gum format --border normal --padding "1 2" --title "$title" "$body"
}

omarchy_syncd_ui_confirm() {
	omarchy_syncd_ui_require_gum
	omarchy_syncd_ui_require_tty
	omarchy_syncd_ui_apply_theme
	local padding="0 0 0 0"
	env \
		GUM_CONFIRM_PROMPT_FOREGROUND="${GUM_CONFIRM_PROMPT_FOREGROUND:-6}" \
		GUM_CONFIRM_SELECTED_FOREGROUND="${GUM_CONFIRM_SELECTED_FOREGROUND:-0}" \
		GUM_CONFIRM_SELECTED_BACKGROUND="${GUM_CONFIRM_SELECTED_BACKGROUND:-2}" \
		GUM_CONFIRM_UNSELECTED_FOREGROUND="${GUM_CONFIRM_UNSELECTED_FOREGROUND:-7}" \
		GUM_CONFIRM_UNSELECTED_BACKGROUND="${GUM_CONFIRM_UNSELECTED_BACKGROUND:-0}" \
		GUM_CONFIRM_PADDING="${GUM_CONFIRM_PADDING:-$padding}" \
		gum confirm "$@"
}
