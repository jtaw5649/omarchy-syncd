use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command as StdCommand;

use anyhow::{Context, Result};
use assert_cmd::Command;
use serde::Deserialize;
use serde_json;
use tempfile::tempdir;
use walkdir::WalkDir;

#[cfg(unix)]
use std::os::unix::fs::symlink;

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
    run_git(Some(seed_dir.path()), &["branch", "-M", "main"])?;
    run_git(
        Some(seed_dir.path()),
        &["remote", "add", "origin", path_str(&remote)?],
    )?;
    run_git(Some(seed_dir.path()), &["push", "-u", "origin", "main"])?;
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

fn init_empty_remote(base: &Path, name: &str) -> Result<PathBuf> {
    let remote = base.join(name);
    run_git(Some(base), &["init", "--bare", path_str(&remote)?])?;
    StdCommand::new("git")
        .args(&[
            "--git-dir",
            path_str(&remote)?,
            "symbolic-ref",
            "HEAD",
            "refs/heads/main",
        ])
        .status()
        .context("Failed to configure empty bare repository")?;
    Ok(remote)
}

fn base_command(home: &Path) -> Command {
    let mut cmd = Command::cargo_bin("omarchy-syncd").unwrap();
    let config_home = home.join(".config");
    let data_home = home.join(".local/share");
    cmd.env("HOME", home)
        .env("XDG_CONFIG_HOME", &config_home)
        .env("XDG_DATA_HOME", &data_home)
        .env("GIT_AUTHOR_NAME", "Omarchy Syncd Test")
        .env("GIT_AUTHOR_EMAIL", "test@example.com")
        .env("GIT_COMMITTER_NAME", "Omarchy Syncd Test")
        .env("GIT_COMMITTER_EMAIL", "test@example.com");
    cmd
}

fn find_config_file(home: &Path) -> Result<PathBuf> {
    let config_home = home.join(".config");
    let candidate = config_home.join("omarchy-syncd/config.toml");
    if candidate.exists() {
        return Ok(candidate);
    }

    for entry in WalkDir::new(&config_home)
        .into_iter()
        .filter_map(Result::ok)
    {
        if entry.file_name() == "config.toml" {
            return Ok(entry.into_path());
        }
    }

    anyhow::bail!(
        "config.toml not found under {} after init",
        config_home.display()
    );
}

#[test]
fn init_with_defaults_and_extra_path_writes_config() -> Result<()> {
    let temp = tempdir()?;
    let home = temp.path().join("home");
    fs::create_dir_all(&home)?;

    let remote = init_remote_repo(temp.path(), "remote-init.git")?;

    base_command(&home)
        .args([
            "init",
            "--repo-url",
            path_str(&remote)?,
            "--include-defaults",
            "--path",
            "~/.config/custom-app",
        ])
        .assert()
        .success();

    let config_path = find_config_file(&home)?;
    let raw = fs::read_to_string(&config_path)?;
    let cfg: omarchy_syncd::config::SyncConfig = toml::from_str(&raw)?;

    assert_eq!(cfg.repo.url, path_str(&remote)?);
    assert_eq!(cfg.repo.branch, "main");

    let unique: HashSet<_> = cfg.files.paths.iter().collect();
    assert_eq!(
        unique.len(),
        cfg.files.paths.len(),
        "paths should be deduplicated"
    );
    assert!(
        cfg.files
            .paths
            .contains(&"~/.config/custom-app".to_string())
    );

    let mut expected_bundles: Vec<String> = omarchy_syncd::bundles::DEFAULT_BUNDLE_IDS
        .iter()
        .map(|id| id.to_string())
        .collect();
    expected_bundles.sort();
    assert_eq!(cfg.files.bundles, expected_bundles, "default bundle set");

    let resolved = cfg.resolved_paths()?;
    let resolved_set: HashSet<_> = resolved.into_iter().collect();
    for bundle_id in omarchy_syncd::bundles::DEFAULT_BUNDLE_IDS {
        let bundle = omarchy_syncd::bundles::find(bundle_id).expect("bundle should exist");
        for path in bundle.paths {
            assert!(
                resolved_set.contains(&path.to_string()),
                "missing {path} from resolved defaults"
            );
        }
    }

    Ok(())
}

#[test]
fn backup_and_restore_roundtrip() -> Result<()> {
    let temp = tempdir()?;
    let home = temp.path().join("home");
    fs::create_dir_all(&home)?;

    let remote = init_remote_repo(temp.path(), "remote-backup.git")?;

    let omarchy_dir = home.join(".config/omarchy");
    let theme_dir = omarchy_dir.join("themes/test-theme");
    fs::create_dir_all(&theme_dir)?;
    fs::write(theme_dir.join("ghostty.conf"), "# theme\n")?;
    fs::write(theme_dir.join("hyprland.conf"), "# hypr\n")?;
    let theme_git = theme_dir.join(".git");
    fs::create_dir_all(&theme_git)?;
    fs::write(theme_git.join("HEAD"), "ref: refs/heads/main\n")?;
    let backgrounds_dir = theme_dir.join("backgrounds");
    fs::create_dir_all(&backgrounds_dir)?;
    fs::write(backgrounds_dir.join("1.png"), "fakeimage")?;
    let current_dir = omarchy_dir.join("current");
    fs::create_dir_all(&current_dir)?;
    #[cfg(unix)]
    symlink(Path::new("../themes/test-theme"), current_dir.join("theme"))?;
    #[cfg(unix)]
    symlink(
        Path::new("../themes/test-theme/backgrounds/1.png"),
        current_dir.join("background"),
    )?;

    let hypr_conf = home.join(".config/hypr/hyprland.conf");
    fs::create_dir_all(hypr_conf.parent().unwrap())?;
    fs::write(&hypr_conf, "monitor = HDMI-A-1\n")?;

    let nvim_conf = home.join(".config/nvim/init.lua");
    fs::create_dir_all(nvim_conf.parent().unwrap())?;
    fs::write(&nvim_conf, "print('hello omarchy')\n")?;

    base_command(&home)
        .args([
            "init",
            "--repo-url",
            path_str(&remote)?,
            "--include-defaults",
        ])
        .assert()
        .success();

    base_command(&home).arg("backup").assert().success();

    let checkout = temp.path().join("checkout");
    run_git(
        Some(temp.path()),
        &["clone", path_str(&remote)?, path_str(&checkout)?],
    )?;

    #[derive(Deserialize)]
    struct RecordedSymlink {
        path: String,
        target: String,
        is_dir: bool,
    }
    let symlink_metadata_path = checkout.join(".config/omarchy-syncd/symlinks.json");
    assert!(symlink_metadata_path.exists());
    let metadata_contents = fs::read_to_string(&symlink_metadata_path)?;
    let recorded: Vec<RecordedSymlink> = serde_json::from_str(&metadata_contents)?;
    assert!(recorded.iter().any(|entry| {
        entry.path == ".config/omarchy/current/theme"
            && entry.target == "../themes/test-theme"
            && entry.is_dir
    }));

    let cloned_theme_file = checkout.join(".config/omarchy/themes/test-theme/hyprland.conf");
    assert!(
        cloned_theme_file.exists(),
        "theme files should be committed"
    );

    let cloned_hypr = checkout.join(".config/hypr/hyprland.conf");
    assert!(cloned_hypr.exists(), "hypr config should be committed");
    assert_eq!(fs::read_to_string(&cloned_hypr)?, "monitor = HDMI-A-1\n");

    let cloned_nvim = checkout.join(".config/nvim/init.lua");
    assert!(cloned_nvim.exists(), "nvim config should be committed");

    fs::remove_dir_all(hypr_conf.parent().unwrap())?;
    fs::remove_dir_all(nvim_conf.parent().unwrap())?;
    fs::remove_dir_all(&omarchy_dir)?;

    base_command(&home).arg("restore").assert().success();

    let restored_hypr = home.join(".config/hypr/hyprland.conf");
    assert!(
        restored_hypr.exists(),
        "restore should recreate hypr config"
    );
    assert_eq!(fs::read_to_string(restored_hypr)?, "monitor = HDMI-A-1\n");

    let restored_nvim = home.join(".config/nvim/init.lua");
    assert!(
        restored_nvim.exists(),
        "restore should recreate nvim config"
    );
    assert_eq!(
        fs::read_to_string(restored_nvim)?,
        "print('hello omarchy')\n"
    );

    let restored_theme_file = home.join(".config/omarchy/themes/test-theme/hyprland.conf");
    assert!(
        restored_theme_file.exists(),
        "restore should recreate theme files"
    );

    #[cfg(unix)]
    {
        let current_symlink = home.join(".config/omarchy/current/theme");
        assert!(current_symlink.symlink_metadata()?.file_type().is_symlink());
        let target = fs::read_link(&current_symlink)?;
        let resolved = if target.is_absolute() {
            target
        } else {
            current_symlink.parent().unwrap().join(&target)
        };
        let resolved_canonical = resolved.canonicalize()?;
        let expected = home
            .join(".config/omarchy/themes/test-theme")
            .canonicalize()?;
        assert_eq!(resolved_canonical, expected);

        let background_link = home.join(".config/omarchy/current/background");
        assert!(background_link.symlink_metadata()?.file_type().is_symlink());
    }

    Ok(())
}

#[test]
fn init_accepts_bundle_flags() -> Result<()> {
    let temp = tempdir()?;
    let home = temp.path().join("home");
    fs::create_dir_all(&home)?;

    let remote = init_remote_repo(temp.path(), "remote-bundle.git")?;

    base_command(&home)
        .args([
            "init",
            "--repo-url",
            path_str(&remote)?,
            "--bundle",
            "core_desktop",
        ])
        .assert()
        .success();

    let config_path = find_config_file(&home)?;
    let raw = fs::read_to_string(&config_path)?;
    let cfg: omarchy_syncd::config::SyncConfig = toml::from_str(&raw)?;

    assert_eq!(
        cfg.files.bundles,
        vec!["core_desktop".to_string()],
        "bundle flag should be persisted"
    );
    assert!(
        cfg.files.paths.is_empty(),
        "no explicit paths expected when only bundle flag is set"
    );

    let resolved = cfg.resolved_paths()?;
    let resolved_set: HashSet<_> = resolved.into_iter().collect();
    let bundle = omarchy_syncd::bundles::find("core_desktop").expect("core bundle exists");
    for path in bundle.paths {
        assert!(
            resolved_set.contains(&path.to_string()),
            "resolved bundle should include {path}"
        );
    }

    Ok(())
}

#[test]
fn install_command_updates_config_via_cli() -> Result<()> {
    let temp = tempdir()?;
    let home = temp.path().join("home");
    fs::create_dir_all(&home)?;

    let remote = init_remote_repo(temp.path(), "remote-install.git")?;

    base_command(&home)
        .args([
            "init",
            "--repo-url",
            path_str(&remote)?,
            "--bundle",
            "core_desktop",
        ])
        .assert()
        .success();

    base_command(&home)
        .args([
            "install",
            "--bundle",
            "terminals",
            "--bundle",
            "dev_git",
            "--path",
            "~/.config/custom-app",
            "--no-ui",
        ])
        .assert()
        .success();

    let config_path = find_config_file(&home)?;
    let raw = fs::read_to_string(&config_path)?;
    let cfg: omarchy_syncd::config::SyncConfig = toml::from_str(&raw)?;

    assert_eq!(
        cfg.files.paths,
        vec!["~/.config/custom-app".to_string()],
        "install should persist explicit path selections"
    );

    let mut expected_bundles = vec!["dev_git".to_string(), "terminals".to_string()];
    expected_bundles.sort();
    assert_eq!(
        cfg.files.bundles, expected_bundles,
        "install should replace bundle selection"
    );

    let resolved = cfg.resolved_paths()?;
    let resolved_set: HashSet<_> = resolved.into_iter().collect();
    for path in omarchy_syncd::bundles::find("terminals").unwrap().paths {
        assert!(resolved_set.contains(&path.to_string()));
    }
    for path in omarchy_syncd::bundles::find("dev_git").unwrap().paths {
        assert!(resolved_set.contains(&path.to_string()));
    }
    assert!(resolved_set.contains(&"~/.config/custom-app".to_string()));

    Ok(())
}

#[test]
fn backup_initializes_empty_remote() -> Result<()> {
    let temp = tempdir()?;
    let home = temp.path().join("home");
    fs::create_dir_all(&home)?;

    let remote = init_empty_remote(temp.path(), "remote-empty.git")?;

    let hypr_conf = home.join(".config/hypr/hyprland.conf");
    fs::create_dir_all(hypr_conf.parent().unwrap())?;
    fs::write(&hypr_conf, "monitor = DP-1\n")?;

    base_command(&home)
        .args([
            "init",
            "--repo-url",
            path_str(&remote)?,
            "--path",
            "~/.config/hypr",
        ])
        .assert()
        .success();

    base_command(&home).arg("backup").assert().success();

    let checkout = temp.path().join("checkout-empty");
    run_git(
        Some(temp.path()),
        &["clone", path_str(&remote)?, path_str(&checkout)?],
    )?;

    let cloned_hypr = checkout.join(".config/hypr/hyprland.conf");
    assert!(
        cloned_hypr.exists(),
        "hypr config should exist in repository after first backup"
    );

    Ok(())
}
