#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "${OMARCHY_SYNCD_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")")/..}/lib/core.sh"

omarchy_syncd_require_command git

omarchy_syncd_git_clone() {
	local repo_url="$1"
	local branch="$2"
	local dest="$3"

	rm -rf -- "$dest"
	omarchy_syncd_info "cloning ${repo_url} (branch ${branch})"
	if git clone --branch "$branch" --single-branch "$repo_url" "$dest" >/dev/null 2>&1; then
		return 0
	fi

	omarchy_syncd_warn "branch clone failed; attempting full clone then checkout"
	rm -rf -- "$dest"
	if ! git clone "$repo_url" "$dest" >/dev/null 2>&1; then
		omarchy_syncd_die "git clone failed for $repo_url"
	fi

	if ! git -C "$dest" checkout "$branch" >/dev/null 2>&1; then
		omarchy_syncd_warn "branch ${branch} missing; creating locally"
		git -C "$dest" checkout -b "$branch" >/dev/null 2>&1 || omarchy_syncd_die "failed to create branch $branch"
	fi
}

omarchy_syncd_git_commit_push() {
	local repo_dir="$1"
	local message="$2"
	local branch="$3"

	if ! git -C "$repo_dir" status --short --untracked-files=all | grep -q .; then
		printf 'No changes to commit.\n'
		omarchy_syncd_info "git: no changes detected"
		return 0
	fi

	git -C "$repo_dir" add --all .

	# Convert submodule entries (160000) to regular directories similar to Rust implementation.
	while read -r mode _ _ path; do
		if [[ "$mode" == 160000 ]]; then
			git -C "$repo_dir" rm --cached "$path" >/dev/null 2>&1 || true
			git -C "$repo_dir" add --force --all "$path"
		fi
	done < <(git -C "$repo_dir" ls-files --stage)

	if ! git -C "$repo_dir" commit -m "$message" >/dev/null 2>&1; then
		printf 'No changes to commit.\n'
		omarchy_syncd_info "git: commit skipped (no changes)"
		return 0
	fi

	omarchy_syncd_info "pushing changes to origin/${branch}"
	git -C "$repo_dir" push origin "$branch" >/dev/null 2>&1 || omarchy_syncd_die "failed to push to origin/${branch}"
}
