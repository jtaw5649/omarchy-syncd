use std::fs;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command as StdCommand;
use std::thread;
use std::time::{Duration, Instant};

use anyhow::{Context, Result};
use assert_cmd::cargo::cargo_bin;
use omarchy_syncd::{bundles, config::SyncConfig};
use ptyprocess::{PtyProcess, WaitStatus};
use tempfile::tempdir;

fn path_str(path: &Path) -> Result<&str> {
    path.to_str()
        .context("Path contains invalid UTF-8 characters, which git cannot handle in these tests")
}

fn run_git(dir: Option<&Path>, args: &[&str]) -> Result<()> {
    let mut cmd = StdCommand::new("git");
    if let Some(d) = dir {
        cmd.current_dir(d);
    }
    let status = cmd
        .args(args)
        .status()
        .with_context(|| format!("Failed to execute git {:?}", args))?;
    if !status.success() {
        anyhow::bail!("git {:?} exited with {:?}", args, status.code());
    }
    Ok(())
}

fn init_remote_repo(base: &Path, name: &str) -> Result<PathBuf> {
    let remote = base.join(name);
    run_git(Some(base), &["init", "--bare", path_str(&remote)?])?;

    let seed_dir = tempdir()?;
    run_git(Some(seed_dir.path()), &["init"])?;
    run_git(Some(seed_dir.path()), &["config", "user.name", "Seed User"])?;
    run_git(
        Some(seed_dir.path()),
        &["config", "user.email", "seed@example.com"],
    )?;
    fs::write(seed_dir.path().join("README.md"), "seed\n")?;
    run_git(Some(seed_dir.path()), &["add", "."])?;
    run_git(Some(seed_dir.path()), &["commit", "-m", "Initial seed"])?;
    run_git(Some(seed_dir.path()), &["branch", "-M", "master"])?;
    run_git(
        Some(seed_dir.path()),
        &["remote", "add", "origin", path_str(&remote)?],
    )?;
    run_git(Some(seed_dir.path()), &["push", "-u", "origin", "master"])?;
    run_git(
        None,
        &[
            "--git-dir",
            path_str(&remote)?,
            "symbolic-ref",
            "HEAD",
            "refs/heads/main",
        ],
    )?;

    Ok(remote)
}

fn configure_git_env(home: &Path) -> Vec<(&'static str, String)> {
    vec![
        ("HOME", home.display().to_string()),
        (
            "XDG_CONFIG_HOME",
            home.join(".config").display().to_string(),
        ),
        (
            "XDG_DATA_HOME",
            home.join(".local/share").display().to_string(),
        ),
        ("GIT_AUTHOR_NAME", "TTY Test".into()),
        ("GIT_AUTHOR_EMAIL", "tty@example.com".into()),
        ("GIT_COMMITTER_NAME", "TTY Test".into()),
        ("GIT_COMMITTER_EMAIL", "tty@example.com".into()),
    ]
}

fn create_gum_stub(dir: &Path) -> Result<()> {
    fs::create_dir_all(dir)?;
    let script_path = dir.join("gum");
    fs::write(
        &script_path,
        r#"#!/usr/bin/env bash
set -euo pipefail

pull_choice() {
  local file="$1"
  if [[ -z "$file" || ! -f "$file" ]]; then
    return 1
  fi
  mapfile -t lines <"$file"
  local selection=""
  if (( ${#lines[@]} > 0 )); then
    selection="${lines[0]}"
    if (( ${#lines[@]} > 1 )); then
      printf '%s\n' "${lines[@]:1}" >"$file"
    else
      : >"$file"
    fi
  else
    : >"$file"
  fi
  printf '%s' "$selection"
}

case "${1:-}" in
  choose)
    shift || true
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-limit|--default|--cursor|--height|--selected|--header|--align|--margin|--padding)
          shift 2;;
        --)
          shift
          break;;
        *)
          shift;;
      esac
    done
    mapfile -t items || true
    selection=""
    if [[ -n "${GUM_CHOOSE_SEQUENCE_FILE:-}" ]]; then
      selection="$(pull_choice "$GUM_CHOOSE_SEQUENCE_FILE")"
    fi
    if [[ -z "$selection" && -n "${GUM_CHOOSE_SELECTION:-}" ]]; then
      selection="$GUM_CHOOSE_SELECTION"
    fi
    if [[ -z "$selection" && ${#items[@]} -gt 0 ]]; then
      selection="${items[0]}"
    fi
    if [[ "$selection" == "__CANCEL__" ]]; then
      exit 1
    fi
    if [[ -z "$selection" ]]; then
      exit 1
    fi
    selection="${selection//\
/$'\n'}"
    printf '%s\n' "$selection"
    ;;
  confirm)
    shift || true
    answer="${GUM_CONFIRM_RESULT:-true}"
    if [[ -n "${GUM_CONFIRM_SEQUENCE_FILE:-}" ]]; then
      candidate="$(pull_choice "$GUM_CONFIRM_SEQUENCE_FILE")"
      if [[ -n "$candidate" ]]; then
        answer="$candidate"
      fi
    fi
    case "${answer,,}" in
      y|yes|true|1) exit 0;;
      *) exit 1;;
    esac
    ;;
  style)
    cat >/dev/null
    ;;
  *)
    echo "gum stub: unsupported subcommand $1" >&2
    exit 1
    ;;
esac
"#,
    )?;
    fs::set_permissions(&script_path, fs::Permissions::from_mode(0o755))?;
    Ok(())
}

const PTY_TIMEOUT: Duration = Duration::from_secs(45);
const PTY_POLL_INTERVAL: Duration = Duration::from_millis(100);

fn run_in_pty(cmd: StdCommand, input: Option<&[u8]>) -> Result<WaitStatus> {
    let mut process = PtyProcess::spawn(cmd)?;
    if let Some(data) = input {
        let mut stream = process.get_pty_stream()?;
        stream.write_all(data)?;
        stream.flush()?;
    }
    let start = Instant::now();
    loop {
        if start.elapsed() > PTY_TIMEOUT {
            let _ = process.exit(true);
            anyhow::bail!("process timed out after {:?}", PTY_TIMEOUT);
        }
        match process.status()? {
            WaitStatus::StillAlive => {
                thread::sleep(PTY_POLL_INTERVAL);
            }
            status => return Ok(status),
        }
    }
}

fn spawn_in_pty(cmd: StdCommand) -> Result<()> {
    match run_in_pty(cmd, None)? {
        WaitStatus::Exited(_, 0) => Ok(()),
        status => anyhow::bail!("process exited abnormally: {status:?}"),
    }
}

fn spawn_in_pty_with_input(cmd: StdCommand, input: &[u8]) -> Result<()> {
    match run_in_pty(cmd, Some(input))? {
        WaitStatus::Exited(_, 0) => Ok(()),
        status => anyhow::bail!("process exited abnormally: {status:?}"),
    }
}

fn write_sequence_file(base: &Path, name: &str, lines: &[&str]) -> Result<PathBuf> {
    let path = base.join(name);
    fs::write(
        &path,
        lines.join(
            "
",
        ),
    )?;
    Ok(path)
}

fn bundle_label(id: &str) -> String {
    let bundles = bundles::all();
    let width = bundles.iter().map(|b| b.name.len()).max().unwrap_or(0);
    let bundle = bundles
        .iter()
        .find(|bundle| bundle.id == id)
        .expect("bundle exists");
    format!(
        "{name:<width$}  {description}",
        name = bundle.name,
        description = bundle.description,
        width = width
    )
}

fn run_config(home: &Path, remote: &Path) -> Result<()> {
    let mut cmd = StdCommand::new(cargo_bin("omarchy-syncd"));
    cmd.arg("config")
        .args([
            "--write",
            "--repo-url",
            path_str(remote)?,
            "--path",
            "~/.config/hypr",
        ])
        .envs(configure_git_env(home));
    let status = cmd.status()?;
    if !status.success() {
        anyhow::bail!("config command failed with status {:?}", status.code());
    }
    Ok(())
}

fn clone_repository(base: &Path, remote: &Path, checkout: &Path) -> Result<()> {
    if checkout.exists() {
        fs::remove_dir_all(checkout).ok();
    }
    fs::create_dir_all(checkout.parent().unwrap())?;
    run_git(
        Some(base),
        &[
            "clone",
            "--branch",
            "master",
            "--single-branch",
            path_str(remote)?,
            path_str(checkout)?,
        ],
    )
}

#[test]
fn backup_prompts_paths_over_tty_with_gum_stub() -> Result<()> {
    let temp = tempdir()?;
    let home = temp.path().join("home");
    fs::create_dir_all(&home)?;

    let remote = init_remote_repo(temp.path(), "tty-backup.git")?;
    let hypr_conf = home.join(".config/hypr/hyprland.conf");
    fs::create_dir_all(hypr_conf.parent().unwrap())?;
    fs::write(&hypr_conf, "monitor = HDMI-A-1\n")?;
    run_config(&home, &remote)?;

    let gum_dir = temp.path().join("gum-bin");
    create_gum_stub(&gum_dir)?;

    let mut cmd = StdCommand::new(cargo_bin("omarchy-syncd"));
    cmd.arg("backup")
        .env("GUM_CHOOSE_SELECTION", "~/.config/hypr")
        .envs(configure_git_env(&home))
        .env(
            "PATH",
            format!(
                "{}:{}",
                gum_dir.display(),
                std::env::var("PATH").unwrap_or_default()
            ),
        );
    spawn_in_pty(cmd)?;

    let checkout = temp.path().join("clone-backup-tty");
    clone_repository(temp.path(), &remote, &checkout)?;
    assert!(
        checkout.join(".config/hypr/hyprland.conf").exists(),
        "interactive backup should populate the remote"
    );

    Ok(())
}

#[test]
fn restore_prompts_paths_over_tty_with_gum_stub() -> Result<()> {
    let temp = tempdir()?;
    let home = temp.path().join("home");
    fs::create_dir_all(&home)?;

    let remote = init_remote_repo(temp.path(), "tty-restore.git")?;
    let hypr_conf = home.join(".config/hypr/hyprland.conf");
    fs::create_dir_all(hypr_conf.parent().unwrap())?;
    fs::write(&hypr_conf, "monitor = HDMI-A-1\n")?;
    run_config(&home, &remote)?;

    // Perform initial backup using non-interactive mode so remote has content
    let mut backup_cmd = StdCommand::new(cargo_bin("omarchy-syncd"));
    backup_cmd
        .arg("backup")
        .args(["--all", "--no-ui"])
        .envs(configure_git_env(&home));
    spawn_in_pty(backup_cmd)?;

    fs::remove_file(&hypr_conf)?;

    let gum_dir = temp.path().join("gum-bin-restore");
    create_gum_stub(&gum_dir)?;

    let mut restore_cmd = StdCommand::new(cargo_bin("omarchy-syncd"));
    restore_cmd
        .arg("restore")
        .env("GUM_CHOOSE_SELECTION", "~/.config/hypr")
        .envs(configure_git_env(&home))
        .env(
            "PATH",
            format!(
                "{}:{}",
                gum_dir.display(),
                std::env::var("PATH").unwrap_or_default()
            ),
        );
    spawn_in_pty(restore_cmd)?;

    assert!(
        hypr_conf.exists(),
        "interactive restore should recreate the config"
    );
    Ok(())
}

#[test]
fn install_prompts_bundles_and_custom_paths_over_tty_with_gum_stub() -> Result<()> {
    let temp = tempdir()?;
    let home = temp.path().join("home");
    fs::create_dir_all(&home)?;

    let remote = init_remote_repo(temp.path(), "tty-install.git")?;
    run_config(&home, &remote)?;

    let choose_sequence = write_sequence_file(
        temp.path(),
        "gum-install.txt",
        &[&bundle_label("core_desktop"), "~/.config/hypr"],
    )?;

    let gum_dir = temp.path().join("gum-bin-install");
    create_gum_stub(&gum_dir)?;

    let mut cmd = StdCommand::new(cargo_bin("omarchy-syncd"));
    cmd.arg("install")
        .env(
            "PATH",
            format!(
                "{}:{}",
                gum_dir.display(),
                std::env::var("PATH").unwrap_or_default()
            ),
        )
        .env(
            "GUM_CHOOSE_SEQUENCE_FILE",
            choose_sequence.display().to_string(),
        )
        .envs(configure_git_env(&home));

    let scripted_input = b"y\n~/.config/custom\nn\n";
    spawn_in_pty_with_input(cmd, scripted_input)?;

    let config_path = home.join(".config/omarchy-syncd/config.toml");
    let raw = fs::read_to_string(&config_path)?;
    let config: SyncConfig = toml::from_str(&raw)?;

    assert_eq!(
        config.files.bundles,
        vec!["core_desktop"],
        "interactive install should persist selected bundle"
    );
    assert!(
        config.files.paths.contains(&"~/.config/custom".to_string()),
        "interactive install should record custom path entries"
    );
    assert!(
        !config.files.paths.contains(&"~/.config/hypr".to_string()),
        "bundle-backed paths should not be duplicated in explicit list"
    );

    Ok(())
}

#[test]
fn backup_cancelled_via_gum_stub_aborts_command() -> Result<()> {
    let temp = tempdir()?;
    let home = temp.path().join("home");
    fs::create_dir_all(&home)?;

    let remote = init_remote_repo(temp.path(), "tty-backup-cancel.git")?;
    let hypr_conf = home.join(".config/hypr/hyprland.conf");
    fs::create_dir_all(hypr_conf.parent().unwrap())?;
    fs::write(&hypr_conf, "monitor = eDP-1\n")?;
    run_config(&home, &remote)?;

    let sequence = write_sequence_file(temp.path(), "gum-backup-cancel.txt", &["__CANCEL__"])?;
    let gum_dir = temp.path().join("gum-bin-cancel");
    create_gum_stub(&gum_dir)?;

    let mut cmd = StdCommand::new(cargo_bin("omarchy-syncd"));
    cmd.arg("backup")
        .env(
            "PATH",
            format!(
                "{}:{}",
                gum_dir.display(),
                std::env::var("PATH").unwrap_or_default()
            ),
        )
        .env("GUM_CHOOSE_SEQUENCE_FILE", sequence.display().to_string())
        .envs(configure_git_env(&home));

    match run_in_pty(cmd, None)? {
        WaitStatus::Exited(_, code) if code != 0 => Ok(()),
        status => {
            anyhow::bail!("expected backup cancellation to exit non-zero, got status {status:?}")
        }
    }
}
