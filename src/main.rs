use std::collections::{BTreeSet, HashSet};
use std::io::{self, IsTerminal, Write};
use std::process::Command;

use anyhow::{Context, Result};
use clap::{Args, Parser, Subcommand};
use tempfile::tempdir;

use omarchy_syncd::{
    bundles, config, fs_ops, git,
    selector::{self, Choice},
};

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
    Restore(RestoreArgs),
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
    /// Restrict backup to specified paths (repeat flag).
    #[arg(long = "path")]
    paths: Vec<String>,
    /// Skip the selection UI and back up every configured path.
    #[arg(long = "all")]
    all: bool,
    /// Disable interactive selection even if running in a TTY.
    #[arg(long = "no-ui")]
    no_ui: bool,
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

#[derive(Args)]
struct RestoreArgs {
    /// Restrict restore to specified paths (repeat flag).
    #[arg(long = "path")]
    paths: Vec<String>,
    /// Restore all configured paths without prompting.
    #[arg(long = "all")]
    all: bool,
    /// Disable interactive selection even if running in a TTY.
    #[arg(long = "no-ui")]
    no_ui: bool,
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Init(args) => cmd_init(args),
        Commands::Backup(args) => cmd_backup(args),
        Commands::Restore(args) => cmd_restore(args),
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
            anyhow::bail!(
                "Interactive init requires a TTY. Re-run within a terminal or use --bundle/--path flags."
            );
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

    let resolved_paths = cfg.resolved_paths()?;
    let mut selected_paths = if !args.paths.is_empty() {
        let normalized = normalize_paths(args.paths.clone());
        validate_paths(&resolved_paths, &normalized)?;
        normalized
    } else {
        resolved_paths.clone()
    };

    let is_tty = std::io::stdin().is_terminal() && std::io::stdout().is_terminal();
    let should_prompt = args.paths.is_empty() && !args.all && !args.no_ui && is_tty;
    if should_prompt {
        let choices: Vec<Choice> = resolved_paths
            .iter()
            .map(|path| Choice {
                id: path.clone(),
                label: path.clone(),
            })
            .collect();
        let selection = selector::multi_select(
            "Backup paths> ",
            "Tab: toggle • Enter: confirm • Esc: cancel",
            &choices,
        )?;
        if !selection.is_empty() {
            let normalized = normalize_paths(selection);
            validate_paths(&resolved_paths, &normalized)?;
            selected_paths = normalized;
        }
    }

    if selected_paths.is_empty() {
        selected_paths = resolved_paths;
    }

    let temp = tempdir().context("Failed to create temporary directory")?;
    let repo_dir = temp.path().join("repo");
    git::clone_repo(&cfg.repo.url, &cfg.repo.branch, &repo_dir)
        .context("Failed to clone repository")?;
    fs_ops::snapshot(&selected_paths, &repo_dir)?;

    let message = args
        .message
        .unwrap_or_else(|| "Automated backup".to_string());
    git::commit_and_push(&repo_dir, &message, &cfg.repo.branch)?;
    println!("Backup complete.");
    Ok(())
}

fn cmd_restore(args: RestoreArgs) -> Result<()> {
    let cfg = load_config()?;
    cfg.ensure_non_empty_paths()?;

    let resolved_paths = cfg.resolved_paths()?;
    let mut selected_paths = if !args.paths.is_empty() {
        let normalized = normalize_paths(args.paths.clone());
        validate_paths(&resolved_paths, &normalized)?;
        normalized
    } else {
        resolved_paths.clone()
    };

    let is_tty = std::io::stdin().is_terminal() && std::io::stdout().is_terminal();
    let should_prompt = args.paths.is_empty() && !args.all && !args.no_ui && is_tty;
    if should_prompt {
        let choices: Vec<Choice> = resolved_paths
            .iter()
            .map(|path| Choice {
                id: path.clone(),
                label: path.clone(),
            })
            .collect();
        let selection = selector::multi_select(
            "Restore paths> ",
            "Tab: toggle • Enter: confirm • Esc: cancel",
            &choices,
        )?;
        if !selection.is_empty() {
            let normalized = normalize_paths(selection);
            validate_paths(&resolved_paths, &normalized)?;
            selected_paths = normalized;
        }
    }

    if selected_paths.is_empty() {
        selected_paths = resolved_paths;
    }

    let temp = tempdir().context("Failed to create temporary directory")?;
    let repo_dir = temp.path().join("repo");
    git::clone_repo(&cfg.repo.url, &cfg.repo.branch, &repo_dir)
        .context("Failed to clone repository")?;
    fs_ops::restore(&selected_paths, &repo_dir)?;
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
    let mut cfg = load_config()
        .context("Missing config. Run 'omarchy-syncd init --repo-url <remote>' first.")?;

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
    _current_bundles: &[String],
    current_paths: &[String],
) -> Result<SelectionResult> {
    let header = "Tab: toggle • Enter: confirm • Esc: cancel";
    let bundle_choices: Vec<Choice> = bundles::all()
        .iter()
        .map(|bundle| Choice {
            id: bundle.id.to_string(),
            label: format!("{:<13} {}", bundle.name, bundle.description),
        })
        .collect();
    let mut bundle_selection = selector::multi_select("Bundles> ", header, &bundle_choices)?;

    let mut path_pool: Vec<String> = bundles::all()
        .iter()
        .flat_map(|bundle| bundle.paths.iter().copied())
        .map(String::from)
        .collect();
    for path in current_paths {
        if !path_pool.contains(path) {
            path_pool.push(path.clone());
        }
    }
    path_pool.sort();
    path_pool.dedup();

    let path_choices: Vec<Choice> = path_pool
        .iter()
        .map(|path| Choice {
            id: path.clone(),
            label: path.clone(),
        })
        .collect();
    let mut path_selection = selector::multi_select("Paths> ", header, &path_choices)?;

    while prompt_yes_no("Add another custom path?")? {
        let custom = prompt_string("Dotfile path (e.g. ~/.config/example)")?;
        if !custom.is_empty() && !path_selection.contains(&custom) {
            path_selection.push(custom);
        }
    }

    bundle_selection = normalize_bundles(bundle_selection);
    path_selection = normalize_paths(path_selection);

    Ok(SelectionResult {
        bundles: bundle_selection,
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

fn prompt_yes_no(question: &str) -> Result<bool> {
    loop {
        print!("{question} [y/n]: ");
        io::stdout().flush()?;
        let mut line = String::new();
        io::stdin().read_line(&mut line)?;
        match line.trim().to_lowercase().as_str() {
            "y" | "yes" => return Ok(true),
            "n" | "no" => return Ok(false),
            _ => {
                println!("Please answer 'y' or 'n'.");
            }
        }
    }
}

fn prompt_string(prompt: &str) -> Result<String> {
    print!("{prompt}: ");
    io::stdout().flush()?;
    let mut line = String::new();
    io::stdin().read_line(&mut line)?;
    Ok(line.trim().to_string())
}

fn validate_paths(valid: &[String], selected: &[String]) -> Result<()> {
    let known: HashSet<&str> = valid.iter().map(|p| p.as_str()).collect();
    for path in selected {
        if !known.contains(path.as_str()) {
            anyhow::bail!(
                "Path {} is not part of the configured backup set. Use 'omarchy-syncd install' to add it first.",
                path
            );
        }
    }
    Ok(())
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
