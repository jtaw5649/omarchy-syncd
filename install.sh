#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
	SCRIPT_DIR="$(
		cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 || exit 0
		pwd -P
	)"
fi

if [[ -z "$SCRIPT_DIR" ]]; then
	echo "error: failed to determine installer directory" >&2
	exit 1
fi

if [[ -t 0 && -z "${OMARCHY_SYNCD_INSTALL_TTY:-}" ]]; then
	OMARCHY_SYNCD_INSTALL_TTY="$(tty)"
	export OMARCHY_SYNCD_INSTALL_TTY
fi

if [[ "${OMARCHY_SYNCD_FLOATING:-0}" != "1" && "${OMARCHY_SYNCD_NO_FLOAT:-0}" != "1" && -n "${OMARCHY_SYNCD_INSTALL_TTY:-}" ]]; then
	if command -v uwsm-app >/dev/null 2>&1 && command -v alacritty >/dev/null 2>&1; then
		printf -v _syncd_exec 'export OMARCHY_SYNCD_FLOATING=1; unset OMARCHY_SYNCD_INSTALL_TTY; cd %q && ./install.sh "$@"' "$SCRIPT_DIR"
		exec setsid uwsm-app -- alacritty --class=Omarchy --title=Omarchy -e bash -lc "$_syncd_exec" install.sh "$@"
	fi
fi

export OMARCHY_SYNCD_ROOT="$SCRIPT_DIR"
export OMARCHY_SYNCD_INSTALL="$OMARCHY_SYNCD_ROOT/install"
export OMARCHY_SYNCD_LOGO_PATH="${OMARCHY_SYNCD_LOGO_PATH:-$OMARCHY_SYNCD_ROOT/logo.txt}"

export OMARCHY_SYNCD_INSTALL_PREFIX="${OMARCHY_SYNCD_INSTALL_PREFIX:-$HOME/.local/bin}"
export OMARCHY_SYNCD_STATE_DIR="${OMARCHY_SYNCD_STATE_DIR:-$HOME/.local/share/omarchy-syncd}"
export OMARCHY_SYNCD_RUNTIME_DIR="${OMARCHY_SYNCD_RUNTIME_DIR:-$OMARCHY_SYNCD_STATE_DIR/runtime}"
export OMARCHY_SYNCD_BIN_DIR="${OMARCHY_SYNCD_BIN_DIR:-$OMARCHY_SYNCD_INSTALL_PREFIX}"
export OMARCHY_SYNCD_ICON_DIR="${OMARCHY_SYNCD_ICON_DIR:-$HOME/.local/share/icons}"
export OMARCHY_SYNCD_CONFIG_PATH="${OMARCHY_SYNCD_CONFIG_PATH:-$HOME/.config/omarchy-syncd/config.toml}"
export OMARCHY_SYNCD_PLACEHOLDER_REPO="${OMARCHY_SYNCD_PLACEHOLDER_REPO:-https://example.com/your-private-repo.git}"
export PATH="$OMARCHY_SYNCD_BIN_DIR:$PATH"

"$OMARCHY_SYNCD_INSTALL/preflight/dependencies_prompt.sh"

# shellcheck source=install/helpers/all.sh
source "$OMARCHY_SYNCD_INSTALL/helpers/all.sh"

# shellcheck source=install/preflight/all.sh
source "$OMARCHY_SYNCD_INSTALL/preflight/all.sh"
# shellcheck source=install/packaging/all.sh
source "$OMARCHY_SYNCD_INSTALL/packaging/all.sh"
# shellcheck source=install/config/all.sh
source "$OMARCHY_SYNCD_INSTALL/config/all.sh"
# shellcheck source=install/post-install/all.sh
source "$OMARCHY_SYNCD_INSTALL/post-install/all.sh"
