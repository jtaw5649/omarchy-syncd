use assert_cmd::Command;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use tempfile::tempdir;

fn copy_dir_all(src: &Path, dst: &Path) -> io::Result<()> {
    fs::create_dir_all(dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let file_type = entry.file_type()?;
        let dest_path = dst.join(entry.file_name());
        if file_type.is_dir() {
            copy_dir_all(&entry.path(), &dest_path)?;
        } else {
            fs::copy(entry.path(), dest_path)?;
        }
    }
    Ok(())
}

#[test]
fn install_prefers_prebuilt_binary_when_available() -> Result<(), Box<dyn std::error::Error>> {
    let project_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let workspace = tempdir()?;
    let release_root = workspace.path().join("release");
    fs::create_dir_all(&release_root)?;

    fs::copy(
        project_root.join("install.sh"),
        release_root.join("install.sh"),
    )?;
    copy_dir_all(&project_root.join("scripts"), &release_root.join("scripts"))?;
    copy_dir_all(&project_root.join("install"), &release_root.join("install"))?;
    if project_root.join("bin").exists() {
        copy_dir_all(&project_root.join("bin"), &release_root.join("bin"))?;
    }
    if project_root.join("logo.txt").exists() {
        fs::copy(project_root.join("logo.txt"), release_root.join("logo.txt"))?;
    }
    if project_root.join("icon.png").exists() {
        fs::copy(project_root.join("icon.png"), release_root.join("icon.png"))?;
    }
    if project_root.join("version").exists() {
        fs::copy(project_root.join("version"), release_root.join("version"))?;
    }

    let packaged_bin = release_root.join("omarchy-syncd");
    let debug_bin = assert_cmd::cargo::cargo_bin("omarchy-syncd");
    fs::copy(debug_bin, &packaged_bin)?;

    let home_dir = tempdir()?;
    let target_dir = home_dir.path().join("bin");
    fs::create_dir_all(&target_dir)?;
    let xdg_data_home = home_dir.path().join("share");

    let mut cmd = Command::new(release_root.join("install.sh"));
    cmd.current_dir(&release_root)
        .env("OMARCHY_SYNCD_BOOTSTRAPPED", "1")
        .env("OMARCHY_SYNCD_FORCE_PLATFORM", "arch")
        .env("OMARCHY_SYNCD_FORCE_NO_GUM", "1")
        .env("OMARCHY_SYNCD_SKIP_PLATFORM_CHECK", "1")
        .env("HOME", home_dir.path())
        .env("XDG_DATA_HOME", &xdg_data_home)
        .env("OMARCHY_SYNCD_USE_SOURCE", "0")
        .arg(&target_dir);
    cmd.assert().success();

    let installed_bin = target_dir.join("omarchy-syncd");
    assert!(
        installed_bin.exists(),
        "omarchy-syncd should be installed when a prebuilt binary is available"
    );

    let installed_contents = fs::read(installed_bin)?;
    let packaged_contents = fs::read(packaged_bin)?;
    assert_eq!(
        installed_contents, packaged_contents,
        "installed binary should match the packaged prebuilt binary"
    );

    let state_dir = home_dir.path().join(".local/share/omarchy-syncd");
    assert!(
        state_dir.join("install.log").exists(),
        "install log should be created"
    );
    assert!(
        state_dir.join("logo.txt").exists(),
        "logo.txt should be copied to state dir"
    );

    let icon_path = xdg_data_home.join("icons/omarchy-syncd.png");
    assert!(icon_path.exists(), "icon should be installed");

    let update_helper = target_dir.join("omarchy-syncd-update");
    assert!(update_helper.exists(), "update helper should be deployed");

    Ok(())
}

#[test]
fn install_fails_on_non_arch_platform() -> Result<(), Box<dyn std::error::Error>> {
    let project_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let workspace = tempdir()?;
    let release_root = workspace.path().join("release");
    fs::create_dir_all(&release_root)?;

    fs::copy(
        project_root.join("install.sh"),
        release_root.join("install.sh"),
    )?;
    copy_dir_all(&project_root.join("install"), &release_root.join("install"))?;
    if project_root.join("logo.txt").exists() {
        fs::copy(project_root.join("logo.txt"), release_root.join("logo.txt"))?;
    }
    if project_root.join("version").exists() {
        fs::copy(project_root.join("version"), release_root.join("version"))?;
    }

    let home_dir = tempdir()?;
    let target_dir = home_dir.path().join("bin");
    fs::create_dir_all(&target_dir)?;
    let xdg_data_home = home_dir.path().join("share");

    let mut cmd = Command::new(release_root.join("install.sh"));
    cmd.current_dir(&release_root)
        .env("OMARCHY_SYNCD_BOOTSTRAPPED", "1")
        .env("OMARCHY_SYNCD_FORCE_PLATFORM", "unsupported")
        .env("OMARCHY_SYNCD_FORCE_NO_GUM", "1")
        .env("HOME", home_dir.path())
        .env("XDG_DATA_HOME", &xdg_data_home)
        .arg(&target_dir);

    let output = cmd.output()?;
    if output.status.success() {
        return Err(format!(
            "installer succeeded despite forcing unsupported platform; stdout: {} stderr: {}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        )
        .into());
    }

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("supports only Arch Linux"),
        "expected Arch-only warning in stderr, got: {}",
        stderr
    );

    Ok(())
}
