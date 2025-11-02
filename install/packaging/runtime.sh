#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${OMARCHY_SYNCD_RUNTIME_DIR:-}" ]]; then
	log_error "runtime: OMARCHY_SYNCD_RUNTIME_DIR is not set"
	exit 1
fi

runtime_root="$OMARCHY_SYNCD_RUNTIME_DIR"
log_info "runtime: syncing assets into $runtime_root"

rm -rf "$runtime_root"
mkdir -p "$runtime_root"

copy_tree() {
	local name="$1"
	local src="$OMARCHY_SYNCD_ROOT/$name"
	local dest="$runtime_root/$name"

	if [[ -d "$src" ]]; then
		rm -rf "$dest"
		mkdir -p "$(dirname "$dest")"
		cp -R "$src" "$dest"
		log_info "runtime: copied directory $name"
	fi
}

copy_file() {
	local name="$1"
	local src="$OMARCHY_SYNCD_ROOT/$name"
	local dest="$runtime_root/$name"

	if [[ -f "$src" ]]; then
		mkdir -p "$(dirname "$dest")"
		cp "$src" "$dest"
		log_info "runtime: copied file $name"
	fi
}

copy_tree "bin"
copy_tree "lib"
copy_tree "data"
copy_file "logo.txt"
copy_file "version"

find "$runtime_root/bin" -type f -print0 2>/dev/null | while IFS= read -r -d '' file; do
	chmod +x "$file"
done
