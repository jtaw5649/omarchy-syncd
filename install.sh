#!/usr/bin/env bash
set -euo pipefail

# Determine repository root early so presentation helpers can align prompts.
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  SCRIPT_DIR="$(
    cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 || exit 0
    pwd -P
  )"
fi

if [[ -n "$SCRIPT_DIR" ]]; then
  export OMARCHY_SYNCD_ROOT="$SCRIPT_DIR"
  export OMARCHY_SYNCD_INSTALL="${OMARCHY_SYNCD_ROOT}/install"
  export OMARCHY_SYNCD_LOGO_PATH="${OMARCHY_SYNCD_LOGO_PATH:-$OMARCHY_SYNCD_ROOT/logo.txt}"
  if [[ -f "$OMARCHY_SYNCD_INSTALL/helpers/presentation.sh" ]]; then
    # Sets gum padding/colours so early confirms match Omarchy style.
    source "$OMARCHY_SYNCD_INSTALL/helpers/presentation.sh"
    if declare -F exit_presentation_mode >/dev/null 2>&1 && [[ -z "${OMARCHY_SYNCD_PRESENTATION_EXIT_TRAP:-}" ]]; then
      trap 'exit_presentation_mode' EXIT
      OMARCHY_SYNCD_PRESENTATION_EXIT_TRAP=1
    fi
  fi
fi

ask_yes_no() {
  local prompt="$1"
  local default="${2:-false}"

  if [[ ! -t 0 ]]; then
    return 1
  fi

  if [[ "${OMARCHY_SYNCD_FORCE_NO_GUM:-0}" != "1" ]] && command -v gum >/dev/null 2>&1; then
    local gum_args=()
    if [[ "$default" == "true" ]]; then
      gum_args+=(--default)
    fi
    if gum confirm "${gum_args[@]}" "$prompt"; then
      if declare -F clear_logo >/dev/null 2>&1; then
        clear_logo || true
      fi
      return 0
    else
      if declare -F clear_logo >/dev/null 2>&1; then
        clear_logo || true
      fi
      return 1
    fi
  fi

  local answer=""
  local hint="[y/N]"
  if [[ "$default" == "true" ]]; then
    hint="[Y/n]"
  fi

  while true; do
    read -r -p "$prompt $hint " answer || return 2
    answer=${answer,,}

    if [[ -z "$answer" ]]; then
      if [[ "$default" == "true" ]]; then
        return 0
      else
        return 1
      fi
    fi

    case "$answer" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *) echo "Please answer 'y' or 'n'." ;;
    esac
  done
}

install_dependency() {
  local dep="$1"

  log_info "Attempting to install dependency: $dep"

  if ! command -v pacman >/dev/null 2>&1; then
    log_error "pacman not available; unable to auto-install $dep"
    echo "error: pacman is required to install '$dep'. Install it manually and rerun the installer." >&2
    exit 1
  fi

  local install_cmd=(pacman -S --needed --noconfirm "$dep")
  if command -v sudo >/dev/null 2>&1; then
    if sudo "${install_cmd[@]}"; then
      log_info "Installed $dep via sudo pacman."
      return 0
    fi
  fi

  if "${install_cmd[@]}"; then
    log_info "Installed $dep via pacman."
    return 0
  fi

  log_error "Failed to install dependency $dep automatically."
  echo "error: failed to install required dependency '$dep'. Please install it manually and rerun omarchy-syncd." >&2
  exit 1
}

maybe_bootstrap_dependencies() {
  if [[ "${OMARCHY_SYNCD_SKIP_DEP_CHECK:-0}" == "1" ]]; then
    log_info "Skipping dependency bootstrap via OMARCHY_SYNCD_SKIP_DEP_CHECK."
    return
  fi

  local -a required=(gum git gh tar curl)
  local -a missing=()
  local dep

  for dep in "${required[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      missing+=("$dep")
    fi
  done

  if [[ -n "${OMARCHY_SYNCD_FORCE_MISSING_DEPS:-}" ]]; then
    local forced_entry
    IFS=',' read -ra forced <<<"${OMARCHY_SYNCD_FORCE_MISSING_DEPS}"
    for forced_entry in "${forced[@]}"; do
      # trim surrounding whitespace
      forced_entry="${forced_entry#"${forced_entry%%[![:space:]]*}"}"
      forced_entry="${forced_entry%"${forced_entry##*[![:space:]]}"}"
      if [[ -n "$forced_entry" && " ${missing[*]} " != *" $forced_entry "* ]]; then
        missing+=("$forced_entry")
      fi
    done
    unset forced_entry forced
  fi

  if ((${#missing[@]} == 0)); then
    log_info "All required dependencies already installed."
    return
  fi

  log_info "Missing dependencies detected: ${missing[*]}"

  if command -v gum >/dev/null 2>&1 && [[ "${OMARCHY_SYNCD_FORCE_NO_GUM:-0}" != "1" ]]; then
    gum_panel \
      "Dependencies required by omarchy-syncd:" \
      "" \
      "${missing[@]/#/• }"
    if ! gum confirm "Install missing dependencies now?"; then
      echo "Installation cancelled because required dependencies are missing." >&2
      exit 1
    fi
  else
    echo
    echo "The following required dependencies are missing: ${missing[*]}"
    if ! ask_yes_no "Install dependencies now?" true; then
      echo "Installation cancelled because required dependencies are missing." >&2
      exit 1
    fi
  fi

  for dep in "${missing[@]}"; do
    install_dependency "$dep"
  done

  if [[ " ${missing[*]} " == *" gum "* ]]; then
    source "$OMARCHY_SYNCD_INSTALL/helpers/presentation.sh"
    log_info "Reloaded presentation helpers after installing gum."
  fi

  log_info "Dependency bootstrap complete."
}

# Relaunch via presentation helper for consistent UX
LAUNCHER_AVAILABLE=0
if command -v omarchy-syncd-launcher >/dev/null 2>&1; then
  LAUNCHER_AVAILABLE=1
fi

if [[ -z "${OMARCHY_SYNCD_LAUNCHED_WITH_PRESENTATION:-}" && "${OMARCHY_SYNCD_FORCE_NO_GUM:-0}" != "1" ]]; then
  if (( LAUNCHER_AVAILABLE )); then
    cmd=$(printf '%q ' "$0" "$@")
    exec env OMARCHY_SYNCD_LAUNCHED_WITH_PRESENTATION=1 omarchy-syncd-launcher "$cmd"
  fi
fi

if declare -F clear_logo >/dev/null 2>&1; then
  should_init_presentation=0
  if [[ -n "${OMARCHY_SYNCD_LAUNCHED_WITH_PRESENTATION:-}" || "${OMARCHY_SYNCD_FORCE_NO_GUM:-0}" == "1" ]]; then
    should_init_presentation=1
  elif (( LAUNCHER_AVAILABLE == 0 )); then
    should_init_presentation=1
  fi
  if (( should_init_presentation )); then
    clear_logo || true
  fi
fi

if [[ -t 0 ]]; then
  if [[ "${OMARCHY_SYNCD_FORCE_NO_GUM:-0}" != "1" ]] && command -v gum >/dev/null 2>&1; then
    gum style --border normal --border-foreground 6 --padding "1 2" --margin "1 0" \
      "Ready to install omarchy-syncd?" \
      "" \
      "• We'll install omarchy-syncd binaries and helpers." \
      "• Rerun this installer any time to update or repair."

    if ! ask_yes_no "Continue with install?" true; then
      echo "Installation cancelled."
      exit 0
    fi

  else
    echo
    if ! ask_yes_no "Ready to install omarchy-syncd?" true; then
      echo "Installation cancelled."
      exit 0
    fi
  fi
fi


# --- Platform helpers -------------------------------------------------------

detect_target_triple() {
  if [[ "${OMARCHY_SYNCD_FORCE_PLATFORM:-}" == "arch" ]]; then
    echo "x86_64-unknown-linux-gnu"
    return 0
  fi

  if [[ -n "${OMARCHY_SYNCD_FORCE_PLATFORM:-}" && "${OMARCHY_SYNCD_FORCE_PLATFORM}" != "arch" ]]; then
    return 1
  fi

  local sys arch
  sys=$(uname -s 2>/dev/null || echo unknown)
  arch=$(uname -m 2>/dev/null || echo unknown)

  if [[ "$sys" == Linux* ]] && [[ "$arch" == "x86_64" || "$arch" == "amd64" ]]; then
    echo "x86_64-unknown-linux-gnu"
    return 0
  fi

  return 1
}

assert_supported_platform() {
  if [[ "${OMARCHY_SYNCD_SKIP_PLATFORM_CHECK:-0}" == "1" ]]; then
    return
  fi

  if [[ -n "${OMARCHY_SYNCD_FORCE_PLATFORM:-}" ]]; then
    if [[ "${OMARCHY_SYNCD_FORCE_PLATFORM}" == "arch" ]]; then
      return
    fi
    echo "error: omarchy-syncd currently supports only Arch Linux on x86_64." >&2
    exit 1
  fi

  if [[ $(uname -s 2>/dev/null) != Linux* ]]; then
    echo "error: omarchy-syncd currently supports only Arch Linux on x86_64." >&2
    exit 1
  fi

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" == "arch" || "${ID_LIKE:-}" == *"arch"* ]]; then
      return
    fi
  fi

  if command -v pacman >/dev/null 2>&1; then
    return
  fi

  echo "error: omarchy-syncd currently supports only Arch Linux on x86_64." >&2
  exit 1
}

assert_supported_platform

# --- Download helpers -------------------------------------------------------

download_release() {
  local url="$1"
  local dest="$2"

  if command -v curl >/dev/null 2>&1; then
    if curl -fsSL "$url" -o "$dest"; then
      return 0
    fi
  fi

  if command -v wget >/dev/null 2>&1; then
    if wget -qO "$dest" "$url"; then
      return 0
    fi
  fi

  return 1
}

# --- Bootstrap --------------------------------------------------------------

if [[ "${OMARCHY_SYNCD_BOOTSTRAPPED:-0}" != "1" ]]; then
  script_dir=""
  if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    script_dir="$(
      cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 || exit 0
      pwd -P
    )"
  fi

  if [[ -z "$script_dir" || ! -f "$script_dir/Cargo.toml" ]]; then
    REPO_URL=${OMARCHY_SYNCD_REPO_URL:-https://github.com/jtaw5649/omarchy-syncd.git}
    REPO_BRANCH=${OMARCHY_SYNCD_REPO_BRANCH:-main}
    CLONE_DEPTH=${OMARCHY_SYNCD_CLONE_DEPTH:-1}
    RELEASE_BASE_URL=${OMARCHY_SYNCD_RELEASE_BASE_URL:-https://github.com/jtaw5649/omarchy-syncd/releases/latest/download}
    RELEASE_TARBALL_URL=${OMARCHY_SYNCD_RELEASE_URL:-}

    if [[ -z "$RELEASE_TARBALL_URL" ]]; then
      if target_triple=$(detect_target_triple); then
        RELEASE_TARBALL_URL="$RELEASE_BASE_URL/omarchy-syncd-${target_triple}.tar.gz"
      else
        if [[ "${OMARCHY_SYNCD_SKIP_PLATFORM_CHECK:-0}" == "1" ]]; then
          echo "warning: skipping platform detection; falling back to source build."
        else
          echo "error: omarchy-syncd currently supports only Arch Linux on x86_64." >&2
          exit 1
        fi
      fi
    fi

    TMP_DIR=$(mktemp -d)
    cleanup() { rm -rf "$TMP_DIR"; }
    trap cleanup EXIT

    if [[ "${OMARCHY_SYNCD_USE_SOURCE:-0}" != "1" && -n "$RELEASE_TARBALL_URL" ]]; then
      echo "Attempting to download prebuilt release from $RELEASE_TARBALL_URL..."
      if download_release "$RELEASE_TARBALL_URL" "$TMP_DIR/omarchy-syncd.tar.gz"; then
        if tar -xzf "$TMP_DIR/omarchy-syncd.tar.gz" -C "$TMP_DIR"; then
          if [[ -f "$TMP_DIR/install.sh" ]]; then
            OMARCHY_SYNCD_BOOTSTRAPPED=1 "$TMP_DIR/install.sh" "$@"
            exit $?
          else
            echo "warning: release archive did not contain install.sh; falling back to source build."
          fi
        else
          echo "warning: failed to extract release archive; falling back to source build."
        fi
      else
        if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
          echo "warning: neither curl nor wget is available; falling back to source build."
        else
          echo "warning: could not download release archive; falling back to source build."
        fi
      fi
    fi

    if ! command -v git >/dev/null 2>&1; then
      echo "error: git is required to install omarchy-syncd when no release archive is available." >&2
      exit 1
    fi

    echo "Fetching omarchy-syncd from $REPO_URL (branch: $REPO_BRANCH)..."
    git clone --depth "$CLONE_DEPTH" --branch "$REPO_BRANCH" "$REPO_URL" "$TMP_DIR" >/dev/null
    OMARCHY_SYNCD_BOOTSTRAPPED=1 "$TMP_DIR/install.sh" "$@"
    exit $?
  fi
fi

# --- Environment ------------------------------------------------------------

OMARCHY_SYNCD_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
export OMARCHY_SYNCD_ROOT
export OMARCHY_SYNCD_INSTALL="$OMARCHY_SYNCD_ROOT/install"
export OMARCHY_SYNCD_LOGO_PATH="${OMARCHY_SYNCD_LOGO_PATH:-$OMARCHY_SYNCD_ROOT/logo.txt}"

TARGET_DIR="${1:-$HOME/.local/bin}"
export OMARCHY_SYNCD_BIN_DIR="$TARGET_DIR"
export OMARCHY_SYNCD_STATE_DIR="${OMARCHY_SYNCD_STATE_DIR:-$HOME/.local/share/omarchy-syncd}"
export OMARCHY_SYNCD_ICON_DIR="${OMARCHY_SYNCD_ICON_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/icons}"

INSTALLED_BIN="$OMARCHY_SYNCD_BIN_DIR/omarchy-syncd"
CONFIG_PATH="$HOME/.config/omarchy-syncd/config.toml"
ICON_DEST="$OMARCHY_SYNCD_ICON_DIR/omarchy-syncd.png"
export ICON_DEST CONFIG_PATH

unset OMARCHY_SYNCD_DONE_MESSAGE OMARCHY_SYNCD_EXAMPLE_NOTE OMARCHY_SYNCD_CONFIG_UPDATED_NOTE OMARCHY_SYNCD_EXAMPLE_CREATED

source "$OMARCHY_SYNCD_INSTALL/helpers/presentation.sh"
source "$OMARCHY_SYNCD_INSTALL/helpers/logging.sh"
source "$OMARCHY_SYNCD_INSTALL/helpers/errors.sh"
log_info "Installer environment: root=$OMARCHY_SYNCD_ROOT bin_dir=$OMARCHY_SYNCD_BIN_DIR state_dir=$OMARCHY_SYNCD_STATE_DIR icon_dir=$OMARCHY_SYNCD_ICON_DIR target_bin=$TARGET_DIR"

maybe_bootstrap_dependencies

PREBUILT_BIN="$OMARCHY_SYNCD_ROOT/omarchy-syncd"
SOURCE_BUILD_BIN="$OMARCHY_SYNCD_ROOT/target/release/omarchy-syncd"

if [[ -f "$PREBUILT_BIN" ]]; then
  echo "Using prebuilt omarchy-syncd from release package..."
  log_info "Using packaged binary at $PREBUILT_BIN"
  export OMARCHY_SYNCD_BIN_SOURCE="$PREBUILT_BIN"
elif [[ -f "$SOURCE_BUILD_BIN" ]]; then
  echo "Using existing build artifact at $SOURCE_BUILD_BIN..."
  log_info "Using existing build artifact at $SOURCE_BUILD_BIN"
  export OMARCHY_SYNCD_BIN_SOURCE="$SOURCE_BUILD_BIN"
else
  if ! command -v cargo >/dev/null 2>&1; then
    echo "error: cargo is required to build omarchy-syncd. Install Rust from https://rustup.rs/ first." >&2
    exit 1
  fi
  echo "Building omarchy-syncd in release mode..."
  cargo build --release --manifest-path "$OMARCHY_SYNCD_ROOT/Cargo.toml"
  log_info "Built omarchy-syncd via cargo --release"
  export OMARCHY_SYNCD_BIN_SOURCE="$SOURCE_BUILD_BIN"
fi

source "$OMARCHY_SYNCD_INSTALL/preflight/guard.sh"
source "$OMARCHY_SYNCD_INSTALL/preflight/begin.sh"
run_logged "$OMARCHY_SYNCD_INSTALL/preflight/show-env.sh"

run_logged "$OMARCHY_SYNCD_INSTALL/packaging/paths.sh"
run_logged "$OMARCHY_SYNCD_INSTALL/packaging/binary.sh"
run_logged "$OMARCHY_SYNCD_INSTALL/packaging/helpers.sh"
run_logged "$OMARCHY_SYNCD_INSTALL/packaging/icon.sh"
run_logged "$OMARCHY_SYNCD_INSTALL/packaging/logo.sh"

run_logged "$OMARCHY_SYNCD_INSTALL/post-install/elephant.sh"

run_logged "$OMARCHY_SYNCD_INSTALL/config/paths.sh"

run_logged "$OMARCHY_SYNCD_INSTALL/post-install/summary.sh"

stop_install_log
trap - ERR INT TERM
clear_logo || true

INSTALLED_BIN="$OMARCHY_SYNCD_BIN_DIR/omarchy-syncd"
DEFAULT_BUNDLE_IDS=(
  "core_desktop"
  "terminals"
  "cli_tools"
  "editors"
  "dev_git"
  "creative"
  "system"
)

DEFAULT_BUNDLE_LABELS=(
  "Core Desktop - Hyprland, Waybar, Omarchy, SwayOSD, WayVNC"
  "Terminals - Alacritty, Ghostty, Kitty"
  "CLI Tools - btop, fastfetch, eza, cava, Walker"
  "Editors - Neovim, Typora"
  "Git Tooling - git, lazygit, gh configs"
  "Creative Tools - Aether, Elephant assets"
  "System Services - user systemd units"
)

# --- Interactive helpers ----------------------------------------------------

prompt_string() {
  local prompt="$1"
  local default="${2:-}"

  if [[ ! -t 0 ]]; then
    echo "$default"
    return
  fi

  if [[ "${OMARCHY_SYNCD_FORCE_NO_GUM:-0}" != "1" ]] && command -v gum >/dev/null 2>&1; then
    local __gum_input
    if ! __gum_input=$(gum input --prompt "$prompt " --value "$default"); then
      return 1
    fi
    if declare -F clear_logo >/dev/null 2>&1; then
      clear_logo || true
    fi
    if [[ -z "$__gum_input" ]]; then
      echo "$default"
    else
      echo "$__gum_input"
    fi
  else
    local value
    read -r -p "$prompt " value || return 1
    if [[ -z "$value" ]]; then
      echo "$default"
    else
      echo "$value"
    fi
  fi
}

append_example_comment() {
  if [[ -f "$CONFIG_PATH" ]] && ! grep -q '^# Example: add additional paths later$' "$CONFIG_PATH"; then
    cat <<'EOF' >>"$CONFIG_PATH"

# Example: add additional paths later
# paths = ["~/.config/example", "~/.local/share/example"]
# bundles = ["creative"]
EOF
    log_info "Appended example guidance to $CONFIG_PATH"
  fi
}

write_example_config() {
  local repo_url="$1"
  local branch_name="$2"
  local config_dir="${CONFIG_PATH%/*}"

  mkdir -p "$config_dir"
  cat >"$CONFIG_PATH" <<EOF
# omarchy-syncd configuration
[repo]
url = "$repo_url"
branch = "$branch_name"

[files]
paths = []
bundles = []
# Example: add additional paths later
# paths = ["~/.config/example", "~/.local/share/example"]
# bundles = ["creative"]
EOF
  log_info "Wrote example config to $CONFIG_PATH (repo=$repo_url branch=$branch_name)"
}

collect_config() {
  local config_path="${CONFIG_PATH:-$HOME/.config/omarchy-syncd/config.toml}"
  local config_preexisted=0
  local backup_path=""
  local backup_note=""
  local example_created=0
  local example_note=""
  local config_updated_note=""

  if [[ ! -t 0 ]]; then
    log_info "Non-interactive shell detected; skipping configuration wizard."
    echo "Non-interactive shell detected; skipping configuration. Run \"omarchy-syncd config --write --repo-url <remote> ...\" later."
    return
  fi

  if [[ -f "$config_path" ]]; then
    config_preexisted=1
    log_info "Existing config detected at $config_path"
    if [[ "${OMARCHY_SYNCD_FORCE_RECONFIGURE:-0}" != "1" ]]; then
      if [[ "${OMARCHY_SYNCD_FORCE_NO_GUM:-0}" != "1" ]] && command -v gum >/dev/null 2>&1; then
        clear_logo || true
        gum_panel \
          "Existing omarchy-syncd config found at:" \
          "$config_path"
      else
        echo "Existing omarchy-syncd config found at $config_path."
      fi

      if ! ask_yes_no "Update existing config now?" false; then
        echo "Keeping current configuration. Run \"omarchy-syncd config --write ...\" later if you change your mind."
        log_info "User opted to keep existing configuration."
        return
      fi
    fi

    backup_path="${config_path}.bak.$(date +%Y%m%d%H%M%S)"
    if cp "$config_path" "$backup_path"; then
      backup_note="Previous config backed up to $backup_path."
      log_info "Backed up existing config to $backup_path"
    else
      backup_note="Previous config could not be backed up automatically."
      log_warn "Failed to back up existing config from $config_path"
    fi
  fi

  if ! git config --global --get user.name >/dev/null 2>&1 || ! git config --global user.email >/dev/null 2>&1; then
    echo "Git is not fully configured (missing user.name / user.email)."
    echo "You can continue, but commands that rely on Git identity may prompt later."
    log_warn "Git identity incomplete (user.name or user.email missing). Prompting user."
    if ! ask_yes_no "Continue configuring omarchy-syncd anyway?" true; then
      log_info "User cancelled configuration due to incomplete git identity."
      return
    fi
  fi

  if [[ "${OMARCHY_SYNCD_FORCE_NO_GUM:-0}" != "1" ]] && command -v gum >/dev/null 2>&1; then
    clear_logo || true
    gum_panel \
      "Ready to write your omarchy-syncd config?" \
      "" \
      "• Adds your repo so menus work." \
      "• Needs git + gh (or configure details manually)."
  else
    printf '%s\n' \
      "Ready to write your omarchy-syncd config?" \
      "" \
      "• Adds your repo so menus work." \
      "• Needs git + gh (or configure details manually)."
  fi

  if ! ask_yes_no "Create config now?" true; then
    echo "You can rerun \"omarchy-syncd config --write ...\" later if you prefer."
    log_info "User declined to create configuration."
    return
  fi

  local repo_url=""
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    if ask_yes_no "Create a new private GitHub repository via gh?"; then
      local gh_user default_repo repo_full
      gh_user="$(gh api user -q '.login' 2>/dev/null || true)"
      default_repo="${gh_user:+$gh_user/}omarchy-dotfiles"
      repo_full=$(prompt_string "GitHub repository (owner/name) [$default_repo]:" "$default_repo")
      if [[ "$repo_full" != */* && -n "$gh_user" ]]; then
        repo_full="$gh_user/$repo_full"
      fi
      if gh repo view "$repo_full" >/dev/null 2>&1; then
        repo_url="git@github.com:${repo_full}.git"
      else
        if gh repo create "$repo_full" --private --branch master --confirm >/dev/null 2>&1; then
          repo_url="git@github.com:${repo_full}.git"
        else
          return
        fi
      fi
    fi
  else
    repo_url=""
  fi

  local transport=""
  while [[ -z "$transport" ]]; do
    transport=$(prompt_string "Use HTTPS or SSH for GitHub access? [https/ssh]:" "")
    transport=${transport,,}
    if [[ "$transport" != "https" && "$transport" != "ssh" ]]; then
      echo "Please answer 'https' or 'ssh'."
      transport=""
    fi
  done

  if [[ -z "$repo_url" ]]; then
    if [[ "$transport" == "https" ]]; then
      repo_url=$(prompt_string "Enter the GitHub repo (owner/name) for HTTPS:" "")
      if [[ "$repo_url" != */* ]]; then
        echo "Expected owner/name format." >&2
        return
      fi
      repo_url="https://github.com/${repo_url}.git"
    else
      repo_url=$(prompt_string "Enter the Git remote URL for SSH:" "")
    fi
  else
    if [[ "$repo_url" = git@github.com:* && "$transport" = "https" ]]; then
      repo_url="https://github.com/${repo_url#git@github.com:}.git"
    elif [[ "$repo_url" = https://github.com/* && "$transport" = "ssh" ]]; then
      repo_url="git@github.com:${repo_url#https://github.com/}"
    fi
  fi

  local branch_name
  branch_name=$(prompt_string "Branch name to track [master]:" "master")
  log_info "Configuration will track branch $branch_name"

  local include_defaults=false
  local manual_mode=false
  local -a manual_bundle_ids=()
  if [[ "${OMARCHY_SYNCD_FORCE_NO_GUM:-0}" != "1" ]] && command -v gum >/dev/null 2>&1; then
    clear_logo || true
    gum_panel \
      "Include Omarchy default path bundles?" \
      "" \
      "• Core Desktop (Hyprland, Waybar, Omarchy theme, SwayOSD, WayVNC)" \
      "• Terminals (Alacritty, Ghostty, Kitty)" \
      "• CLI Tools (btop, fastfetch, eza, cava, Walker)" \
      "• Editors (Neovim, Typora)" \
      "• Git Tooling (git, lazygit, gh configs)" \
      "• Creative Tools (Aether, Elephant assets)" \
      "• System Services (user systemd units)"

    local bundle_action
    bundle_action=$(gum choose --cursor "➤" --height 6 --header "↓↑ navigate • Space toggles • Enter confirms" \
      "Include all default bundles" \
      "Manual bundle selection" \
      "Skip default bundles") || bundle_action="Skip default bundles"
    if declare -F clear_logo >/dev/null 2>&1; then
      clear_logo || true
    fi

    case "$bundle_action" in
      "Include all default bundles")
        include_defaults=true
        ;;
      "Manual bundle selection")
        manual_mode=true
        local selection
        selection=$(gum choose --no-limit --cursor "➤" --height 12 --header "Bundles are optional; deselect to skip tracking" "${DEFAULT_BUNDLE_LABELS[@]}") || selection=""
        if declare -F clear_logo >/dev/null 2>&1; then
          clear_logo || true
        fi
        if [[ -n "$selection" ]]; then
          manual_bundle_ids=()
          while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            for idx in "${!DEFAULT_BUNDLE_LABELS[@]}"; do
              if [[ "$line" == "${DEFAULT_BUNDLE_LABELS[$idx]}" ]]; then
                manual_bundle_ids+=("${DEFAULT_BUNDLE_IDS[$idx]}")
                break
              fi
            done
          done <<<"$selection"
        fi
        ;;
      *)
        ;;
    esac
  else
    printf '%s\n' \
      "Include Omarchy default path bundles?" \
      "" \
      "1) Core Desktop - Hyprland, Waybar, Omarchy, SwayOSD, WayVNC" \
      "2) Terminals - Alacritty, Ghostty, Kitty" \
      "3) CLI Tools - btop, fastfetch, eza, cava, Walker" \
      "4) Editors - Neovim, Typora" \
      "5) Git Tooling - git, lazygit, gh configs" \
      "6) Creative Tools - Aether, Elephant assets" \
      "7) System Services - user systemd units" \
      "" \
      "Enter 'm' for manual selection."
    printf "Include defaults? [Y/n/m]: "
    local answer
    read -r answer || answer=""
    case "${answer,,}" in
      ""|"y"|"yes")
        include_defaults=true
        ;;
      "m"|"manual")
        manual_mode=true
        printf "Enter bundle numbers separated by spaces (e.g. 1 3 5): "
        local manual_input
        read -r manual_input
        manual_bundle_ids=()
        for token in $manual_input; do
          if [[ "$token" =~ ^[0-9]+$ ]]; then
            local idx=$((token - 1))
            if (( idx >= 0 && idx < ${#DEFAULT_BUNDLE_IDS[@]} )); then
              manual_bundle_ids+=("${DEFAULT_BUNDLE_IDS[$idx]}")
            fi
          fi
        done
        ;;
      *)
        ;;
    esac
  fi

  local extra_paths=""
  if [[ "$include_defaults" == true || "$manual_mode" == true ]]; then
    extra_paths=$(prompt_string "Additional paths (comma-separated, optional):" "")
  fi
  if [[ "$include_defaults" == true ]]; then
    log_info "User opted to include all default bundles."
  elif (( ${#manual_bundle_ids[@]} > 0 )); then
    log_info "User selected manual bundles: ${manual_bundle_ids[*]}"
  else
    log_info "No default bundles selected."
  fi
  if [[ -n "$extra_paths" ]]; then
    log_info "Additional paths requested: $extra_paths"
  fi

  local args=("$INSTALLED_BIN" "config" "--write" "--repo-url" "$repo_url" "--branch" "$branch_name")
  if [[ "$include_defaults" == true ]]; then
    args+=("--include-defaults")
  fi
  if (( ${#manual_bundle_ids[@]} > 0 )); then
    for bundle_id in "${manual_bundle_ids[@]}"; do
      args+=("--bundle" "$bundle_id")
    done
  fi
  if [[ -n "$extra_paths" ]]; then
    IFS=',' read -ra entries <<<"$extra_paths"
    for entry in "${entries[@]}"; do
      entry="${entry#${entry%%[![:space:]]*}}"
      entry="${entry%${entry##*[![:space:]]}}"
      [[ -n "$entry" ]] && args+=("--path" "$entry")
    done
  fi

  local example_note=""
  if [[ "$include_defaults" == true || ${#manual_bundle_ids[@]} -gt 0 || -n "$extra_paths" ]]; then
    if (( config_preexisted == 1 )); then
      args+=("--force")
    fi
    log_info "Invoking omarchy-syncd config writer with args: ${args[*]}"
    if "${args[@]}"; then
      append_example_comment
      log_info "Config writer completed successfully."
    else
      log_error "Config writer failed with status $?"
      return
    fi
  else
    write_example_config "$repo_url" "$branch_name"
    example_note="Example config created at $CONFIG_PATH. Edit this file to add bundles or paths."
    example_created=1
  fi

  if (( config_preexisted == 1 )); then
    config_updated_note="Updated existing config at $config_path."
    if [[ -n "$backup_note" ]]; then
      config_updated_note+=" $backup_note"
    fi
    log_info "Configuration updated at $config_path"
  else
    log_info "Initial configuration created at $config_path"
  fi

  export OMARCHY_SYNCD_EXAMPLE_CREATED="$example_created"
  export OMARCHY_SYNCD_EXAMPLE_NOTE="$example_note"
  export OMARCHY_SYNCD_CONFIG_UPDATED_NOTE="$config_updated_note"
}

# --- Post install interactions ---------------------------------------------

collect_config

done_lines=()
if [[ -n "${OMARCHY_SYNCD_EXAMPLE_NOTE:-}" ]]; then
  done_lines+=("• ${OMARCHY_SYNCD_EXAMPLE_NOTE}")
fi
if [[ -n "${OMARCHY_SYNCD_CONFIG_UPDATED_NOTE:-}" ]]; then
  done_lines+=("• ${OMARCHY_SYNCD_CONFIG_UPDATED_NOTE}")
fi
done_lines+=("• omarchy-syncd binaries installed to $OMARCHY_SYNCD_BIN_DIR.")
if [[ -f "$CONFIG_PATH" ]]; then
  done_lines+=("• Configuration is at $CONFIG_PATH. Update it any time with \"omarchy-syncd config --write\".")
else
  done_lines+=("• No config was written. Run \"omarchy-syncd config --write\" when you're ready to set up your repo.")
fi
if [[ -n "${OMARCHY_SYNCD_INSTALL_LOG_FILE:-}" ]]; then
  done_lines+=("• Install log saved to ${OMARCHY_SYNCD_INSTALL_LOG_FILE}.")
fi
summary_text=$(printf '%s\n' "${done_lines[@]}")
if [[ -n "${OMARCHY_SYNCD_DONE_MESSAGE:-}" ]]; then
  OMARCHY_SYNCD_DONE_MESSAGE+=$'\n\n'"$summary_text"
else
  OMARCHY_SYNCD_DONE_MESSAGE="$summary_text"
fi
done_summary_path="$OMARCHY_SYNCD_STATE_DIR/done-message.txt"
mkdir -p "$(dirname "$done_summary_path")"
printf '%s\n' "$summary_text" >"$done_summary_path"
log_info "Wrote installation summary to $done_summary_path"
export OMARCHY_SYNCD_DONE_MESSAGE
