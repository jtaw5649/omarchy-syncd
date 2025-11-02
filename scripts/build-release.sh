#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
DIST_DIR="$ROOT_DIR/dist"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

VERSION="$(cat "$ROOT_DIR/version" 2>/dev/null || echo "dev")"
TARBALL="$DIST_DIR/omarchy-syncd-$VERSION.tar.gz"

WORK_ROOT="$DIST_DIR/work/omarchy-syncd"
mkdir -p "$WORK_ROOT"
cp -R "$ROOT_DIR/bin" "$WORK_ROOT/bin"
cp -R "$ROOT_DIR/lib" "$WORK_ROOT/lib"
if [[ -d "$ROOT_DIR/data" ]]; then
	cp -R "$ROOT_DIR/data" "$WORK_ROOT/data"
fi
cp -R "$ROOT_DIR/install" "$WORK_ROOT/install"
cp "$ROOT_DIR/install.sh" "$WORK_ROOT/install.sh"
cp "$ROOT_DIR/logo.txt" "$WORK_ROOT/logo.txt" 2>/dev/null || true
cp "$ROOT_DIR/version" "$WORK_ROOT/version" 2>/dev/null || true
cp "$ROOT_DIR/README.md" "$WORK_ROOT/README.md" 2>/dev/null || true

(cd "$DIST_DIR/work" && tar -czf "$TARBALL" omarchy-syncd)
rm -rf "$DIST_DIR/work"

echo "Created $TARBALL"
