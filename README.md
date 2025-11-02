# omarchy-syncd

A shell-first dotfile sync utility for Omarchy users. It clones your private git repository on demand, exposes a modular CLI, and mirrors the Omarchy installer UX without relying on Rust.

```text
omarchy-syncd menu
omarchy-syncd install [--bundle …]
omarchy-syncd backup [-m "Commit message"]
omarchy-syncd restore
omarchy-syncd config [--print-path | --create | --write …]
omarchy-syncd uninstall [--yes]
```

> **Supported platform:** Arch Linux on x86_64. The installer will exit on other operating systems. All commands only require standard POSIX utilities plus `git`.

## Installation

**Remote installer (recommended)**

```bash
curl -fsSL https://raw.githubusercontent.com/jtaw5649/omarchy-syncd/master/install.sh | bash
```

The installer:
- validates dependencies (including `gum`) and downloads release assets (falling back to `git clone` when offline)
- installs the shell dispatcher and helper shims into `~/.local/bin`
- launches `omarchy-syncd install` so you can pick bundles/paths interactively

When a Hyprland session is detected the installer opens in a floating terminal with logo/summary framing; export `OMARCHY_SYNCD_NO_FLOAT=1` to keep it in the original shell. A placeholder config is written on first run—edit `~/.config/omarchy-syncd/config.toml` and replace the repo URL with your private remote before running `export`, `backup`, or `restore`. Use `OMARCHY_SYNCD_NON_INTERACTIVE=1` with `OMARCHY_SYNCD_INSTALL_ARGS="--bundle …"` to preseed the install.

**Local checkout**

```bash
git clone https://github.com/jtaw5649/omarchy-syncd
cd omarchy-syncd
./install.sh
```

The staged installer detects the local checkout and skips the bootstrap step. For non-interactive validation, run `scripts/smoke-test.sh`.

**Manual tarball**

```bash
git clone https://github.com/jtaw5649/omarchy-syncd
./scripts/build-release.sh  # produces dist/omarchy-syncd-<version>.tar.gz
```

Upload the tarball and point `OMARCHY_SYNCD_RELEASE_URL` at it before executing the remote installer.

## CLI commands

## Uninstall

Run `omarchy-syncd menu` and select **Uninstall** to remove installed binaries, runtime state, Elephant entries, and icons. For non-interactive environments run `omarchy-syncd uninstall --yes`. Existing git repositories and system packages remain untouched.

- `menu` – gum-driven launcher with entries for Install, Backup, Restore, Config, Uninstall, and optional Update when a newer release is detected. Honour `OMARCHY_SYNCD_MENU_CHOICE` to auto-run a selection.
- `install` – multi-select bundle picker; use `--bundle`, `--path`, `--dry-run`, and `--force` for scripting or reuse `OMARCHY_SYNCD_INSTALL_ARGS` during install.
- `backup` – snapshots configured paths into a temp repo, captures symlinks, and pushes to the configured branch. Works headless via `--all`, `--no-ui`, or `--path`.
- `restore` – clones the repo, copies files back into `$HOME`, rehydrates symlinks, and runs `hyprctl reload` when available.
- `config` – manage `~/.config/omarchy-syncd/config.toml`: print, create, or rewrite via `--write`. Bundle metadata loads from `data/bundles.toml`.
- `uninstall` – removes installed binaries, helper shims, config directory, and cached state (`--yes` skips confirmation).

## Default bundles

| Bundle ID      | Description                                   |
| -------------- | --------------------------------------------- |
| core_desktop   | Hyprland, Waybar, Omarchy data, SwayOSD, WayVNC |
| terminals      | Alacritty, Ghostty, Kitty                     |
| cli_tools      | btop, fastfetch, eza, cava, Walker            |
| editors        | Neovim, Typora                                |
| dev_git        | git, lazygit, gh                              |
| creative       | Aether, Elephant                              |
| system         | User-level systemd units                      |

## Environment variables

| Variable | Purpose |
| --- | --- |
| `OMARCHY_SYNCD_NON_INTERACTIVE` | Skip CLI prompts during installer | 
| `OMARCHY_SYNCD_INSTALL_ARGS` | Extra flags passed to `omarchy-syncd install` |
| `OMARCHY_SYNCD_MENU_CHOICE` | Auto-run a menu selection (`backup`, `restore`, etc.) |
| `OMARCHY_SYNCD_FORCE_UPDATE_VERSION` | Override remote version check (testing) |

## Development

- `scripts/run-tests.sh` – runs the Bats suite (`tests/bats/*.bats`).
- `scripts/smoke-test.sh` – exercises the installer in a temp directory.
- `scripts/lint.sh` – optional `shellcheck` + `shfmt` runner.

Rust sources and Cargo manifests have been removed; the entire CLI is maintained in shell.
