#!/usr/bin/env bash
set -euo pipefail

local_bin="$OMARCHY_SYNCD_BIN_DIR/omarchy-syncd"
show_logo_bin="$OMARCHY_SYNCD_BIN_DIR/omarchy-syncd-show-logo"
show_done_bin="$OMARCHY_SYNCD_BIN_DIR/omarchy-syncd-show-done"
readonly OMARCHY_SYNCD_EXIT_CANCELLED=130
if [[ -n "${OMARCHY_SYNCD_ROOT:-}" && -f "$OMARCHY_SYNCD_ROOT/lib/ui.sh" ]]; then
	# shellcheck source=lib/ui.sh
	source "$OMARCHY_SYNCD_ROOT/lib/ui.sh"
fi
# Presentation needs to run before any gum confirm so styling is applied.
# shellcheck source=install/helpers/presentation.sh
source "$OMARCHY_SYNCD_INSTALL/helpers/presentation.sh"
if [[ -n "${OMARCHY_SYNCD_ROOT:-}" && -f "$OMARCHY_SYNCD_ROOT/lib/config.sh" ]]; then
	# shellcheck source=lib/config.sh
	source "$OMARCHY_SYNCD_ROOT/lib/config.sh"
fi
if [[ ! -x "$local_bin" ]]; then
	log_warn "config: omarchy-syncd binary not found at $local_bin; skipping configuration prompt."
	exit 0
fi

install_args=()
if [[ -n "${OMARCHY_SYNCD_INSTALL_ARGS:-}" ]]; then
	read -r -a install_args <<<"$OMARCHY_SYNCD_INSTALL_ARGS"
fi

logo_shown=false
show_cancelled() {
	if command -v gum >/dev/null 2>&1 && [[ -t 0 && -t 1 ]]; then
		gum style --foreground 214 --bold "Installation cancelled"
		gum spin --spinner globe --title "Done! Press any key to close..." -- bash -lc 'read -n 1 -s'
	else
		printf 'Installation cancelled\n'
		if [[ -t 0 ]]; then
			printf 'Press any key to close...\n'
			read -r -n1 -s
		fi
	fi
}

derive_repo_full() {
	local remote="${1:-}"
	remote="${remote%.git}"
	case "$remote" in
		git@github.com:*) printf '%s\n' "${remote#git@github.com:}" ;;
		ssh://git@github.com/*) printf '%s\n' "${remote#ssh://git@github.com/}" ;;
		https://github.com/*) printf '%s\n' "${remote#https://github.com/}" ;;
		*) printf '%s\n' "" ;;
	esac
}

build_github_url() {
	local owner_repo="$1"
	local transport="$2"
	case "$transport" in
		https) printf 'https://github.com/%s.git\n' "$owner_repo" ;;
		ssh) printf 'git@github.com:%s.git\n' "$owner_repo" ;;
		*) printf '%s\n' "$owner_repo" ;;
	esac
}

repo_transport_from_url() {
	local remote="${1:-}"
	case "$remote" in
		git@github.com:*|ssh://git@github.com/*) printf '%s\n' "ssh" ;;
		https://github.com/*) printf '%s\n' "https" ;;
		*) printf '%s\n' "" ;;
	esac
}

configure_repo_after_install() {
	if [[ ! -t 0 || ! -t 1 ]]; then
		return
	fi
	if ! command -v gum >/dev/null 2>&1; then
		return
	fi
	if ! declare -F omarchy_syncd_config_repo_url >/dev/null 2>&1; then
		return
	fi

	clear_logo || true
	gum_panel "Configure dotfile repository" "• Configure the remote repo used by backup and restore." "• You can let GitHub CLI create a private repo or point at an existing remote." "• You may skip for now, but backup/restore will remain disabled."

	local config_tool="$OMARCHY_SYNCD_ROOT/lib/python/config_tool.py"
	if [[ ! -f "$config_tool" ]]; then
		return
	fi

	local existing_repo
	existing_repo="$(omarchy_syncd_config_repo_url 2>/dev/null || true)"
	local branch_default
	branch_default="$(omarchy_syncd_config_repo_branch 2>/dev/null || echo master)"
	branch_default="${branch_default:-master}"
	local placeholder=false
	if omarchy_syncd_config_repo_is_placeholder; then
		placeholder=true
	fi

	local -a selected_bundles=()
	if ! mapfile -t selected_bundles < <(python3 "$config_tool" --root "$OMARCHY_SYNCD_ROOT" read-config --config-path "$OMARCHY_SYNCD_CONFIG_PATH" --field bundles); then
		selected_bundles=()
	fi

	local -a explicit_paths=()
	if ! mapfile -t explicit_paths < <(python3 "$config_tool" --root "$OMARCHY_SYNCD_ROOT" read-config --config-path "$OMARCHY_SYNCD_CONFIG_PATH" --field explicit_paths); then
		explicit_paths=()
	fi

	local base_transport
	base_transport="$(repo_transport_from_url "$existing_repo")"
	if [[ -z "$base_transport" ]]; then
		base_transport="ssh"
	fi

	local gh_ready=false
	if command -v gh >/dev/null 2>&1; then
		if gh auth status >/dev/null 2>&1; then
			gh_ready=true
		fi
	fi

	local configured=false

	while :; do
		local confirm_default="false"
		if [[ "$placeholder" == "true" ]]; then
			confirm_default="true"
		fi

		if ! omarchy_syncd_ui_confirm --default="$confirm_default" "Configure your Omarchy Syncd repository now?"; then
			gum_panel "Repository not configured" "Backup and restore will not work until a repository is set." "You can configure it now or continue and do it later."
			if omarchy_syncd_ui_confirm --default=true "Go back and configure the repository now?"; then
				clear_logo || true
				gum_panel "Configure dotfile repository" "• Configure the remote repo used by backup and restore." "• You can let GitHub CLI create a private repo or point at an existing remote." "• You may skip for now, but backup/restore will remain disabled."
				continue
			fi
			break
		fi

		local repo_url="$existing_repo"
		local repo_full
		repo_full="$(derive_repo_full "$repo_url")"
		local transport_default="$base_transport"
		local transport_choice=""
		local branch_value=""
		local include_defaults="false"
		local repo_status_message=""

		if ! transport_choice=$(printf "%s\n" "https" "ssh" | gum choose --header "Select Git transport" --selected "$transport_default"); then
			gum_panel "Repository setup cancelled." "You can configure the repo later with 'omarchy-syncd config --write --repo-url …'."
			continue
		fi

		if ! branch_value=$(gum input --value "$branch_default" --prompt "branch> "); then
			gum_panel "Repository setup cancelled." "You can configure the repo later with 'omarchy-syncd config --write --repo-url …'."
			continue
		fi
		branch_value="${branch_value:-$branch_default}"
		branch_value="${branch_value//[[:space:]]/}"
		if [[ -z "$branch_value" ]]; then
			branch_value="$branch_default"
		fi

		local use_gh=false
		local gh_user=""
		if [[ "$gh_ready" == "true" ]]; then
			if omarchy_syncd_ui_confirm --default="$placeholder" "Create a private GitHub repository with GitHub CLI?"; then
				use_gh=true
				gh_user="$(gh api user -q '.login' 2>/dev/null || true)"
				local default_repo
				if [[ -n "$gh_user" ]]; then
					default_repo="$gh_user/omarchy-dotfiles"
				else
					default_repo="omarchy-dotfiles"
				fi
				local repo_input=""
				local cancelled=false
				while :; do
					if ! repo_input=$(gum input --placeholder "$default_repo" --value "$default_repo" --prompt "repo> "); then
						cancelled=true
						break
					fi
					repo_input="${repo_input:-$default_repo}"
					repo_input="${repo_input%.git}"
					if [[ "$repo_input" != */* ]]; then
						if [[ -n "$gh_user" ]]; then
							repo_input="$gh_user/$repo_input"
						else
							gum_panel "Invalid repository format." "Provide owner/name (e.g. you/omarchy-dotfiles)."
							continue
						fi
					fi
					break
				done
				if [[ "$cancelled" == "true" ]]; then
					gum_panel "Repository setup cancelled." "You can configure the repo later with 'omarchy-syncd config --write --repo-url …'."
					continue
				fi
				repo_full="$repo_input"
				repo_url="$(build_github_url "$repo_full" "$transport_choice")"
				if [[ -n "$repo_full" ]]; then
					if gh repo view "$repo_full" >/dev/null 2>&1; then
						repo_status_message="• Repository exists: https://github.com/${repo_full}"
					else
						if gh repo create "$repo_full" --private --confirm >/dev/null 2>&1; then
							repo_status_message="• Repository created: https://github.com/${repo_full}"
						else
							gum_panel "Failed to create GitHub repository." "Run 'gh auth login' or create the repo manually, then rerun this installer."
							continue
						fi
					fi
				fi
			fi
		fi

		if [[ "$use_gh" != "true" && -z "$repo_full" ]]; then
			local cancelled=false
			if [[ "$transport_choice" == "https" ]]; then
				while :; do
					local https_input=""
					if ! https_input=$(gum input --placeholder "you/omarchy-dotfiles" --prompt "owner/name> "); then
						cancelled=true
						break
					fi
					https_input="${https_input%.git}"
					if [[ -z "$https_input" ]]; then
						gum_panel "Repository cannot be empty." ""
						continue
					fi
					if [[ "$https_input" == https://github.com/* ]]; then
						repo_url="$https_input"
						repo_full="$(derive_repo_full "$repo_url")"
					elif [[ "$https_input" == */* ]]; then
						repo_full="$https_input"
						repo_url="$(build_github_url "$repo_full" "$transport_choice")"
					else
						gum_panel "Provide owner/name (e.g. you/omarchy-dotfiles) or a full https URL." ""
						continue
					fi
					break
				done
			else
				while :; do
					local ssh_input=""
					if ! ssh_input=$(gum input --placeholder "git@github.com:you/omarchy-dotfiles.git" --prompt "ssh remote> "); then
						cancelled=true
						break
					fi
					if [[ -z "$ssh_input" ]]; then
						gum_panel "Repository cannot be empty." ""
						continue
					fi
					repo_url="$ssh_input"
					repo_full="$(derive_repo_full "$repo_url")"
					if [[ "$repo_url" != git@github.com:* && "$repo_url" != ssh://git@github.com/* && -z "$repo_full" ]]; then
						gum_panel "Enter a full SSH remote (e.g. git@github.com:you/omarchy-dotfiles.git)." ""
						continue
					fi
					break
					done
			fi
			if [[ "$cancelled" == "true" ]]; then
				gum_panel "Repository setup cancelled." "You can configure the repo later with 'omarchy-syncd config --write --repo-url …'."
				continue
			fi
		fi

		if [[ -n "$repo_full" ]]; then
			repo_url="$(build_github_url "$repo_full" "$transport_choice")"
		fi

		if [[ "$transport_choice" == "https" && "$repo_url" != https://github.com/* ]]; then
			local converted_https
			converted_https="$(derive_repo_full "$repo_url")"
			if [[ -n "$converted_https" ]]; then
				repo_full="$converted_https"
				repo_url="$(build_github_url "$repo_full" "$transport_choice")"
			fi
		fi
		if [[ "$transport_choice" == "ssh" && "$repo_url" != git@github.com:* && "$repo_url" != ssh://git@github.com/* ]]; then
			local converted_ssh
			converted_ssh="$(derive_repo_full "$repo_url")"
			if [[ -n "$converted_ssh" ]]; then
				repo_full="$converted_ssh"
				repo_url="$(build_github_url "$repo_full" "$transport_choice")"
			fi
		fi

		if [[ -z "$repo_url" ]]; then
			gum_panel "Repository URL is required." "Configuration unchanged."
			continue
		fi

		if [[ ${#selected_bundles[@]} -eq 0 && ${#explicit_paths[@]} -eq 0 ]]; then
			include_defaults="true"
		fi
		if ! omarchy_syncd_config_write "$repo_url" "$branch_value" "$include_defaults" "false" "true" selected_bundles explicit_paths; then
			gum_panel "Failed to update configuration." "Check $OMARCHY_SYNCD_INSTALL_LOG_FILE for details."
			continue
		fi

		log_info "config: repository configured for $repo_url ($branch_value)"
		if [[ -n "$repo_status_message" ]]; then
			gum_panel "Repository configured" "• URL: $repo_url" "• Branch: $branch_value" "$repo_status_message"
		else
			gum_panel "Repository configured" "• URL: $repo_url" "• Branch: $branch_value"
		fi

		configured=true
		existing_repo="$repo_url"
		branch_default="$branch_value"
		base_transport="$transport_choice"
		break
	done

	local final_repo
	local final_branch
	final_repo="$(python3 "$config_tool" --root "$OMARCHY_SYNCD_ROOT" read-config --config-path "$OMARCHY_SYNCD_CONFIG_PATH" --field repo.url 2>/dev/null || true)"
	final_branch="$(python3 "$config_tool" --root "$OMARCHY_SYNCD_ROOT" read-config --config-path "$OMARCHY_SYNCD_CONFIG_PATH" --field repo.branch 2>/dev/null || echo "$branch_default")"
	final_branch="${final_branch:-$branch_default}"

	if [[ -n "${selection_summary:-}" ]]; then
		selection_summary+=$'\n'
	fi
	if [[ -n "$final_repo" && "$final_repo" != "$OMARCHY_SYNCD_PLACEHOLDER_REPO" ]]; then
		selection_summary+="• Repository: $final_repo ($final_branch)"
	else
		selection_summary+="• Repository: not configured"
		selection_summary+=$'\n• Backup/Restore unavailable until repository is configured.'
	fi
}

run_install_command() {
	local capture_file status reason_output
	capture_file="$(mktemp)"
	if OMARCHY_SYNCD_SELECTION_FILE="$selection_file" "${cmd[@]}" 2> >(tee -a "$OMARCHY_SYNCD_INSTALL_LOG_FILE" "$capture_file" >&2); then
		rm -f "$capture_file"
		failure_reason=""
		return 0
	fi
	status=$?
	if reason_output=$(summarize_failure_reason "$capture_file"); then
		failure_reason="$reason_output"
	else
		failure_reason=""
	fi
	rm -f "$capture_file"
	return "$status"
}
show_failure_panel() {
	local status="$1"
	local reason="${2:-}"

	if $interactive; then
		clear_logo || true
		if [[ -x "$show_logo_bin" ]]; then
			"$show_logo_bin" || true
		fi
	fi
	local -a message_lines=(
		"Installation failed (exit $status)"
		"See $OMARCHY_SYNCD_INSTALL_LOG_FILE for full details."
	)
	if [[ -n "$reason" ]]; then
		message_lines+=("Failure reason:")
		local -a reason_lines=()
		if mapfile -t reason_lines <<<"$(printf '%s\n' "$reason")"; then
			message_lines+=("${reason_lines[@]}")
		fi
	fi
	message_lines+=("Press any key to close.")
	if [[ "${GUM_NO_COLOR:-0}" == "1" ]]; then
		printf 'Installation failed (exit %d)\n' "$status"
		printf 'See %s for full details.\n' "$OMARCHY_SYNCD_INSTALL_LOG_FILE"
		if [[ -n "$reason" ]]; then
			printf 'Failure reason:\n%s\n' "$reason"
		fi
		printf 'Press any key to close.\n'
	else
		gum style --border normal --border-foreground 1 --padding "1 2" --margin "1 0" \
			"${message_lines[@]}"
	fi
	if [[ -t 0 ]]; then
		read -r -n1 -s
	fi
	if $interactive; then
		exit_presentation_mode || true
	fi
}

interactive=false
if [[ -t 0 && -t 1 && "${OMARCHY_SYNCD_NON_INTERACTIVE:-0}" != "1" ]]; then
	interactive=true
fi

if $interactive; then
	if [[ "${GUM_NO_COLOR:-0}" == "1" ]]; then
		printf '\n'
		printf '\nReady to install Omarchy Syncd?\n'
		printf ' - You can exit any time\n'
		printf ' - Requires git and gh to be configured\n\n'
	else
		printf '\n'
		gum style --border normal --border-foreground 6 --padding "1 2" --margin "1 0" \
			"Ready to install Omarchy Syncd?" \
			"" \
			"• You can exit any time" \
			"• Requires git and gh to be configured"
		printf '\n'
	fi
	if ! omarchy_syncd_ui_confirm --default=true "Continue with installation?"; then
		log_warn "config: installation cancelled at confirmation prompt"
		show_cancelled
		exit 0
	fi
fi

if $interactive; then
	printf '\033c'
	clear_logo || true
	logo_shown=true
fi

should_write_placeholder=false
if [[ ! -f "$OMARCHY_SYNCD_CONFIG_PATH" ]]; then
	should_write_placeholder=true
elif $interactive; then
	if [[ "${GUM_NO_COLOR:-0}" == "1" ]]; then
		printf '\nExisting config found: %s\n\n' "$OMARCHY_SYNCD_CONFIG_PATH"
	else
		printf '\n'
		gum style --border normal --border-foreground 214 --padding "1 2" --margin "1 0" \
			"Existing config found:" \
			"$OMARCHY_SYNCD_CONFIG_PATH"
		printf '\n'
	fi
	if ! omarchy_syncd_ui_confirm --default=false "Overwrite existing config?"; then
		log_warn "config: user declined to overwrite existing config"
		show_cancelled
		exit 0
	fi
	should_write_placeholder=true
fi

if [[ "$should_write_placeholder" == true ]]; then
	mkdir -p "$(dirname "$OMARCHY_SYNCD_CONFIG_PATH")"
	log_info "config: writing placeholder configuration"
	if ! "$local_bin" config --write --repo-url "$OMARCHY_SYNCD_PLACEHOLDER_REPO" --branch main --include-defaults --force; then
		log_warn "config: failed to write placeholder configuration"
	fi
fi

if [[ "${OMARCHY_SYNCD_NON_INTERACTIVE:-0}" == "1" ]]; then
	if [[ ${#install_args[@]} -eq 0 ]]; then
		log_warn "config: non-interactive mode requires OMARCHY_SYNCD_INSTALL_ARGS"
		printf 'error: No bundles or paths selected. Use --bundle/--path or run interactively.\n' >&2
		exit 1
	fi
	log_info "config: running omarchy-syncd install in non-interactive mode"
	run_install_command status failure_reason
	if [[ $status -eq 0 ]]; then
		exit 0
	fi
	if [[ -n "$failure_reason" ]]; then
		failure_head="$(printf '%s\n' "$failure_reason" | head -n 1)"
		log_warn "config: non-interactive install failed: ${failure_head}"
	else
		log_warn "config: non-interactive install exited with status $status"
		failure_reason=""
	fi
	printf 'error: Install failed (exit %d). See %s for details.\n' "$status" "$OMARCHY_SYNCD_INSTALL_LOG_FILE" >&2
	if [[ -n "$failure_reason" ]]; then
		printf 'Failure reason:\n%s\n' "$failure_reason" >&2
	fi
	exit "$status"
fi

if $interactive; then
	if ! $logo_shown; then
		clear_logo || true
		logo_shown=true
	fi
	if [[ -x "$show_logo_bin" ]]; then
		"$show_logo_bin" || true
	fi
fi
log_info "config: launching omarchy-syncd install workflow"

if [[ "${GUM_NO_COLOR:-0}" == "1" ]]; then
	printf '\n'
	printf 'Choose default bundles or manually select\n\n'
	printf ' - Update this config at any time in the menu\n'
	printf ' - Config path: %s\n\n' "$OMARCHY_SYNCD_CONFIG_PATH"
else
	printf '\n'
	gum style --border normal --border-foreground 6 --padding "1 2" --margin "1 0" \
		"Choose default bundles or manually select" \
		"" \
		"• Update this config at any time in the menu" \
		"• Config path: $OMARCHY_SYNCD_CONFIG_PATH"
	printf '\n'
fi

status=0
selection_file="$(mktemp)"
cmd=("$local_bin" install --force)
if [[ ${#install_args[@]} -gt 0 ]]; then
	cmd+=("${install_args[@]}")
fi
if $interactive; then
	export OMARCHY_SYNCD_SUPPRESS_SELECTION=1
fi
failure_reason=""
run_install_command
status=$?
if $interactive; then
	unset OMARCHY_SYNCD_SUPPRESS_SELECTION
fi

if [[ -s "$selection_file" ]]; then
	selection_summary=$(<"$selection_file")
else
	selection_summary=""
fi
rm -f "$selection_file"

if [[ $status -eq 0 ]]; then
	if $interactive; then
		configure_repo_after_install
	fi
	if $interactive && [[ -x "$show_done_bin" ]]; then
		export OMARCHY_SYNCD_SKIP_POST_SUMMARY=1
		OMARCHY_SYNCD_SELECTION_SUMMARY="$selection_summary" \
		OMARCHY_SYNCD_CONFIG_PATH="$OMARCHY_SYNCD_CONFIG_PATH" \
		OMARCHY_SYNCD_INSTALL_LOG_FILE="$OMARCHY_SYNCD_INSTALL_LOG_FILE" \
		"$show_done_bin" || true
	fi
	if $interactive; then
		exit_presentation_mode || true
	fi
	exit 0
fi

if [[ $status -eq $OMARCHY_SYNCD_EXIT_CANCELLED ]]; then
	if $interactive && ! $logo_shown; then
		clear_logo || true
		logo_shown=true
	fi
	show_cancelled
	if $interactive; then
		exit_presentation_mode || true
	fi
	exit 0
fi

log_warn "config: install command exited with status $status"
if [[ -n "$failure_reason" ]]; then
	failure_head="$(printf '%s\n' "$failure_reason" | head -n 1)"
	log_warn "config: failure reason: ${failure_head}"
else
	failure_reason=""
fi
export OMARCHY_SYNCD_SUPPRESS_FAILURE_UI=1
if [[ -n "$failure_reason" ]]; then
	export OMARCHY_SYNCD_FAILURE_REASON="$failure_reason"
fi
show_failure_panel "$status" "$failure_reason"
unset OMARCHY_SYNCD_FAILURE_REASON
exit "$status"
