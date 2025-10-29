use std::collections::{BTreeSet, HashSet};
use std::io::IsTerminal;
use std::process::Command;

use anyhow::{Context, Result};
use clap::{Args, Parser, Subcommand};
use dialoguer::{theme::ColorfulTheme, Confirm, Input, MultiSelect};
use tempfile::tempdir;

use omarchy_syncd::{bundles, config, fs_ops, git};

use config::{FileConfig, RepoConfig, SyncConfig, load_config, write_config};

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
    /// Launch the interactive selector to choose bundles and dotfiles.
    Install(InstallArgs),
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
    /// Bundle identifier(s) to include. Repeat the flag to add multiple bundles.
    #[arg(long = "bundle")]
    bundles: Vec<String>,
    /// Overwrite existing config.toml if it exists.
    #[arg(long)]
    force: bool,
    /// Check that the remote branch exists during init.
    #[arg(long = "verify-remote")]
    verify_remote: bool,
    /// Include the Omarchy default path bundle.
    #[arg(long = "include-defaults")]
    include_defaults: bool,
    /// Launch an interactive selector to choose bundles and paths.
    #[arg(long = "interactive")]
    interactive: bool,
}

#[derive(Args)]
struct BackupArgs {
    /// Commit message to use when pushing changes. Defaults to "Automated backup".
    #[arg(short, long)]
    message: Option<String>,
}

#[derive(Args)]
struct InstallArgs {
    /// Bundle identifiers to include (repeat flag).
    #[arg(long = "bundle")]
    bundles: Vec<String>,
    /// Explicit dotfile paths to include (repeat flag).
    #[arg(long = "path")]
    paths: Vec<String>,
    /// Skip interactive prompts even if running in a TTY.
    #[arg(long = "no-ui")]
    no_ui: bool,
    /// Print the resulting selection without writing config.toml.
    #[arg(long = "dry-run")]
    dry_run: bool,
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Init(args) => cmd_init(args),
        Commands::Backup(args) => cmd_backup(args),
        Commands::Restore => cmd_restore(),
        Commands::Install(args) => cmd_install(args),
    }
}

fn cmd_init(args: InitArgs) -> Result<()> {
    let InitArgs {
        repo_url,
        branch,
        paths,
        bundles: bundle_flags,
        force,
        verify_remote,
        include_defaults,
        interactive,
    } = args;

    let config_path = config::config_file_path()?;
    if config_path.exists() && !force {
        anyhow::bail!(
            "Config already exists at {}. Re-run with --force to overwrite.",
            config_path.display()
        );
    }

    let mut explicit_unique: HashSet<String> = HashSet::new();
    let mut explicit_paths: Vec<String> = Vec::new();
    for path in paths {
        if explicit_unique.insert(path.clone()) {
            explicit_paths.push(path);
        }
    }

    let mut bundle_ids: BTreeSet<String> = BTreeSet::new();
    if include_defaults {
        for id in bundles::DEFAULT_BUNDLE_IDS {
            bundle_ids.insert((*id).to_string());
        }
    }
    for bundle in bundle_flags {
        bundle_ids.insert(bundle);
    }

    let mut bundle_vec = normalize_bundles(bundle_ids.into_iter().collect());
    bundles::ensure_known(&bundle_vec)?;
    explicit_paths = normalize_paths(explicit_paths);
    explicit_paths = prune_explicit_paths(&bundle_vec, explicit_paths)?;

    if interactive {
        if !(std::io::stdin().is_terminal() && std::io::stdout().is_terminal()) {
            anyhow::bail!("Interactive init requires a TTY. Re-run within a terminal or use --bundle/--path flags.");
        }
        let selection = interactive_selection(&bundle_vec, &explicit_paths)?;
        bundle_vec = normalize_bundles(selection.bundles);
        bundles::ensure_known(&bundle_vec)?;
        explicit_paths = normalize_paths(selection.paths);
        explicit_paths = prune_explicit_paths(&bundle_vec, explicit_paths)?;
    }

    if explicit_paths.is_empty() && bundle_vec.is_empty() {
        anyhow::bail!(
            "No paths provided. Use --path <path> and/or --include-defaults (or select bundles) to configure backups."
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
        files: FileConfig {
            paths: explicit_paths,
            bundles: bundle_vec,
        },
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
    let paths = cfg.resolved_paths()?;
    fs_ops::snapshot(&paths, &repo_dir)?;

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
    let paths = cfg.resolved_paths()?;
    fs_ops::restore(&paths, &repo_dir)?;
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

fn cmd_install(args: InstallArgs) -> Result<()> {
    let mut cfg =
        load_config().context("Missing config. Run 'omarchy-syncd init --repo-url <remote>' first.")?;

    let mut selected_bundles = if !args.bundles.is_empty() {
        args.bundles.clone()
    } else if cfg.files.bundles.is_empty() {
        detect_bundles_from_paths(&cfg.files.paths)
    } else {
        cfg.files.bundles.clone()
    };

    let mut explicit_paths = if !args.paths.is_empty() {
        args.paths.clone()
    } else {
        cfg.files.paths.clone()
    };

    let should_prompt = args.bundles.is_empty()
        && args.paths.is_empty()
        && !args.no_ui
        && std::io::stdin().is_terminal()
        && std::io::stdout().is_terminal();

    selected_bundles = normalize_bundles(selected_bundles);
    bundles::ensure_known(&selected_bundles)?;
    explicit_paths = normalize_paths(explicit_paths);
    let base_paths = prune_explicit_paths(&selected_bundles, explicit_paths.clone())?;

    if should_prompt {
        let selection = interactive_selection(&selected_bundles, &base_paths)?;
        selected_bundles = selection.bundles;
        explicit_paths = selection.paths;
    } else {
        explicit_paths = base_paths;
    }

    selected_bundles = normalize_bundles(selected_bundles);
    bundles::ensure_known(&selected_bundles)?;
    explicit_paths = normalize_paths(explicit_paths);
    explicit_paths = prune_explicit_paths(&selected_bundles, explicit_paths)?;

    if selected_bundles.is_empty() && explicit_paths.is_empty() {
        anyhow::bail!("No bundles or explicit paths selected. Config not updated.");
    }

    if args.dry_run {
        print_selection(&selected_bundles, &explicit_paths);
        return Ok(());
    }

    cfg.files.bundles = selected_bundles;
    cfg.files.paths = explicit_paths;
    write_config(&cfg)?;

    print_selection(&cfg.files.bundles, &cfg.files.paths);
    println!(
        "Saved selection to {}",
        config::config_file_path()?.display()
    );
    Ok(())
}

struct SelectionResult {
    bundles: Vec<String>,
    paths: Vec<String>,
}

fn interactive_selection(
    current_bundles: &[String],
    current_paths: &[String],
) -> Result<SelectionResult> {
    let theme = ColorfulTheme::default();
    let all_bundles = bundles::all();
    let bundle_labels: Vec<String> = all_bundles
        .iter()
        .map(|bundle| format!("{} – {}", bundle.name, bundle.description))
        .collect();
    let bundle_defaults: Vec<bool> = all_bundles
        .iter()
        .map(|bundle| current_bundles.iter().any(|id| id == bundle.id))
        .collect();

    let selected_bundle_indices = MultiSelect::with_theme(&theme)
        .with_prompt("Select dotfile bundles")
        .items(&bundle_labels)
        .defaults(&bundle_defaults)
        .interact_opt()?
        .ok_or_else(|| anyhow::anyhow!("Bundle selection cancelled"))?;

    let mut bundle_choices: Vec<String> = selected_bundle_indices
        .into_iter()
        .map(|idx| all_bundles[idx].id.to_string())
        .collect();

    let mut path_options: Vec<String> = all_bundles
        .iter()
        .flat_map(|bundle| bundle.paths.iter().copied())
        .map(String::from)
        .collect();
    for path in current_paths {
        if !path_options.contains(path) {
            path_options.push(path.clone());
        }
    }
    path_options.sort();
    path_options.dedup();

    let path_defaults: Vec<bool> = path_options
        .iter()
        .map(|path| current_paths.iter().any(|p| p == path))
        .collect();

    let mut path_selection: Vec<String> = MultiSelect::with_theme(&theme)
        .with_prompt("Select individual dotfiles (in addition to bundles)")
        .items(&path_options)
        .defaults(&path_defaults)
        .interact_opt()?
        .ok_or_else(|| anyhow::anyhow!("Path selection cancelled"))?
        .into_iter()
        .map(|idx| path_options[idx].clone())
        .collect();

    loop {
        let add_more = Confirm::with_theme(&theme)
            .with_prompt("Add another custom path?")
            .default(false)
            .interact()?;
        if !add_more {
            break;
        }

        let input: String = Input::with_theme(&theme)
            .with_prompt("Dotfile path (e.g. ~/.config/example)")
            .allow_empty(true)
            .interact_text()?;
        let trimmed = input.trim();
        if trimmed.is_empty() {
            continue;
        }
        let trimmed = trimmed.to_string();
        if !path_selection.contains(&trimmed) {
            path_selection.push(trimmed);
        }
    }

    bundle_choices = normalize_bundles(bundle_choices);
    path_selection = normalize_paths(path_selection);

    Ok(SelectionResult {
        bundles: bundle_choices,
        paths: path_selection,
    })
}

fn detect_bundles_from_paths(paths: &[String]) -> Vec<String> {
    let mut detected: Vec<String> = Vec::new();
    let path_set: HashSet<&str> = paths.iter().map(|p| p.as_str()).collect();
    for bundle in bundles::all() {
        if bundle.paths.iter().all(|path| path_set.contains(*path)) {
            detected.push(bundle.id.to_string());
        }
    }
    normalize_bundles(detected)
}

fn normalize_bundles(bundles: Vec<String>) -> Vec<String> {
    let mut set: BTreeSet<String> = bundles.into_iter().map(|b| b.trim().to_string()).collect();
    set.retain(|b| !b.is_empty());
    set.into_iter().collect()
}

fn normalize_paths(paths: Vec<String>) -> Vec<String> {
    let set: BTreeSet<String> = paths
        .into_iter()
        .map(|p| p.trim().to_string())
        .filter(|p| !p.is_empty())
        .collect();
    set.into_iter().collect()
}

fn prune_explicit_paths(bundles: &[String], paths: Vec<String>) -> Result<Vec<String>> {
    if bundles.is_empty() {
        return Ok(paths);
    }

    let bundle_ids: Vec<String> = bundles.iter().cloned().collect();
    let bundle_paths: HashSet<String> = bundles::resolve_paths(&bundle_ids)?.into_iter().collect();
    Ok(paths
        .into_iter()
        .filter(|path| !bundle_paths.contains(path))
        .collect())
}

fn print_selection(bundles: &[String], paths: &[String]) {
    if bundles.is_empty() {
        println!("Bundles: (none)");
    } else {
        println!("Bundles:");
        for id in bundles {
            if let Some(bundle) = bundles::find(id) {
                println!("  - {} [{}]", bundle.name, bundle.id);
            } else {
                println!("  - {}", id);
            }
        }
    }

    if paths.is_empty() {
        println!("Explicit paths: (none)");
    } else {
        println!("Explicit paths:");
        for path in paths {
            println!("  - {}", path);
        }
    }
}
