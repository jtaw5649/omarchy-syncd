#!/usr/bin/env bash
set -euo pipefail

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

echo "Installed $BIN_NAME to $TARGET_DIR"
echo
echo "Make sure $TARGET_DIR is on your PATH. You can check with:"
echo "  echo \"export PATH=\\\"$TARGET_DIR:\\\$PATH\\\"\" >> ~/.bashrc"

INSTALLED_BIN="$TARGET_DIR/$BIN_NAME"
CONFIG_PATH="$HOME/.config/omarchy-syncd/config.toml"
LEGACY_CONFIG="$HOME/.config/syncd/config.toml"

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

set +e
read -r -p "Would you like to create a config now? [Y/n] " init_choice
status=$?
set -e
if [ $status -ne 0 ]; then
  echo
  echo "Input closed unexpectedly; skipping configuration. Run 'omarchy-syncd init --repo-url <remote>' later."
  exit 0
fi

init_choice=${init_choice:-Y}

if [[ "$init_choice" =~ ^[Yy]$ ]]; then
  repo_url=""
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    set +e
    read -r -p "Create a new private GitHub repository via gh? [Y/n] " create_repo_choice
    status=$?
    set -e
    if [ $status -ne 0 ]; then
      echo
      echo "Input closed unexpectedly; skipping configuration. Run 'omarchy-syncd init --repo-url <remote>' later."
      exit 0
    fi
    create_repo_choice=${create_repo_choice:-Y}
    if [[ "$create_repo_choice" =~ ^[Yy]$ ]]; then
      gh_user="$(gh api user -q '.login' 2>/dev/null || true)"
      default_repo="${gh_user:+$gh_user/}omarchy-dotfiles"
      if [ -z "$default_repo" ]; then
        default_repo="omarchy-dotfiles"
      fi
      read -r -p "GitHub repository (owner/name) [$default_repo]: " repo_full
      repo_full=${repo_full:-$default_repo}
      if [[ "$repo_full" != */* ]]; then
        if [ -n "$gh_user" ]; then
          repo_full="$gh_user/$repo_full"
        else
          echo "Unable to determine GitHub username. Specify repo as owner/name."
          exit 1
        fi
      fi
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

  read -r -p "Include Omarchy default paths bundle? [Y/n] " include_defaults_choice
  include_defaults_choice=${include_defaults_choice:-Y}

  read -r -p "Additional paths (comma-separated, optional): " extra_paths

  args=("$INSTALLED_BIN" "init" "--repo-url" "$repo_url" "--branch" "$branch_name")

  if [[ "$include_defaults_choice" =~ ^[Yy]$ ]]; then
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

  set +e
  read -r -p "Run an initial backup now? [Y/n] " backup_choice
  status=$?
  set -e
  if [ $status -ne 0 ]; then
    echo
    echo "Input closed unexpectedly; skipping initial backup. Run 'omarchy-syncd backup' later."
  else
    backup_choice=${backup_choice:-Y}
    if [[ "$backup_choice" =~ ^[Yy]$ ]]; then
      echo
      echo "Running initial backup..."
      if "$INSTALLED_BIN" backup; then
        echo "Initial backup completed."
      else
        echo "Initial backup failed. Resolve the issue above and rerun 'omarchy-syncd backup'."
      fi
    else
      echo
      echo "Skipping initial backup. Run 'omarchy-syncd backup' whenever you're ready."
    fi
  fi
else
  echo
  echo "Skipping configuration. Run 'omarchy-syncd init --repo-url <remote>' later to set it up."
fi
