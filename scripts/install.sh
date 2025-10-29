#!/usr/bin/env bash
set -euo pipefail

# Bootstrapping: when this script is executed via curl|bash it is not inside
# a cloned repository. Detect that case, clone the repo, and re-run from there.
if [[ "${OMARCHY_SYNCD_BOOTSTRAPPED:-0}" != "1" ]]; then
  script_dir=""
  if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    script_dir="$(
      cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 || exit 0
      pwd -P
    )"
  fi

  if [[ -z "$script_dir" || ! -f "$script_dir/../Cargo.toml" ]]; then
    REPO_URL=${OMARCHY_SYNCD_REPO_URL:-https://github.com/jtaw5649/omarchy-syncd.git}
    REPO_BRANCH=${OMARCHY_SYNCD_REPO_BRANCH:-main}
    CLONE_DEPTH=${OMARCHY_SYNCD_CLONE_DEPTH:-1}

    if ! command -v git >/dev/null 2>&1; then
      echo "error: git is required to install omarchy-syncd." >&2
      exit 1
    fi

    TMP_DIR=$(mktemp -d)
    cleanup() {
      rm -rf "$TMP_DIR"
    }
    trap cleanup EXIT

    echo "Fetching omarchy-syncd from $REPO_URL (branch: $REPO_BRANCH)..."
    git clone --depth "$CLONE_DEPTH" --branch "$REPO_BRANCH" "$REPO_URL" "$TMP_DIR" >/dev/null

    OMARCHY_SYNCD_BOOTSTRAPPED=1 "$TMP_DIR/scripts/install.sh" "$@"
    exit $?
  fi
fi

# Determine project root (one directory above this script).
PROJECT_ROOT="$(
  cd -- "$(dirname "${BASH_SOURCE[0]}")"/.. >/dev/null 2>&1
  pwd -P
)"

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo is required to build omarchy-syncd. Install Rust from https://rustup.rs/ first." >&2
  exit 1
fi

TARGET_DIR="${1:-$HOME/.local/bin}"
BIN_NAME="omarchy-syncd"
BUILD_TARGET="$PROJECT_ROOT/target/release/$BIN_NAME"

echo "Building $BIN_NAME in release mode..."
cargo build --release --manifest-path "$PROJECT_ROOT/Cargo.toml"

mkdir -p "$TARGET_DIR"
cp "$BUILD_TARGET" "$TARGET_DIR/"

HELPER_SCRIPTS=(
  "omarchy-syncd-menu.sh"
  "omarchy-syncd-install.sh"
  "omarchy-syncd-backup.sh"
  "omarchy-syncd-restore.sh"
  "omarchy-syncd-config.sh"
)
for helper in "${HELPER_SCRIPTS[@]}"; do
  cp "$PROJECT_ROOT/scripts/$helper" "$TARGET_DIR/"
  chmod +x "$TARGET_DIR/$helper"
done

echo "Installed $BIN_NAME to $TARGET_DIR"
echo
echo "Make sure $TARGET_DIR is on your PATH. You can check with:"
echo "  echo \"export PATH=\\\"$TARGET_DIR:\\\$PATH\\\"\" >> ~/.bashrc"

INSTALLED_BIN="$TARGET_DIR/$BIN_NAME"
CONFIG_PATH="$HOME/.config/omarchy-syncd/config.toml"
LEGACY_CONFIG="$HOME/.config/syncd/config.toml"

ask_yes_no() {
  local prompt="$1"
  local answer
  while true; do
    if ! read -r -p "$prompt [y/n] " answer; then
      return 2
    fi
    answer=${answer,,}
    case "$answer" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *) echo "Please answer 'y' or 'n'." ;;
    esac
  done
}

if [ -f "$LEGACY_CONFIG" ] && [ ! -f "$CONFIG_PATH" ]; then
  echo
  echo "Migrating legacy config from ~/.config/syncd to ~/.config/omarchy-syncd..."
  mkdir -p "$(dirname "$CONFIG_PATH")"
  mv "$LEGACY_CONFIG" "$CONFIG_PATH"
  if [ -d "$HOME/.config/syncd" ] && [ ! "$(ls -A "$HOME/.config/syncd")" ]; then
    rmdir "$HOME/.config/syncd" 2>/dev/null || true
  fi
fi

if [ -f "$CONFIG_PATH" ]; then
  echo
  echo "Existing config detected at $CONFIG_PATH. Skipping initialization."
  exit 0
fi

if [ ! -t 0 ]; then
  echo
  echo "Non-interactive shell detected; skipping configuration. Run 'omarchy-syncd init --repo-url <remote>' later to set it up."
  exit 0
fi

if ! git config --global --get user.name >/dev/null 2>&1 || \
   ! git config --global --get user.email >/dev/null 2>&1; then
  echo
  echo "Git is not fully configured (missing user.name / user.email)."
  echo "Run 'git config --global user.name \"Your Name\"' and 'git config --global user.email \"you@example.com\"', then rerun the installer."
  exit 1
fi

ask_yes_no "Would you like to create a config now?"
init_status=$?
if [ $init_status -eq 0 ]; then
  repo_url=""
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    ask_yes_no "Create a new private GitHub repository via gh?"
    create_repo_status=$?
    if [ $create_repo_status -eq 0 ]; then
      gh_user="$(gh api user -q '.login' 2>/dev/null || true)"
      default_repo="${gh_user:+$gh_user/}omarchy-dotfiles"
      if [ -z "$default_repo" ]; then
        default_repo="omarchy-dotfiles"
      fi
      while true; do
        read -r -p "GitHub repository (owner/name) [$default_repo]: " repo_full
        repo_full=${repo_full:-$default_repo}
        if [[ "$repo_full" != */* ]]; then
          if [ -n "$gh_user" ]; then
            repo_full="$gh_user/$repo_full"
          else
            echo "Unable to determine GitHub username. Specify repo as owner/name."
            continue
          fi
        fi
        break
      done
      if gh repo view "$repo_full" >/dev/null 2>&1; then
        echo "GitHub repository $repo_full already exists; using existing remote."
        repo_url="git@github.com:${repo_full}.git"
      else
        echo "Creating GitHub repository $repo_full..."
        if gh repo create "$repo_full" --private --confirm >/dev/null 2>&1; then
          repo_url="git@github.com:${repo_full}.git"
          echo "Created private repository at https://github.com/${repo_full}"
        else
          echo "Failed to create GitHub repository (is gh authenticated?)."
          echo "Run 'gh auth login' or create the repo manually, then rerun the installer."
          exit 1
        fi
      fi
    elif [ $create_repo_status -eq 2 ]; then
      echo
      echo "Input closed unexpectedly; skipping configuration. Run 'omarchy-syncd init --repo-url <remote>' later."
      exit 0
    fi
  else
    if command -v gh >/dev/null 2>&1; then
      echo
      echo "gh CLI detected but not authenticated. Run 'gh auth login' to enable automatic repo creation."
    else
      echo
      echo "Install the GitHub CLI (gh) and authenticate if you want the installer to create the repo."
    fi
  fi

  transport=""
  while [ -z "$transport" ]; do
    read -r -p "Use HTTPS or SSH for GitHub access? [https/ssh] " transport
    transport=${transport,,}
    if [ "$transport" != "https" ] && [ "$transport" != "ssh" ] && [ -n "$transport" ]; then
      echo "Please answer 'https' or 'ssh'."
      transport=""
    fi
  done

  if [ -n "$repo_url" ]; then
    if [[ "$repo_url" = git@github.com:* && "$transport" = "https" ]]; then
      repo_url="https://github.com/${repo_full}.git"
    elif [[ "$repo_url" = https://github.com/* && "$transport" = "ssh" ]]; then
      repo_url="git@github.com:${repo_full}.git"
    fi
  fi

  while [ -z "$repo_url" ]; do
    if [ "$transport" = "https" ]; then
      read -r -p "Enter the GitHub repo (owner/name) for HTTPS (e.g. you/omarchy-dotfiles): " repo_full
    else
      read -r -p "Enter the Git remote URL for SSH (e.g. git@github.com:you/omarchy-dotfiles.git): " repo_full
    fi
    if [ -z "$repo_full" ]; then
      echo "A remote is required to continue."
      continue
    fi
    if [ "$transport" = "https" ]; then
      if [[ "$repo_full" != */* ]]; then
        echo "Please provide owner/name (e.g. you/omarchy-dotfiles)."
        continue
      fi
      repo_url="https://github.com/${repo_full}.git"
    else
      repo_url="$repo_full"
    fi
  done

  read -r -p "Branch name to track [main]: " branch_name
  branch_name=${branch_name:-main}

  include_defaults_choice=false
  ask_yes_no "Include Omarchy default path bundles?"
  include_status=$?
  if [ $include_status -eq 0 ]; then
    include_defaults_choice=true
  elif [ $include_status -eq 2 ]; then
    echo
    echo "Input closed unexpectedly; skipping configuration. Run 'omarchy-syncd init --repo-url <remote>' later."
    exit 0
  fi

  read -r -p "Additional paths (comma-separated, optional): " extra_paths

  args=("$INSTALLED_BIN" "init" "--repo-url" "$repo_url" "--branch" "$branch_name")

  if [ "$include_defaults_choice" = true ]; then
    args+=("--include-defaults")
  fi

  if [ -n "$extra_paths" ]; then
    IFS=',' read -ra entries <<< "$extra_paths"
    for entry in "${entries[@]}"; do
      trimmed="${entry#"${entry%%[![:space:]]*}"}"
      trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
      if [ -n "$trimmed" ]; then
        args+=("--path" "$trimmed")
      fi
    done
  fi

  echo
  echo "Running: ${args[*]}"
  "${args[@]}"
  echo "Configuration written to $CONFIG_PATH"

  ask_yes_no "Run an initial backup now?"
  backup_status=$?
  if [ $backup_status -eq 0 ]; then
    echo
    echo "Running initial backup..."
    if "$INSTALLED_BIN" backup; then
      echo "Initial backup completed."
    else
      echo "Initial backup failed. Resolve the issue above and rerun 'omarchy-syncd backup'."
    fi
  elif [ $backup_status -eq 2 ]; then
    echo
    echo "Input closed unexpectedly; skipping initial backup. Run 'omarchy-syncd backup' later."
  else
  echo
  echo "Skipping initial backup. Run 'omarchy-syncd backup' whenever you're ready."
  fi

  ask_yes_no "Add a Walker launcher entry for omarchy-syncd?"
  walker_status=$?
  if [ $walker_status -eq 0 ]; then
    WALKER_CONFIG="$HOME/.config/walker/config.toml"
    mkdir -p "$(dirname "$WALKER_CONFIG")"
    if ! grep -Fq "$TARGET_DIR/omarchy-syncd-menu.sh" "$WALKER_CONFIG" 2>/dev/null; then
      {
        [ -s "$WALKER_CONFIG" ] && echo
        cat <<WALKER_ENTRY
[[commands]]
name = "Omarchy Sync"
exec = "$TARGET_DIR/omarchy-syncd-menu.sh"
category = "Setup"
WALKER_ENTRY
      } >>"$WALKER_CONFIG"
      echo "Added Walker command to $WALKER_CONFIG."
    else
      echo "Walker configuration already contains an omarchy-syncd entry; skipping."
    fi
  elif [ $walker_status -eq 2 ]; then
    echo
    echo "Input closed unexpectedly; skipping Walker configuration.";
  else
    echo
    echo "Skipping Walker integration. You can add it later in ~/.config/walker/config.toml."
  fi
elif [ $init_status -eq 2 ]; then
  echo
  echo "Input closed unexpectedly; skipping configuration. Run 'omarchy-syncd init --repo-url <remote>' later."
  exit 0
else
  echo
  echo "Skipping configuration. Run 'omarchy-syncd init --repo-url <remote>' later to set it up."
fi
