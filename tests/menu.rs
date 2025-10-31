use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command as StdCommand, Output};

use anyhow::{Context, Result};
use assert_cmd::Command;
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

fn base_command(home: &Path) -> Command {
    let mut cmd = Command::cargo_bin("omarchy-syncd").expect("binary available");
    let config_home = home.join(".config");
    let data_home = home.join(".local/share");
    cmd.env("HOME", home)
        .env("XDG_CONFIG_HOME", &config_home)
        .env("XDG_DATA_HOME", &data_home)
        .env("GIT_AUTHOR_NAME", "Omarchy Menu Test")
        .env("GIT_AUTHOR_EMAIL", "menu@example.com")
        .env("GIT_COMMITTER_NAME", "Omarchy Menu Test")
        .env("GIT_COMMITTER_EMAIL", "menu@example.com");
    cmd
}

#[test]
fn menu_runs_update_script_when_forced_version_available() -> Result<()> {
    let temp = tempdir()?;
    let home = temp.path().join("home");
    fs::create_dir_all(&home)?;

    let bin_dir = temp.path().join("bin");
    fs::create_dir_all(&bin_dir)?;
    let marker = temp.path().join("update-invoked");
    let update_script = bin_dir.join("omarchy-syncd-update");
    fs::write(
        &update_script,
        format!(
            "#!/usr/bin/env bash\nset -euo pipefail\nprintf 'called' > {}\n",
            marker.display()
        ),
    )?;
    fs::set_permissions(&update_script, fs::Permissions::from_mode(0o755))?;

    let output = run_menu_command(
        &home,
        Some(&bin_dir),
        &[
            ("OMARCHY_SYNCD_FORCE_UPDATE_VERSION", "9.9.9"),
            ("OMARCHY_SYNCD_MENU_CHOICE", "update"),
        ],
    )?;
    assert!(output.status.success());

    assert!(
        marker.exists(),
        "update helper should be invoked when update is available"
    );
    Ok(())
}

fn configure_config(home: &Path, remote: &Path) -> Result<()> {
    fs::create_dir_all(home)?;
    let hypr_conf = home.join(".config/hypr/hyprland.conf");
    fs::create_dir_all(hypr_conf.parent().unwrap())?;
    fs::write(&hypr_conf, "monitor = DP-1\n")?;

    base_command(home)
        .arg("config")
        .args([
            "--write",
            "--repo-url",
            path_str(remote)?,
            "--bundle",
            "core_desktop",
        ])
        .assert()
        .success();

    Ok(())
}

fn run_menu_backup(home: &Path, envs: &[(&str, &str)], update_bin: &Path) -> Result<Output> {
    let mut merged_envs = envs.to_vec();
    merged_envs.push(("OMARCHY_SYNCD_MENU_CHOICE", "backup"));
    let output = run_menu_command(home, Some(update_bin), &merged_envs)?;
    if !output.status.success() {
        anyhow::bail!(
            "menu backup failed: status {:?}, stderr {}",
            output.status.code(),
            String::from_utf8_lossy(&output.stderr)
        );
    }
    Ok(output)
}

fn run_menu_command(
    home: &Path,
    update_bin: Option<&Path>,
    envs: &[(&str, &str)],
) -> Result<Output> {
    let mut cmd = base_command(home);
    cmd.arg("menu").env("OMARCHY_SYNCD_FORCE_NO_GUM", "1");
    if let Some(bin) = update_bin {
        cmd.env(
            "PATH",
            format!(
                "{}:{}",
                bin.display(),
                std::env::var("PATH").unwrap_or_default()
            ),
        );
    }
    for (key, value) in envs {
        cmd.env(key, value);
    }
    Ok(cmd.output()?)
}

fn clone_remote(remote: &Path, target: &Path) -> Result<()> {
    if target.exists() {
        fs::remove_dir_all(target).ok();
    }
    fs::create_dir_all(target.parent().unwrap())?;
    run_git(
        Some(target.parent().unwrap()),
        &[
            "clone",
            "--branch",
            "master",
            "--single-branch",
            path_str(remote)?,
            path_str(target)?,
        ],
    )?;
    Ok(())
}

#[test]
fn menu_skips_update_when_version_not_newer() -> Result<()> {
    let temp = tempdir()?;
    let home = temp.path().join("home");
    fs::create_dir_all(&home)?;

    let update_dir = temp.path().join("bin");
    fs::create_dir_all(&update_dir)?;
    let script_path = update_dir.join("omarchy-syncd-update");
    fs::write(
        &script_path,
        "#!/usr/bin/env bash\ntouch '$0.must_not_run'\n",
    )?;
    fs::set_permissions(&script_path, fs::Permissions::from_mode(0o755))?;

    let remote = init_remote_repo(temp.path(), "menu-no-update.git")?;
    configure_config(&home, &remote)?;

    let _ = run_menu_backup(
        &home,
        &[(
            "OMARCHY_SYNCD_FORCE_UPDATE_VERSION",
            env!("CARGO_PKG_VERSION"),
        )],
        &update_dir,
    )?;

    assert!(
        !update_dir
            .join("omarchy-syncd-update.must_not_run")
            .exists(),
        "update helper should not run when the forced version matches current"
    );

    let checkout = temp.path().join("clone-no-update");
    clone_remote(&remote, &checkout)?;
    assert!(
        checkout.join(".config/hypr/hyprland.conf").exists(),
        "backup should populate the remote"
    );

    Ok(())
}

#[test]
fn menu_handles_invalid_forced_version() -> Result<()> {
    let temp = tempdir()?;
    let home = temp.path().join("home");
    fs::create_dir_all(&home)?;

    let update_dir = temp.path().join("bin");
    fs::create_dir_all(&update_dir)?;
    let script_path = update_dir.join("omarchy-syncd-update");
    fs::write(
        &script_path,
        "#!/usr/bin/env bash\ntouch '$0.should_not_run'\n",
    )?;
    fs::set_permissions(&script_path, fs::Permissions::from_mode(0o755))?;

    let remote = init_remote_repo(temp.path(), "menu-invalid-update.git")?;
    configure_config(&home, &remote)?;

    let _ = run_menu_backup(
        &home,
        &[("OMARCHY_SYNCD_FORCE_UPDATE_VERSION", "not-a-version")],
        &update_dir,
    )?;

    assert!(
        !update_dir
            .join("omarchy-syncd-update.should_not_run")
            .exists(),
        "update helper must not run when forced version is invalid"
    );

    let checkout = temp.path().join("clone-invalid-update");
    clone_remote(&remote, &checkout)?;
    assert!(
        checkout.join(".config/hypr/hyprland.conf").exists(),
        "backup should still succeed even when update check fails"
    );

    Ok(())
}

#[test]
fn menu_respects_skip_update_check() -> Result<()> {
    let temp = tempdir()?;
    let home = temp.path().join("home");
    fs::create_dir_all(&home)?;

    let update_dir = temp.path().join("bin");
    fs::create_dir_all(&update_dir)?;
    let update_script = update_dir.join("omarchy-syncd-update");
    fs::write(
        &update_script,
        "#!/usr/bin/env bash\ntouch '$0.should_not_run'\n",
    )?;
    fs::set_permissions(&update_script, fs::Permissions::from_mode(0o755))?;

    let output = run_menu_command(
        &home,
        Some(&update_dir),
        &[
            ("OMARCHY_SYNCD_SKIP_UPDATE_CHECK", "1"),
            ("OMARCHY_SYNCD_FORCE_UPDATE_VERSION", "9.9.9"),
            ("OMARCHY_SYNCD_MENU_CHOICE", "update"),
        ],
    )?;
    assert!(
        output.status.success(),
        "menu should exit cleanly when update check skipped"
    );
    assert!(
        !update_dir
            .join("omarchy-syncd-update.should_not_run")
            .exists(),
        "update helper must not run when update checks are skipped"
    );

    Ok(())
}

#[test]
fn menu_reports_update_failure_but_returns_success() -> Result<()> {
    let temp = tempdir()?;
    let home = temp.path().join("home");
    fs::create_dir_all(&home)?;

    let update_dir = temp.path().join("bin");
    fs::create_dir_all(&update_dir)?;
    let marker = temp.path().join("update-called-before-fail");
    let update_script = update_dir.join("omarchy-syncd-update");
    fs::write(
        &update_script,
        format!(
            "#!/usr/bin/env bash\nset -euo pipefail\ntouch '{}'\nexit 1\n",
            marker.display()
        ),
    )?;
    fs::set_permissions(&update_script, fs::Permissions::from_mode(0o755))?;

    let output = run_menu_command(
        &home,
        Some(&update_dir),
        &[
            ("OMARCHY_SYNCD_FORCE_UPDATE_VERSION", "9.9.9"),
            ("OMARCHY_SYNCD_MENU_CHOICE", "update"),
        ],
    )?;

    assert!(
        output.status.success(),
        "menu should not propagate update failure"
    );
    assert!(
        marker.exists(),
        "update helper should have been invoked before failure"
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("omarchy-syncd-update failed"),
        "stderr should report update helper failure"
    );

    Ok(())
}

#[test]
fn menu_rejects_unknown_choice() -> Result<()> {
    let temp = tempdir()?;
    let home = temp.path().join("home");
    fs::create_dir_all(&home)?;

    let output = run_menu_command(&home, None, &[("OMARCHY_SYNCD_MENU_CHOICE", "bogus")])?;
    assert!(
        !output.status.success(),
        "menu should exit with failure for unknown choices"
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("Unknown selection"));
    Ok(())
}
