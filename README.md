# omarchy-syncd

A minimal Rust utility for Omarchy users who want easy dotfile backups. It clones your private GitHub repository on demand into a temporary workspace and exposes a small CLI:

```text
omarchy-syncd init --repo-url <remote> --path <file-or-dir> [--path ...]
omarchy-syncd backup [-m "Commit message"]
omarchy-syncd restore
```

### Installation

Pick whichever route matches your workflow:

- `cargo install --path .` – installs straight into `~/.cargo/bin` (ensure it is on your `PATH`).
- `./scripts/install.sh [target-dir]` – builds a release binary, copies it into the directory you specify (defaults to `~/.local/bin`), and runs an interactive setup: it can create a new private GitHub repository automatically via `gh repo create`, populate the config with the default path bundle, and add any extra paths you supply.
- `cargo build --release` – then copy `target/release/omarchy-syncd` wherever you prefer.

You only need Rust’s toolchain (`cargo`) for these steps; runtime dependencies are just `git` and a POSIX shell.

### Commands

- `init` – writes `~/.config/omarchy-syncd/config.toml`. Repeat `--path` to track multiple files or directories. Add `--include-defaults` to prefill the Omarchy bundle (Hypr, Waybar, Omarchy, Alacritty, Ghostty, Kitty, btop, fastfetch, Neovim, Walker, SwayOSD, eza, cava). Pass `--verify-remote` if you want to check the remote branch immediately.
- `backup` – clones the remote repo to a temporary directory, copies the tracked files into it, commits, and pushes. If there are no changes it exits cleanly without pushing.
- `restore` – clones the remote repo to a temporary directory and copies tracked files back into `$HOME` (overwriting existing files/directories).

### Default path bundle

If you run `init` with `--include-defaults`, the following paths are tracked automatically (you can still add extra `--path` flags):

```
~/.config/hypr
~/.config/waybar
~/.config/omarchy
~/.config/alacritty
~/.config/ghostty
~/.config/kitty
~/.config/btop
~/.config/fastfetch
~/.config/nvim
~/.config/walker
~/.config/swayosd
~/.config/eza
~/.config/cava
~/.config/git
~/.config/lazygit
```

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
- Symlink information (for example `~/.config/omarchy/current/theme`) is stored inside the backup at `.config/omarchy-syncd/symlinks.json`, and `restore` writes a copy to `~/.config/omarchy-syncd/symlinks.json` on each machine so theme links stay intact.
