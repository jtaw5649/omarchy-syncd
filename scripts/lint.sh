#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")"/.. && pwd)"
STATUS=0

mapfile -t SHELL_FILES < <(find "$PROJECT_ROOT" -path "$PROJECT_ROOT/.venv" -prune -o -type f \( -name '*.sh' -o -name '*.bash' \) -print)

if command -v shellcheck >/dev/null 2>&1; then
	if ((${#SHELL_FILES[@]} > 0)); then
		echo "Running shellcheck"
		shellcheck -x "${SHELL_FILES[@]}" || STATUS=1
	fi
else
	echo "shellcheck not installed; skipping" >&2
fi

if command -v shfmt >/dev/null 2>&1; then
	if ((${#SHELL_FILES[@]} > 0)); then
		echo "Running shfmt --diff"
		shfmt -d "${SHELL_FILES[@]}" || STATUS=1
	fi
else
	echo "shfmt not installed; skipping" >&2
fi

exit $STATUS
