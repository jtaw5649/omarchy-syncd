#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")"/.. && pwd)"

BATS=$(command -v bats || true)
if [[ -z "$BATS" ]]; then
	echo "error: bats is not installed. Please install bats-core first." >&2
	exit 1
fi

STATUS=0
for file in "$PROJECT_ROOT"/tests/bats/*.bats; do
	echo "Running $(basename "$file")"
	if ! "$BATS" "$file"; then
		STATUS=1
	fi
	echo
done

EXPECT=$(command -v expect || true)
RUN_EXPECT="$PROJECT_ROOT/tests/support/run_expect.sh"
if [[ -z "$EXPECT" ]]; then
	echo "error: expect is not installed. Skipping interactive installer tests." >&2
	STATUS=1
elif [[ ! -x "$RUN_EXPECT" ]]; then
	echo "error: expect runner not found at $RUN_EXPECT" >&2
	STATUS=1
else
	TIMEOUT_BIN=$(command -v timeout || true)
	for script in "$PROJECT_ROOT"/tests/interactive/*.exp; do
		echo "Running $(basename "$script")"
		if [[ -n "$TIMEOUT_BIN" ]]; then
			if ! "$TIMEOUT_BIN" 60s "$RUN_EXPECT" "$script"; then
				STATUS=1
			fi
		else
			if ! "$RUN_EXPECT" "$script"; then
				STATUS=1
			fi
		fi
		echo
	done
fi

exit $STATUS
