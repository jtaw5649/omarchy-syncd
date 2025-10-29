# omarchy-syncd

A minimal Rust utility for Omarchy users who want easy dotfile backups. It clones your private GitHub repository on demand into a temporary workspace and exposes a small CLI:

```text
omarchy-syncd init --repo-url <remote> --path <file-or-dir> [--path ...]
omarchy-syncd backup [-m "Commit message"]
omarchy-syncd restore
```

### Installation

**Recommended (remote installer)**

```bash
curl -fsSL https://raw.githubusercontent.com/jtaw5649/omarchy-syncd/main/scripts/install.sh | bash
```

The script clones the latest release into a temporary directory, runs the interactive installer, and cleans up automatically. Pass any flags after `--` to forward them to the installer (for example, a custom target directory).

**Local checkout**

- `git clone https://github.com/jtaw5649/omarchy-syncd && cd omarchy-syncd` then run `./scripts/install.sh`. The script detects the local clone and skips the bootstrap step.
- `cargo install --path .` – installs straight into `~/.cargo/bin` (ensure it is on your `PATH`).
- `cargo build --release` – then copy `target/release/omarchy-syncd` wherever you prefer.

The installer requires Rust’s toolchain (`cargo`), `git`, and a POSIX shell at install time; day-to-day usage only needs `git` and the `omarchy-syncd` binary.

### Commands

- `init` – writes `~/.config/omarchy-syncd/config.toml`. Repeat `--path` to track multiple files or directories. Add `--bundle <id>` (repeat as needed) or `--include-defaults` to prefill the Omarchy bundles (Hypr, Waybar, Omarchy, Alacritty, Ghostty, Kitty, btop, fastfetch, Neovim, Walker, SwayOSD, eza, cava, aether, elephant, wayvnc, systemd, Typora, gh). Pass `--interactive` to launch the selector UI (Tab to toggle, Enter to confirm) and `--verify-remote` if you want to check the remote branch immediately.
- `menu` – lightweight launcher UI with entries for Install, Backup, Restore, and Edit Config. This is what the wrapper scripts expose.
- `backup` – clones the remote repo to a temporary directory, lets you choose which of the configured paths to include, then copies them, commits, and pushes. Use `--all`, `--no-ui`, or `--path <…>` to skip the selector in scripts. If there are no changes it exits cleanly without pushing.
- `restore` – clones the remote repo to a temporary directory, lets you pick which tracked paths to restore, and copies them back into `$HOME` (overwriting existing files/directories). Use `--all`, `--no-ui`, or `--path <…>` to bypass the selector.
- `install` – launches the multi-select installer so you can choose bundles and extra dotfiles (also usable non-interactively with `--bundle`, `--path`, and `--dry-run`).
- `config` – prints or opens `~/.config/omarchy-syncd/config.toml`. Add `--print-path` to avoid launching an editor.

### Default path bundle

If you run `init` with `--include-defaults`, the installer tracks all of the built-in bundles (you can still layer more `--bundle` or `--path` flags):

| Bundle ID        | What it covers                                               |
| ---------------- | ------------------------------------------------------------ |
| `core_desktop`   | Hypr, Waybar, Omarchy assets, SwayOSD, WayVNC                |
| `terminals`      | Alacritty, Ghostty, Kitty                                    |
| `cli_tools`      | btop, fastfetch, eza, cava, Walker                           |
| `editors`        | Neovim, Typora                                               |
| `dev_git`        | git, lazygit, gh                                             |
| `creative`       | Aether, Elephant                                             |
| `system`         | User-level systemd units                                     |

All selectors use the same key bindings: **Tab** toggles the highlighted entry, **Enter** confirms, and **Esc** cancels. The installer shows every path from these bundles and lets you append any custom dotfile paths you want.

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
- The helper script `scripts/omarchy-syncd-menu.sh` launches `omarchy-syncd menu`; wire it to Super+Alt+Space (or your preferred launcher) to mirror the Omarchy desktop workflow. The installer can add the Walker entry for you, or use the snippet below.
- **Launcher integration:**
  - *Walker:* Add a command entry to `~/.config/walker/config.toml` (create the file if it does not exist). Adjust the path if you installed somewhere other than `~/.local/bin`:
    ```toml
    [[commands]]
    name = "Omarchy Sync"
    exec = "~/.local/bin/omarchy-syncd-menu.sh"
    category = "Setup"
    ```
    Restart Walker (or reload its config) and the entry will appear in the Install menu.
  - *Hyprland:* Bind `scripts/omarchy-syncd-menu.sh` (or `omarchy-syncd menu`) to your preferred key combination, e.g. Super+Alt+Space.
