#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")"/.. && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

OMARCHY_SYNCD_INSTALL_PREFIX="$TMPDIR/bin"
export OMARCHY_SYNCD_INSTALL_PREFIX
export OMARCHY_SYNCD_CONFIG_PATH="$TMPDIR/config.toml"
export OMARCHY_SYNCD_STATE_DIR="$TMPDIR/state"
export OMARCHY_SYNCD_LOG_PATH="$TMPDIR/activity.log"
export HOME="$TMPDIR/home"
mkdir -p "$HOME" "$OMARCHY_SYNCD_INSTALL_PREFIX"

# Seed fake release tarball (essential runtime assets)
RELEASE_WORK="$TMPDIR/release"
RELEASE_ROOT="$RELEASE_WORK/omarchy-syncd"
mkdir -p "$RELEASE_ROOT"
cp -R "$PROJECT_ROOT/bin" "$RELEASE_ROOT/bin"
cp -R "$PROJECT_ROOT/lib" "$RELEASE_ROOT/lib"
if [[ -d "$PROJECT_ROOT/data" ]]; then
	cp -R "$PROJECT_ROOT/data" "$RELEASE_ROOT/data"
fi
cp -R "$PROJECT_ROOT/install" "$RELEASE_ROOT/install"
cp "$PROJECT_ROOT/install.sh" "$RELEASE_ROOT/install.sh"
[ -f "$PROJECT_ROOT/logo.txt" ] && cp "$PROJECT_ROOT/logo.txt" "$RELEASE_ROOT/logo.txt"
[ -f "$PROJECT_ROOT/version" ] && cp "$PROJECT_ROOT/version" "$RELEASE_ROOT/version"

release_tar="$TMPDIR/release.tar.gz"
tar -C "$RELEASE_WORK" -czf "$release_tar" omarchy-syncd

export OMARCHY_SYNCD_RELEASE_URL="file://$release_tar"
export OMARCHY_SYNCD_NON_INTERACTIVE=1
export OMARCHY_SYNCD_INSTALL_ARGS="--force --bundle core_desktop"

INSTALL_ROOT="$TMPDIR/install"
mkdir -p "$INSTALL_ROOT"
cp "$PROJECT_ROOT/install.sh" "$INSTALL_ROOT/install.sh"
cp -R "$PROJECT_ROOT/install" "$INSTALL_ROOT/install"
[ -f "$PROJECT_ROOT/logo.txt" ] && cp "$PROJECT_ROOT/logo.txt" "$INSTALL_ROOT/logo.txt"

(
	cd "$INSTALL_ROOT"
	./install.sh
)

runtime_bin="$OMARCHY_SYNCD_INSTALL_PREFIX/omarchy-syncd"
"$runtime_bin" --help >/dev/null

RUNTIME_DIR="$OMARCHY_SYNCD_STATE_DIR/runtime"
if [[ ! -f "$RUNTIME_DIR/lib/core.sh" ]]; then
	printf 'error: runtime core.sh not deployed\n' >&2
	exit 1
fi

if [[ ! -L "$runtime_bin" ]]; then
	printf 'error: omarchy-syncd is not linked from runtime\n' >&2
	exit 1
fi

runtime_target="$(readlink -f "$runtime_bin")"
expected_target="$RUNTIME_DIR/bin/omarchy-syncd"
if [[ "$runtime_target" != "$expected_target" ]]; then
	printf 'error: omarchy-syncd link targets %s (expected %s)\n' "$runtime_target" "$expected_target" >&2
	exit 1
fi

for helper in omarchy-syncd-launcher omarchy-syncd-show-logo omarchy-syncd-show-done omarchy-syncd-update; do
	if [[ ! -L "$OMARCHY_SYNCD_INSTALL_PREFIX/$helper" ]]; then
		printf 'error: helper %s missing link\n' "$helper" >&2
		exit 1
	fi
done

printf 'Smoke test succeeded (artifacts in %s)\n' "$INSTALL_ROOT"
