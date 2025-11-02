#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "${OMARCHY_SYNCD_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")")/..}/lib/core.sh"

omarchy_syncd_fs_expand_path() {
	python3 - "$1" <<'PY'
import os, sys
print(os.path.expanduser(sys.argv[1]))
PY
}

omarchy_syncd_fs_relative_to_home() {
	local path="$1"
	local home="${HOME%/}"
	case "$path" in
	"$home"/*) printf '%s\n' "${path#"$home/"}" ;;
	"$home") printf '\n' ;;
	*) omarchy_syncd_die "configured path ${path} must live under ${home}" ;;
	esac
}

omarchy_syncd_fs_remove_git_dirs() {
	local target="$1"
	find "$target" -type d -name ".git" -prune -exec rm -rf {} + 2>/dev/null || true
}

omarchy_syncd_fs_snapshot() {
	local -n paths_ref="$1"
	local repo_dir="$2"

	mkdir -p -- "$repo_dir"

	local -a symlink_entries=()

	local raw
	for raw in "${paths_ref[@]}"; do
		local expanded
		expanded="$(omarchy_syncd_fs_expand_path "$raw")"

		if [[ ! -e "$expanded" ]]; then
			printf 'Skipping %s because it does not exist on this machine.\n' "$raw"
			omarchy_syncd_warn "snapshot: skipping missing path $raw"
			continue
		fi

		local rel
		rel="$(omarchy_syncd_fs_relative_to_home "$expanded")"
		[[ -n "$rel" ]] || rel="$(basename -- "$expanded")"
		local dest="$repo_dir/$rel"

		if [[ -L "$expanded" ]]; then
			local target
			target="$(readlink "$expanded")" || {
				omarchy_syncd_warn "snapshot: could not read symlink target for $raw"
				continue
			}
			local is_dir="false"
			if [[ -d "$expanded" ]]; then
				is_dir="true"
			fi
			symlink_entries+=("$rel|$target|$is_dir")
			continue
		fi

		if [[ -d "$expanded" ]]; then
			rm -rf -- "$dest"
			mkdir -p -- "$(dirname -- "$dest")"
			if ! cp -a "$expanded" "$dest"; then
				printf 'Skipping %s because copy failed.\n' "$raw"
				omarchy_syncd_warn "snapshot: copy failed for $raw"
				rm -rf -- "$dest"
				continue
			fi
			omarchy_syncd_fs_remove_git_dirs "$dest"
			while IFS= read -r link_path; do
				local rel_link
				rel_link="$(omarchy_syncd_fs_relative_to_home "$link_path")"
				local target
				target="$(readlink "$link_path")" || continue
				local is_dir="false"
				if [[ -d "$link_path" ]]; then
					is_dir="true"
				fi
				symlink_entries+=("$rel_link|$target|$is_dir")
			done < <(find "$expanded" -type l)
		else
			mkdir -p -- "$(dirname -- "$dest")"
			if ! cp -f "$expanded" "$dest"; then
				printf 'Skipping %s because copy failed.\n' "$raw"
				omarchy_syncd_warn "snapshot: copy failed for $raw"
				continue
			fi
		fi
	done

	local meta_dir="$repo_dir/.config/omarchy-syncd"
	local meta_file="$meta_dir/symlinks.json"
	if [[ ${#symlink_entries[@]} -eq 0 ]]; then
		rm -f -- "$meta_file"
		return 0
	fi

	mkdir -p -- "$meta_dir"
	local entries_payload
	entries_payload="$(printf '%s\n' "${symlink_entries[@]}")"
	OMARCHY_SYNCD_SYMLINK_ENTRIES="$entries_payload" python3 - "$meta_file" <<'PY'
import json, os, sys
out = []
for entry in os.environ.get("OMARCHY_SYNCD_SYMLINK_ENTRIES", "").split("\n"):
    if not entry.strip():
        continue
    path, target, is_dir = entry.split("|", 2)
    out.append({"path": path, "target": target, "is_dir": is_dir == "true"})
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    json.dump(out, fh, indent=2)
PY
}

omarchy_syncd_fs_restore() {
	local -n paths_ref="$1"
	local repo_dir="$2"

	local raw
	for raw in "${paths_ref[@]}"; do
		local expanded
		expanded="$(omarchy_syncd_fs_expand_path "$raw")"
		local rel
		rel="$(omarchy_syncd_fs_relative_to_home "$expanded")"
		[[ -n "$rel" ]] || rel="$(basename -- "$expanded")"
		local source="$repo_dir/$rel"

		if [[ ! -e "$source" ]]; then
			printf 'Skipping %s because it is not present in the repository.\n' "$raw"
			omarchy_syncd_warn "restore: skipping missing repo path $raw"
			continue
		fi

		if [[ -d "$source" ]]; then
			rm -rf -- "$expanded"
			mkdir -p -- "$(dirname -- "$expanded")"
			cp -a "$source" "$expanded"
		else
			rm -f -- "$expanded"
			mkdir -p -- "$(dirname -- "$expanded")"
			cp -a "$source" "$expanded"
		fi
	done

	local meta_file="$repo_dir/.config/omarchy-syncd/symlinks.json"
	if [[ -f "$meta_file" ]]; then
		python3 - "$meta_file" <<'PY'
import json, os, shutil, sys

meta_path = sys.argv[1]
home = os.path.expanduser("~")
user_meta = os.path.join(home, ".config", "omarchy-syncd", "symlinks.json")

with open(meta_path, "r", encoding="utf-8") as fh:
    entries = json.load(fh)

for entry in entries:
    rel_path = entry["path"]
    dest = os.path.join(home, rel_path)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if os.path.lexists(dest):
        if os.path.isdir(dest) and not os.path.islink(dest):
            shutil.rmtree(dest)
        else:
            os.unlink(dest)
    target = entry["target"]
    if not os.path.isabs(target):
        target = os.path.join(os.path.dirname(dest), target)
    os.symlink(target, dest)

os.makedirs(os.path.dirname(user_meta), exist_ok=True)
with open(user_meta, "w", encoding="utf-8") as fh:
    json.dump(entries, fh, indent=2)
PY
	fi
}
