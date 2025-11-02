#!/usr/bin/env bash

set -euo pipefail

OMARCHY_SYNCD_LOGO_PATH="${OMARCHY_SYNCD_LOGO_PATH:-$OMARCHY_SYNCD_ROOT/logo.txt}"

require_gum() {
	if ! command -v gum >/dev/null 2>&1; then
		echo "error: gum is required for omarchy-syncd installer presentation." >&2
		exit 1
	fi
}

enter_presentation_mode() {
	if [[ ! -t 1 ]]; then
		return
	fi

	if [[ -n "${OMARCHY_SYNCD_IN_ALT_SCREEN:-}" ]]; then
		return
	fi

	printf '\033[?1049h'
	OMARCHY_SYNCD_IN_ALT_SCREEN=1
}

exit_presentation_mode() {
	if [[ -z "${OMARCHY_SYNCD_IN_ALT_SCREEN:-}" ]]; then
		return
	fi

	if [[ -t 1 ]]; then
		printf '\033[?1049l\033[?25h'
	fi

	unset OMARCHY_SYNCD_IN_ALT_SCREEN
}

require_gum

# Force Omarchy theme even if parent shell exported no-color flags.
unset NO_COLOR
unset GUM_NO_COLOR

if [[ -e /dev/tty ]]; then
	term_size=$(stty size </dev/tty 2>/dev/null || echo "")
else
	term_size=""
fi

if [[ -n "$term_size" ]]; then
	TERM_HEIGHT=$(echo "$term_size" | cut -d' ' -f1)
	TERM_WIDTH=$(echo "$term_size" | cut -d' ' -f2)
	export TERM_HEIGHT TERM_WIDTH
else
	TERM_WIDTH=120
	TERM_HEIGHT=36
	export TERM_WIDTH TERM_HEIGHT
fi

LOGO_WIDTH=$(awk '{ if (length > max) max = length } END { print max+0 }' "$OMARCHY_SYNCD_LOGO_PATH" 2>/dev/null || echo 0)
LOGO_HEIGHT=$(wc -l <"$OMARCHY_SYNCD_LOGO_PATH" 2>/dev/null || echo 0)
export LOGO_WIDTH LOGO_HEIGHT

PADDING_LEFT=$(((TERM_WIDTH - LOGO_WIDTH) / 2))
if ((PADDING_LEFT < 0)); then
	PADDING_LEFT=0
fi
printf -v PADDING_LEFT_SPACES "%*s" "$PADDING_LEFT" ""

export PADDING="0 0 0 0"
if declare -F omarchy_syncd_ui_apply_theme >/dev/null 2>&1; then
	omarchy_syncd_ui_apply_theme
else
	unset NO_COLOR
	unset GUM_NO_COLOR
	export GUM_CONFIRM_PROMPT_FOREGROUND="6"
	export GUM_CONFIRM_SELECTED_FOREGROUND="0"
	export GUM_CONFIRM_SELECTED_BACKGROUND="2"
	export GUM_CONFIRM_UNSELECTED_FOREGROUND="7"
	export GUM_CONFIRM_UNSELECTED_BACKGROUND="0"
	export GUM_CHOOSE_CURSOR="> "
	export GUM_CHOOSE_CURSOR_FOREGROUND="212"
	export GUM_CHOOSE_SELECTED_FOREGROUND="212"
	export GUM_CHOOSE_SELECTED_PREFIX="• "
	export GUM_CHOOSE_UNSELECTED_PREFIX="  "
	export GUM_CONFIRM_PADDING="$PADDING"
	export GUM_CHOOSE_PADDING="$PADDING"
	export GUM_INPUT_PADDING="$PADDING"
	export GUM_FILTER_PADDING="$PADDING"
	export GUM_SPIN_PADDING="$PADDING"
fi

clear_logo() {
	# Only redraw when stdout is an interactive terminal; piping would just leak
	# control sequences into logs.
	if [[ ! -t 1 ]]; then
		return
	fi

	enter_presentation_mode

	# Clear scrollback (ESC[3J) so previous steps do not linger, then wipe the
	# visible screen before redrawing the logo.
	printf '\033[3J\033[H\033[2J\033[32m'
	if [[ -f "$OMARCHY_SYNCD_LOGO_PATH" ]]; then
		cat "$OMARCHY_SYNCD_LOGO_PATH"
	fi
	printf '\033[0m\n'
}

gum_panel() {
	local message=("$@")
	gum style --border normal --border-foreground 6 --padding "1 2" --margin "1 0" --align left "${message[@]}"
}
