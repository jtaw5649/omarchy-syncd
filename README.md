# omarchy-syncd

A minimal Rust utility for Omarchy users who want easy dotfile backups. It clones your private GitHub repository on demand into a temporary workspace and exposes a small CLI:

```text
omarchy-syncd menu
omarchy-syncd backup [-m "Commit message"]
omarchy-syncd restore
omarchy-syncd config [--print-path | --create | --write ...]
```

> **Supported platform:** Arch Linux on x86_64. The installer will exit on other operating systems.

### Installation

**Recommended (remote installer)**

```bash
curl -fsSL https://github.com/jtaw5649/omarchy-syncd/raw/main/install.sh | bash
```

The installer downloads the latest prebuilt release artifact, extracts it to a temporary directory, and runs interactively. If the release download fails (or you export `OMARCHY_SYNCD_USE_SOURCE=1`), it falls back to cloning the repository and building from source. Pass any flags after `--` to forward them to the installer (for example, a custom target directory).

**Local checkout**

- `git clone https://github.com/jtaw5649/omarchy-syncd && cd omarchy-syncd` then run `./install.sh`. The script detects the local clone and skips the bootstrap step.
- `cargo install --path .` – installs straight into `~/.cargo/bin` (ensure it is on your `PATH`).
- `cargo build --release` – then copy `target/release/omarchy-syncd` wherever you prefer.

**Manual release download**

```bash
curl -LO https://github.com/jtaw5649/omarchy-syncd/releases/latest/download/omarchy-syncd-x86_64-unknown-linux-gnu.tar.gz
tar -xzf omarchy-syncd-x86_64-unknown-linux-gnu.tar.gz
./install.sh
```

The installer auto-detects your platform and pulls the matching archive (currently only `x86_64-unknown-linux-gnu`). Override the detection with `OMARCHY_SYNCD_RELEASE_URL=<custom-url>` or change the base path via `OMARCHY_SYNCD_RELEASE_BASE_URL=<mirror>`.

The installer requires Rust’s toolchain (`cargo`), `git`, and a POSIX shell at install time; day-to-day usage only needs `git` and the `omarchy-syncd` binary.

### Commands

- `menu` – lightweight launcher UI with entries for Install, Backup, Restore, and Edit Config. This is what the wrapper scripts expose.
- `backup` – clones the remote repo to a temporary directory, lets you choose which of the configured paths to include, then copies them, commits, and pushes. Use `--all`, `--no-ui`, or `--path <…>` to skip the selector in scripts. If there are no changes it exits cleanly without pushing.
- `restore` – clones the remote repo to a temporary directory, lets you pick which tracked paths to restore, and copies them back into `$HOME` (overwriting existing files/directories). Use `--all`, `--no-ui`, or `--path <…>` to bypass the selector.
- `install` – launches the multi-select installer so you can choose bundles and extra dotfiles (also usable non-interactively with `--bundle`, `--path`, and `--dry-run`).
- `config` – prints or opens `~/.config/omarchy-syncd/config.toml`. Add `--print-path` to avoid launching an editor, use `--create` to ensure the file exists, or call `--write` with `--repo-url`, `--branch`, and optional `--bundle/--path` flags to generate a configuration non-interactively.
- `uninstall` – removes the installed binaries, helper scripts, config directory, and Walker entry.

### Default path bundle

If you enable the "Include Omarchy default path bundles" option during the installer (or invoke `omarchy-syncd config --write --include-defaults ...`), the following bundles are tracked automatically (you can still layer more `--bundle` or `--path` flags):

| Bundle ID        | What it covers                                               |
| ---------------- | ------------------------------------------------------------ |
| `core_desktop`   | Hypr, Waybar, Omarchy assets, SwayOSD, WayVNC                |
| `terminals`      | Alacritty, Ghostty, Kitty                                    |
| `cli_tools`      | btop, fastfetch, eza, cava, Walker                           |
| `editors`        | Neovim, Typora                                               |
| `dev_git`        | git, lazygit, gh                                             |
| `creative`       | Aether, Elephant                                             |
| `system`         | User-level systemd units                                     |

All selectors let you type to filter in place. **Tab** toggles the highlighted entry, **Shift+Tab** selects everything, **Enter** confirms, and **Esc** cancels. The installer shows every path from these bundles and lets you append any custom dotfile paths you want.

Missing directories are skipped during backup with a friendly message.

### Configuration format

```toml
[repo]
url = "git@github.com:you/omarchy-dotfiles.git"
branch = "main"

[files]
paths = [
  "~/.config/hypr",
  "~/.config/waybar",
  "~/.config/omarchy"
]
```

### Notes

- All tracked paths must live under your `$HOME` directory; the tool preserves the relative structure when copying.
- `git` must be available on your `PATH`. Authentication relies on your normal Git configuration (SSH agent, credential helper, etc.).
- Repositories are cloned into a temporary directory for each run, so there is no long-lived local staging area—your private GitHub repository is the source of truth.
- Symlink information (for example `~/.config/omarchy/current/theme`) is stored inside the backup at `.config/omarchy-syncd/symlinks.json`, and `restore` writes a copy to `~/.config/omarchy-syncd/symlinks.json` on each machine so theme links stay intact. **Do not delete this JSON file**—without it, Omarchy theme symlinks and other link-based configs cannot be reconstructed during `restore`.
- After `restore` completes the tool runs `hyprctl reload` (if available) to pick up the updated configuration.
- The helper script `scripts/omarchy-syncd-menu.sh` launches `omarchy-syncd menu`; wire it to Super+Alt+Space (or your preferred launcher) to mirror the Omarchy desktop workflow. The installer can generate the Elephant menu automatically, or replicate the snippet below.
- **Launcher integration:**
  - *Elephant menu:* Create `~/.config/elephant/menus/omarchy-syncd.toml` so the `menus` provider exposes the Omarchy entry:
    ```toml
    # Managed by omarchy-syncd
    name = "omarchy-syncd"
    name_pretty = "Omarchy Syncd"
    icon = "~/.local/share/icons/omarchy-syncd.png"
    global_search = true
    action = "launch"

    [actions]
    launch = "~/.local/bin/omarchy-syncd-menu"

    [[entries]]
    text = "Omarchy Syncd"
    keywords = ["backup", "restore", "install", "config"]
    terminal = true
    ```
    Restart Elephant (for example `pkill elephant && elephant &`) so launchers pick up the updated menu.
  - *Hyprland:* Bind `scripts/omarchy-syncd-menu.sh` (or `omarchy-syncd menu`) to your preferred key combination, e.g. Super+Alt+Space.
