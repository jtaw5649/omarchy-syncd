#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${OMARCHY_SYNCD_SKIP_BOOTSTRAP:-}" ]]; then
	log_info "bootstrap: skipping due to OMARCHY_SYNCD_SKIP_BOOTSTRAP."
	exit 0
fi

if [[ -d "$OMARCHY_SYNCD_ROOT/.git" || -x "$OMARCHY_SYNCD_ROOT/bin/omarchy-syncd" ]]; then
	log_info "bootstrap: repository assets already present."
	exit 0
fi

release_url="${OMARCHY_SYNCD_RELEASE_URL:-https://github.com/jtaw5649/omarchy-syncd/releases/latest/download/omarchy-syncd.tar.gz}"
source_url="${OMARCHY_SYNCD_SOURCE_URL:-https://github.com/jtaw5649/omarchy-syncd.git}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

fetch_release() {
	log_info "bootstrap: attempting release download from $release_url"
	if curl -fsSL "$release_url" -o "$workdir/release.tar.gz"; then
		mkdir -p "$workdir/release"
		if tar -xzf "$workdir/release.tar.gz" -C "$workdir/release"; then
			local unpacked
			unpacked="$(find "$workdir/release" -mindepth 1 -maxdepth 1 | head -n 1)"
			if [[ -n "$unpacked" ]]; then
				cp -R "$unpacked"/. "$OMARCHY_SYNCD_ROOT/"
				log_info "bootstrap: release assets extracted."
				return 0
			fi
		fi
	fi
	return 1
}

fetch_source() {
	log_info "bootstrap: falling back to git clone from $source_url"
	if command -v git >/dev/null 2>&1; then
		if git clone "$source_url" "$workdir/src" >/dev/null 2>&1; then
			cp -R "$workdir/src"/. "$OMARCHY_SYNCD_ROOT/"
			log_info "bootstrap: cloned source repository."
			return 0
		fi
	fi
	return 1
}

if fetch_release || fetch_source; then
	log_info "bootstrap: repository hydrated."
else
	log_error "bootstrap: failed to obtain omarchy-syncd assets."
	echo "error: could not download omarchy-syncd release or clone repository." >&2
	exit 1
fi
