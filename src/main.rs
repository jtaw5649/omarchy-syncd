use std::collections::{BTreeSet, HashSet};
use std::env;
use std::fs;
use std::io::{self, IsTerminal, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use anyhow::{Context, Result};
use clap::{Args, Parser, Subcommand};
use tempfile::tempdir;
use which::which;

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
    /// Clone the remote, copy dotfiles, commit, and push to GitHub.
    Backup(BackupArgs),
    /// Clone the remote and restore tracked files into $HOME.
    Restore(RestoreArgs),
    /// Launch the interactive selector to choose bundles and dotfiles.
    Install(InstallArgs),
    /// Open the high-level omarchy-syncd menu.
    Menu,
    /// Inspect or edit the configuration file.
    Config(ConfigArgs),
    /// Remove omarchy-syncd binaries, helpers, and config files.
    Uninstall(UninstallArgs),
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

#[derive(Args)]
struct ConfigArgs {
    /// Launch the given editor instead of $EDITOR.
    #[arg(long)]
    editor: Option<String>,
    /// Print the on-disk config path and exit.
    #[arg(long = "print-path")]
    print_path: bool,
    /// Create an empty config file if it is missing.
    #[arg(long = "create")]
    create: bool,
    /// Write a new configuration instead of opening the editor.
    #[arg(long, requires = "repo_url")]
    write: bool,
    /// Git remote URL to use when writing a configuration.
    #[arg(long = "repo-url", requires = "write")]
    repo_url: Option<String>,
    /// Git branch to track when writing a configuration.
    #[arg(long, default_value = "main")]
    branch: String,
    /// Extra bundles to include when writing a configuration.
    #[arg(long = "bundle")]
    bundles: Vec<String>,
    /// Include the default bundle set when writing a configuration.
    #[arg(long = "include-defaults")]
    include_defaults: bool,
    /// Extra paths to include when writing a configuration.
    #[arg(long = "path")]
    paths: Vec<String>,
    /// Verify the remote branch exists before writing the configuration.
    #[arg(long = "verify-remote")]
    verify_remote: bool,
    /// Overwrite an existing configuration file.
    #[arg(long = "force")]
    force: bool,
}

#[derive(Args)]
struct UninstallArgs {
    /// Skip the confirmation prompt and uninstall immediately.
    #[arg(long)]
    yes: bool,
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Backup(args) => cmd_backup(args),
        Commands::Restore(args) => cmd_restore(args),
        Commands::Install(args) => cmd_install(args),
        Commands::Menu => cmd_menu(),
        Commands::Config(args) => cmd_config(args),
        Commands::Uninstall(args) => cmd_uninstall(args),
    }
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
            "Backup paths (type to filter)> ",
            "Tab toggles, Shift+Tab selects all, Enter confirms, Esc cancels",
            &choices,
            &[],
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
            "Restore paths (type to filter)> ",
            "Tab toggles, Shift+Tab selects all, Enter confirms, Esc cancels",
            &choices,
            &[],
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
    let mut cfg = load_config().context(
        "Missing config. Run 'omarchy-syncd config --write --repo-url <remote> ...' first.",
    )?;

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

fn cmd_menu() -> Result<()> {
    let header = "Enter runs selection • Esc cancels";
    let choices = vec![
        Choice {
            id: "install".to_string(),
            label: "Install – Configure tracked bundles or paths".to_string(),
        },
        Choice {
            id: "backup".to_string(),
            label: "Backup – Snapshot selected dotfiles to the remote".to_string(),
        },
        Choice {
            id: "restore".to_string(),
            label: "Restore – Pull tracked dotfiles back into $HOME".to_string(),
        },
        Choice {
            id: "config".to_string(),
            label: "Config – Edit or inspect omarchy-syncd settings".to_string(),
        },
        Choice {
            id: "uninstall".to_string(),
            label: "Uninstall – Remove omarchy-syncd and its config".to_string(),
        },
    ];

    let selection =
        selector::single_select("Omarchy Syncd (type to filter) >", header, &choices, &[])?;
    match selection.as_str() {
        "install" => run_subcommand(&["install"]),
        "backup" => run_subcommand(&["backup"]),
        "restore" => run_subcommand(&["restore"]),
        "config" => run_subcommand(&["config"]),
        "uninstall" => run_subcommand(&["uninstall"]),
        other => anyhow::bail!("Unknown selection {other}"),
    }
}

fn cmd_config(args: ConfigArgs) -> Result<()> {
    if args.write {
        let repo_url = args
            .repo_url
            .clone()
            .ok_or_else(|| anyhow::anyhow!("--repo-url is required when using --write"))?;
        let mut bundles = args.bundles.clone();
        if args.include_defaults {
            bundles.extend(bundles::DEFAULT_BUNDLE_IDS.iter().map(|id| id.to_string()));
        }
        let write_opts = ConfigWriteOptions {
            repo_url,
            branch: args.branch.clone(),
            bundles,
            paths: args.paths.clone(),
            verify_remote: args.verify_remote,
            force: args.force,
        };
        let written_path = write_sync_configuration(write_opts)?;
        println!("Wrote config to {}", written_path.display());
        return Ok(());
    }

    let config_path = config::config_file_path()?;

    if args.print_path {
        println!("{}", config_path.display());
        return Ok(());
    }

    if args.create {
        let created = ensure_config_file(&config_path)?;
        if created {
            println!("Created config at {}", config_path.display());
        } else {
            println!("Config already exists at {}", config_path.display());
        }
        return Ok(());
    }

    if !config_path.exists() {
        anyhow::bail!(
            "Config not found at {}. Run 'omarchy-syncd config --write --repo-url <remote> ...' first or rerun with --create.",
            config_path.display()
        );
    }

    let header = "Enter runs selection • Ctrl+O opens editor • Esc cancels";
    let choices = vec![
        Choice {
            id: "open_editor".to_string(),
            label: "Open config in editor".to_string(),
        },
        Choice {
            id: "print_path".to_string(),
            label: format!("Show config path ({})", config_path.display()),
        },
        Choice {
            id: "ensure_exists".to_string(),
            label: "Ensure config exists (create if missing)".to_string(),
        },
    ];

    let selection = selector::single_select(
        "Config actions (type to filter) >",
        header,
        &choices,
        &["ctrl-o:accept"],
    )?;

    match selection.as_str() {
        "open_editor" => open_config_in_editor(args.editor.clone())?,
        "print_path" => println!("{}", config_path.display()),
        "ensure_exists" => {
            let created = ensure_config_file(&config_path)?;
            if created {
                println!("Created config at {}", config_path.display());
            } else {
                println!("Config already exists at {}", config_path.display());
            }
        }
        other => anyhow::bail!("Unknown selection {other}"),
    }

    Ok(())
}

fn cmd_uninstall(args: UninstallArgs) -> Result<()> {
    if !args.yes {
        let proceed =
            prompt_yes_no("This will remove omarchy-syncd completely. Do you wish to continue?")?;
        if !proceed {
            println!("Uninstall cancelled.");
            return Ok(());
        }
    }

    let exe_path = env::current_exe().context("Could not determine current executable path")?;
    let bin_dir = exe_path
        .parent()
        .map(Path::to_path_buf)
        .context("Executable path has no parent directory")?;

    // Remove helper scripts first
    let helper_bases = [
        "omarchy-syncd-menu",
        "omarchy-syncd-install",
        "omarchy-syncd-backup",
        "omarchy-syncd-restore",
        "omarchy-syncd-config",
        "omarchy-syncd-uninstall",
    ];
    for base in &helper_bases {
        remove_file_if_exists(&bin_dir.join(base))?;
        remove_file_if_exists(&bin_dir.join(format!("{base}.sh")))?;
    }

    // Remove the primary binary last
    remove_file_if_exists(&bin_dir.join("omarchy-syncd"))?;

    // Remove configuration directory
    let config_path = config::config_file_path()?;
    if config_path.exists() {
        fs::remove_file(&config_path)
            .with_context(|| format!("Failed removing {}", config_path.display()))?;
    }
    let config_dir = config::config_dir()?;
    if config_dir.exists() {
        fs::remove_dir_all(&config_dir)
            .with_context(|| format!("Failed removing {}", config_dir.display()))?;
    }

    remove_walker_entry(&bin_dir)?;

    println!("omarchy-syncd has been uninstalled.");
    Ok(())
}

struct ConfigWriteOptions {
    repo_url: String,
    branch: String,
    bundles: Vec<String>,
    paths: Vec<String>,
    verify_remote: bool,
    force: bool,
}

fn write_sync_configuration(opts: ConfigWriteOptions) -> Result<std::path::PathBuf> {
    let config_path = config::config_file_path()?;
    if config_path.exists() && !opts.force {
        anyhow::bail!(
            "Config already exists at {}. Re-run with --force to overwrite.",
            config_path.display()
        );
    }

    let mut explicit_unique: HashSet<String> = HashSet::new();
    let mut explicit_paths: Vec<String> = Vec::new();
    for path in opts.paths {
        if explicit_unique.insert(path.clone()) {
            explicit_paths.push(path);
        }
    }

    let mut bundle_ids: BTreeSet<String> = BTreeSet::new();
    for bundle in opts.bundles {
        bundle_ids.insert(bundle);
    }

    let bundle_vec = normalize_bundles(bundle_ids.into_iter().collect());
    bundles::ensure_known(&bundle_vec)?;
    explicit_paths = normalize_paths(explicit_paths);
    explicit_paths = prune_explicit_paths(&bundle_vec, explicit_paths)?;

    if explicit_paths.is_empty() && bundle_vec.is_empty() {
        anyhow::bail!(
            "No paths provided. Use --path <path> and/or --bundle <bundle> (or --include-defaults) to configure backups."
        );
    }

    if opts.verify_remote {
        git::verify_remote(&opts.repo_url, &opts.branch).context("Remote verification failed")?;
    }

    let cfg = SyncConfig {
        repo: RepoConfig {
            url: opts.repo_url,
            branch: opts.branch,
        },
        files: FileConfig {
            paths: explicit_paths,
            bundles: bundle_vec,
        },
    };

    write_config(&cfg)?;
    Ok(config_path)
}

fn ensure_config_file(path: &Path) -> Result<bool> {
    if path.exists() {
        return Ok(false);
    }
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(path, b"# omarchy-syncd configuration\n")?;
    Ok(true)
}

fn open_config_in_editor(preferred_editor: Option<String>) -> Result<()> {
    let config_path = config::config_file_path()?;
    ensure_config_file(&config_path)?;

    let editor = preferred_editor
        .or_else(|| env::var("EDITOR").ok())
        .or_else(|| env::var("VISUAL").ok())
        .or_else(find_default_editor)
        .ok_or_else(|| anyhow::anyhow!("No editor found. Set $EDITOR or pass --editor <cmd>."))?;

    let status = Command::new(&editor)
        .arg(&config_path)
        .status()
        .with_context(|| format!("Failed launching editor '{editor}'"))?;
    if !status.success() {
        anyhow::bail!("Editor '{}' exited with status {:?}", editor, status.code());
    }

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
    let header = "Tab toggles, Shift+Tab selects all, Enter confirms, Esc cancels";
    let bundle_choices: Vec<Choice> = bundles::all()
        .iter()
        .map(|bundle| Choice {
            id: bundle.id.to_string(),
            label: format!("{:<13} {}", bundle.name, bundle.description),
        })
        .collect();
    let mut bundle_selection = selector::multi_select(
        "Bundle choices (type to filter)> ",
        header,
        &bundle_choices,
        &[],
    )?;

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
    let mut path_selection = selector::multi_select(
        "Individual paths (type to filter)> ",
        header,
        &path_choices,
        &[],
    )?;

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

fn run_subcommand(args: &[&str]) -> Result<()> {
    let exe = env::current_exe().context("Failed to locate omarchy-syncd executable")?;
    let status = Command::new(exe)
        .args(args)
        .status()
        .with_context(|| format!("Failed to execute subcommand {:?}", args))?;
    if status.success() {
        Ok(())
    } else {
        anyhow::bail!(
            "Subcommand {:?} exited with status {:?}",
            args,
            status.code()
        );
    }
}

fn find_default_editor() -> Option<String> {
    const CANDIDATES: &[&str] = &["nano", "vi", "vim", "nvim", "code", "gedit"];
    for candidate in CANDIDATES {
        if which(candidate).is_ok() {
            return Some(candidate.to_string());
        }
    }
    None
}

fn prompt_yes_no(question: &str) -> Result<bool> {
    loop {
        print!("{question} [Y/n]: ");
        io::stdout().flush()?;
        let mut line = String::new();
        io::stdin().read_line(&mut line)?;
        let trimmed = line.trim();
        match trimmed.to_lowercase().as_str() {
            "y" | "yes" => return Ok(true),
            "n" | "no" => return Ok(false),
            _ => println!("Please answer 'y' or 'n'."),
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

fn remove_file_if_exists(path: &Path) -> Result<()> {
    match fs::remove_file(path) {
        Ok(_) => Ok(()),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(err) => Err(anyhow::Error::new(err))
            .with_context(|| format!("Failed removing {}", path.display())),
    }
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

fn remove_walker_entry(bin_dir: &Path) -> Result<()> {
    let home = match env::var_os("HOME") {
        Some(val) => PathBuf::from(val),
        None => return Ok(()),
    };
    let config_path = home.join(".config/walker/config.toml");
    if !config_path.exists() {
        return Ok(());
    }

    let exec_marker = format!("exec = \"{}/omarchy-syncd-menu\"", bin_dir.display());
    let mut content = fs::read_to_string(&config_path)?;
    let mut changed = false;
    let mut search_start = 0usize;
    loop {
        let slice = &content[search_start..];
        let Some(rel_idx) = slice.find("[[commands]]") else {
            break;
        };
        let idx = search_start + rel_idx;
        let rest = &content[idx + "[[commands]]".len()..];
        let block_end = rest
            .find("[[commands]]")
            .map(|offset| idx + "[[commands]]".len() + offset);
        let end_idx = block_end.unwrap_or(content.len());
        let block = &content[idx..end_idx];
        if block.contains(&exec_marker) {
            // Remove the block and any trailing blank lines
            let mut removal_end = end_idx;
            while removal_end < content.len() && content.as_bytes()[removal_end] == b'\n' {
                removal_end += 1;
            }
            content.replace_range(idx..removal_end, "");
            changed = true;
            search_start = idx;
        } else {
            search_start = end_idx;
        }
    }

    if changed {
        // Normalize to ensure at most a single trailing newline
        let trimmed = content.trim_end_matches('\n');
        let mut output = trimmed.to_string();
        if !output.is_empty() {
            output.push('\n');
        }
        fs::write(&config_path, output)?;
        restart_walker()?;
    }

    Ok(())
}

fn restart_walker() -> Result<()> {
    if which("walker").is_err() {
        return Ok(());
    }

    let _ = Command::new("pkill").arg("-x").arg("walker").status();
    Command::new("walker")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .context("Failed to relaunch walker")?;

    Ok(())
}
