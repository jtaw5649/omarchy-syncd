use std::collections::HashSet;
use std::process::Command;

use anyhow::{Context, Result};
use clap::{Args, Parser, Subcommand};
use tempfile::tempdir;

use omarchy_syncd::{config, fs_ops, git};

use config::{FileConfig, RepoConfig, SyncConfig, load_config, write_config};

const DEFAULT_PATHS: &[&str] = &[
    "~/.config/hypr",
    "~/.config/waybar",
    "~/.config/omarchy",
    "~/.config/alacritty",
    "~/.config/ghostty",
    "~/.config/kitty",
    "~/.config/btop",
    "~/.config/fastfetch",
    "~/.config/nvim",
    "~/.config/walker",
    "~/.config/swayosd",
    "~/.config/eza",
    "~/.config/cava",
    "~/.config/git",
    "~/.config/lazygit",
];

#[derive(Parser)]
#[command(
    author,
    version,
    about = "Minimal dotfile backup tool for Omarchy users",
    propagate_version = true
)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Create or overwrite the backup configuration.
    Init(InitArgs),
    /// Clone the remote, copy dotfiles, commit, and push to GitHub.
    Backup(BackupArgs),
    /// Clone the remote and restore tracked files into $HOME.
    Restore,
}

#[derive(Args)]
struct InitArgs {
    /// Git remote URL to use for backups (should point to a private repo).
    #[arg(long = "repo-url")]
    repo_url: String,
    /// Git branch to track.
    #[arg(long, default_value = "main")]
    branch: String,
    /// Path(s) to include. Repeat the flag to add multiple paths.
    #[arg(long = "path")]
    paths: Vec<String>,
    /// Overwrite existing config.toml if it exists.
    #[arg(long)]
    force: bool,
    /// Check that the remote branch exists during init.
    #[arg(long = "verify-remote")]
    verify_remote: bool,
    /// Include the Omarchy default path bundle.
    #[arg(long = "include-defaults")]
    include_defaults: bool,
}

#[derive(Args)]
struct BackupArgs {
    /// Commit message to use when pushing changes. Defaults to "Automated backup".
    #[arg(short, long)]
    message: Option<String>,
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Init(args) => cmd_init(args),
        Commands::Backup(args) => cmd_backup(args),
        Commands::Restore => cmd_restore(),
    }
}

fn cmd_init(args: InitArgs) -> Result<()> {
    let InitArgs {
        repo_url,
        branch,
        paths,
        force,
        verify_remote,
        include_defaults,
    } = args;

    let config_path = config::config_file_path()?;
    if config_path.exists() && !force {
        anyhow::bail!(
            "Config already exists at {}. Re-run with --force to overwrite.",
            config_path.display()
        );
    }

    let mut unique: HashSet<String> = HashSet::new();
    let mut collected: Vec<String> = Vec::new();

    if include_defaults {
        for path in DEFAULT_PATHS {
            let candidate = (*path).to_string();
            if unique.insert(candidate.clone()) {
                collected.push(candidate);
            }
        }
    }

    for path in paths {
        if unique.insert(path.clone()) {
            collected.push(path);
        }
    }

    if collected.is_empty() {
        anyhow::bail!(
            "No paths provided. Use --path <path> and/or --include-defaults to configure backups."
        );
    }

    if verify_remote {
        git::verify_remote(&repo_url, &branch).context("Remote verification failed")?;
    }

    let cfg = SyncConfig {
        repo: RepoConfig {
            url: repo_url,
            branch,
        },
        files: FileConfig { paths: collected },
    };

    write_config(&cfg)?;
    println!("Wrote config to {}", config_path.display());
    Ok(())
}

fn cmd_backup(args: BackupArgs) -> Result<()> {
    let cfg = load_config()?;
    cfg.ensure_non_empty_paths()?;

    let temp = tempdir().context("Failed to create temporary directory")?;
    let repo_dir = temp.path().join("repo");
    git::clone_repo(&cfg.repo.url, &cfg.repo.branch, &repo_dir)
        .context("Failed to clone repository")?;
    fs_ops::snapshot(&cfg.files.paths, &repo_dir)?;

    let message = args
        .message
        .unwrap_or_else(|| "Automated backup".to_string());
    git::commit_and_push(&repo_dir, &message, &cfg.repo.branch)?;
    println!("Backup complete.");
    Ok(())
}

fn cmd_restore() -> Result<()> {
    let cfg = load_config()?;
    cfg.ensure_non_empty_paths()?;

    let temp = tempdir().context("Failed to create temporary directory")?;
    let repo_dir = temp.path().join("repo");
    git::clone_repo(&cfg.repo.url, &cfg.repo.branch, &repo_dir)
        .context("Failed to clone repository")?;
    fs_ops::restore(&cfg.files.paths, &repo_dir)?;
    println!("Restore complete.");

    match Command::new("hyprctl").arg("reload").status() {
        Ok(status) if status.success() => println!("hyprctl reload executed."),
        Ok(status) => println!(
            "hyprctl reload exited with status {:?}; continuing.",
            status.code()
        ),
        Err(err) => {
            if err.kind() != std::io::ErrorKind::NotFound {
                println!("hyprctl reload failed: {}", err);
            }
        }
    }

    Ok(())
}
