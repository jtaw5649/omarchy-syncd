#!/usr/bin/env bash

set -euo pipefail

runtime_bin_dir="$OMARCHY_SYNCD_RUNTIME_DIR/bin"
if [[ ! -d "$runtime_bin_dir" ]]; then
	log_error "helpers: runtime bin directory missing at $runtime_bin_dir"
	exit 1
fi

while IFS= read -r -d '' file; do
	target_name=$(basename "$file")
	if [[ "$target_name" == "omarchy-syncd" ]]; then
		continue
	fi
	chmod +x "$file"
	ln -sfn "$file" "$OMARCHY_SYNCD_BIN_DIR/$target_name"
	if declare -F log_info >/dev/null 2>&1; then
		log_info "helpers: linked $target_name to $file"
	fi
done < <(find "$runtime_bin_dir" -type f -print0)
