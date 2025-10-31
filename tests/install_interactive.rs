use anyhow::{Context, Result, anyhow};
use assert_cmd::cargo::cargo_bin;
use nix::poll::{PollFd, PollFlags, poll};
use ptyprocess::{PtyProcess, WaitStatus, stream::Stream};
use std::fs;
use std::io::{self, ErrorKind, Read, Write};
use std::os::fd::BorrowedFd;
use std::os::unix::{fs::PermissionsExt, io::AsRawFd};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{Duration, Instant};
use tempfile::{TempDir, tempdir};

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
fn install_interactive_skip_defaults_generates_example_config() -> Result<()> {
    let fixture = ReleaseFixture::prepare()?;
    let run = run_install(&fixture, SKIP_DEFAULTS_ACTIONS, None, true)?;

    let summary = run.summary();
    assert!(
        summary.contains("Example config created at"),
        "expected example-note in summary:\n{summary}"
    );
    assert!(
        summary.contains("Configuration is at"),
        "expected configuration path in summary:\n{summary}"
    );

    let config_body =
        fs::read_to_string(run.config_path()).context("reading generated config.toml")?;
    assert!(
        config_body.contains("# Example: add additional paths later"),
        "config should include example comment, got:\n{config_body}"
    );

    assert!(
        run.state_dir().join("install.log").exists(),
        "install log should exist in state dir"
    );

    Ok(())
}

#[test]
fn install_interactive_include_defaults_tracks_default_bundles() -> Result<()> {
    let fixture = ReleaseFixture::prepare()?;
    let run = run_install(&fixture, INCLUDE_DEFAULTS_ACTIONS, None, true)?;

    let summary = run.summary();
    assert!(
        !summary.contains("Example config created at"),
        "include-defaults run should not mention example config:\n{summary}"
    );

    let config_body =
        fs::read_to_string(run.config_path()).context("reading generated config.toml")?;
    for bundle in ["core_desktop", "terminals", "cli_tools"] {
        assert!(
            config_body.contains(bundle),
            "expected default bundle '{bundle}' present in config:\n{config_body}"
        );
    }

    Ok(())
}

#[test]
fn install_interactive_manual_selection_tracks_custom_choices() -> Result<()> {
    let fixture = ReleaseFixture::prepare()?;
    let run = run_install(&fixture, MANUAL_SELECTION_ACTIONS, None, true)?;

    let summary = run.summary();
    assert!(
        !summary.contains("Example config created at"),
        "manual selection should not report example config:\n{summary}"
    );

    let config_body =
        fs::read_to_string(run.config_path()).context("reading generated config.toml")?;
    for bundle in ["core_desktop", "cli_tools"] {
        assert!(
            config_body.contains(bundle),
            "manual selection should include bundle '{bundle}', got:\n{config_body}"
        );
    }
    assert!(
        config_body.contains("~/.config/manual"),
        "manual selection should carry custom path, got:\n{config_body}"
    );

    Ok(())
}

#[test]
fn install_interactive_update_existing_creates_backup_note() -> Result<()> {
    let fixture = ReleaseFixture::prepare()?;
    let initial = run_install(&fixture, SKIP_DEFAULTS_ACTIONS, None, true)?;

    let rerun = run_install(
        &fixture,
        UPDATE_EXISTING_ACTIONS,
        Some(initial.home_path()),
        true,
    )?;

    let summary = rerun.summary();
    assert!(
        summary.contains("Updated existing config"),
        "expected updated-config note in summary:\n{summary}"
    );
    assert!(
        summary.contains("Previous config backed up"),
        "expected backup note in summary:\n{summary}"
    );

    let config_body =
        fs::read_to_string(rerun.config_path()).context("reading updated config.toml")?;
    assert!(
        config_body.contains("tester/updated"),
        "updated config should reflect new repo, got:\n{config_body}"
    );

    let backup_exists = rerun
        .config_dir()
        .read_dir()?
        .filter_map(Result::ok)
        .any(|entry| entry.file_name().to_string_lossy().contains(".bak"));
    assert!(
        backup_exists,
        "expected backup config file alongside updated config"
    );

    Ok(())
}

struct ReleaseFixture {
    _root: TempDir,
    path: PathBuf,
}

impl ReleaseFixture {
    fn prepare() -> Result<Self> {
        let project_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let staging = tempdir()?;
        let release_root = staging.path().join("release");
        fs::create_dir_all(&release_root)?;

        let install_src = project_root.join("install.sh");
        let install_dest = release_root.join("install.sh");
        fs::copy(&install_src, &install_dest)?;
        fs::set_permissions(&install_dest, fs::Permissions::from_mode(0o755))?;

        copy_dir_all(&project_root.join("install"), &release_root.join("install"))?;
        copy_dir_all(&project_root.join("scripts"), &release_root.join("scripts"))?;
        if project_root.join("bin").exists() {
            copy_dir_all(&project_root.join("bin"), &release_root.join("bin"))?;
        } else {
            fs::create_dir_all(release_root.join("bin"))?;
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
        let debug_bin = cargo_bin("omarchy-syncd");
        fs::copy(debug_bin, &packaged_bin)?;

        let show_done_path = release_root.join("bin/omarchy-syncd-show-done");
        let done_capture_script = r#"#!/usr/bin/env bash
set -euo pipefail
state_dir="${OMARCHY_SYNCD_STATE_DIR:-${HOME}/.local/share/omarchy-syncd}"
summary_file="${state_dir}/done-message.txt"
mkdir -p "${state_dir}"
if [[ -n "${OMARCHY_SYNCD_DONE_MESSAGE:-}" ]]; then
  printf '%s\n' "${OMARCHY_SYNCD_DONE_MESSAGE}" >"${summary_file}"
fi
if [[ -f "${summary_file}" ]]; then
  cat "${summary_file}"
fi
"#;

        fs::write(&show_done_path, done_capture_script)?;
        fs::set_permissions(&show_done_path, fs::Permissions::from_mode(0o755))?;

        Ok(Self {
            _root: staging,
            path: release_root,
        })
    }

    fn path(&self) -> &Path {
        &self.path
    }
}

#[derive(Clone, Copy)]
struct PromptAction {
    expect: &'static str,
    reply: Option<&'static str>,
    optional: bool,
}

impl PromptAction {
    const fn reply(expect: &'static str, reply: &'static str) -> Self {
        Self {
            expect,
            reply: Some(reply),
            optional: false,
        }
    }

    const fn optional_reply(expect: &'static str, reply: &'static str) -> Self {
        Self {
            expect,
            reply: Some(reply),
            optional: true,
        }
    }

    const fn optional_ack(expect: &'static str) -> Self {
        Self {
            expect,
            reply: None,
            optional: true,
        }
    }
}

const SKIP_DEFAULTS_ACTIONS: &[PromptAction] = &[
    PromptAction::reply("Ready to install omarchy-syncd? [Y/n]", "y"),
    PromptAction::reply("Create config now? [y/N]", "y"),
    PromptAction::optional_reply("Create a new private GitHub repository via gh? [y/N]", "n"),
    PromptAction::reply("Use HTTPS or SSH for GitHub access? [https/ssh]:", "https"),
    PromptAction::reply(
        "Enter the GitHub repo (owner/name) for HTTPS:",
        "tester/example",
    ),
    PromptAction::reply("Branch name to track [master]:", ""),
    PromptAction::reply("Include defaults? [Y/n/m]:", "n"),
];

const INCLUDE_DEFAULTS_ACTIONS: &[PromptAction] = &[
    PromptAction::reply("Ready to install omarchy-syncd? [Y/n]", "y"),
    PromptAction::reply("Create config now? [y/N]", "y"),
    PromptAction::optional_reply("Create a new private GitHub repository via gh? [y/N]", "n"),
    PromptAction::reply("Use HTTPS or SSH for GitHub access? [https/ssh]:", "https"),
    PromptAction::reply(
        "Enter the GitHub repo (owner/name) for HTTPS:",
        "tester/include-defaults",
    ),
    PromptAction::reply("Branch name to track [master]:", ""),
    PromptAction::reply("Include defaults? [Y/n/m]:", ""),
    PromptAction::reply("Additional paths (comma-separated, optional):", ""),
];

const MANUAL_SELECTION_ACTIONS: &[PromptAction] = &[
    PromptAction::reply("Ready to install omarchy-syncd? [Y/n]", "y"),
    PromptAction::reply("Create config now? [y/N]", "y"),
    PromptAction::optional_reply("Create a new private GitHub repository via gh? [y/N]", "n"),
    PromptAction::reply("Use HTTPS or SSH for GitHub access? [https/ssh]:", "https"),
    PromptAction::reply(
        "Enter the GitHub repo (owner/name) for HTTPS:",
        "tester/manual",
    ),
    PromptAction::reply("Branch name to track [master]:", ""),
    PromptAction::reply("Include defaults? [Y/n/m]:", "m"),
    PromptAction::reply("Enter bundle numbers separated by spaces", "1 3"),
    PromptAction::reply(
        "Additional paths (comma-separated, optional):",
        "~/.config/manual",
    ),
];

const UPDATE_EXISTING_ACTIONS: &[PromptAction] = &[
    PromptAction::reply("Ready to install omarchy-syncd? [Y/n]", "y"),
    PromptAction::optional_ack("Existing omarchy-syncd config found at"),
    PromptAction::reply("Update existing config now? [y/N]", "y"),
    PromptAction::reply("Create config now? [y/N]", "y"),
    PromptAction::optional_reply("Create a new private GitHub repository via gh? [y/N]", "n"),
    PromptAction::reply("Use HTTPS or SSH for GitHub access? [https/ssh]:", "https"),
    PromptAction::reply(
        "Enter the GitHub repo (owner/name) for HTTPS:",
        "tester/updated",
    ),
    PromptAction::reply("Branch name to track [master]:", "main"),
    PromptAction::reply("Include defaults? [Y/n/m]:", "n"),
];

fn run_install(
    fixture: &ReleaseFixture,
    actions: &[PromptAction],
    home_override: Option<&Path>,
    configure_git: bool,
) -> Result<InstallRun> {
    let home_handle = if let Some(path) = home_override {
        HomeHandle::Borrowed(path.to_path_buf())
    } else {
        HomeHandle::Owned(tempdir()?)
    };

    if configure_git {
        init_git_config(home_handle.path())?;
    }

    let xdg_config = home_handle.path().join(".config");
    let xdg_data = home_handle.path().join(".local/share");
    let mut cmd = Command::new("./install.sh");
    cmd.current_dir(fixture.path())
        .env("HOME", home_handle.path())
        .env("XDG_CONFIG_HOME", &xdg_config)
        .env("XDG_DATA_HOME", &xdg_data)
        .env("OMARCHY_SYNCD_FORCE_NO_GUM", "1")
        .env("OMARCHY_SYNCD_BOOTSTRAPPED", "1")
        .env("OMARCHY_SYNCD_FORCE_PLATFORM", "arch")
        .env("OMARCHY_SYNCD_SKIP_PLATFORM_CHECK", "1")
        .env("OMARCHY_SYNCD_USE_SOURCE", "0")
        .env(
            "PATH",
            format!(
                "{}:{}",
                fixture.path().join("bin").display(),
                std::env::var("PATH").unwrap_or_default()
            ),
        );

    let process = PtyProcess::spawn(cmd)?;
    let stream = process
        .get_pty_stream()
        .context("creating PTY stream for installer")?;
    let mut driver = PromptDriver::new(stream);

    for action in actions {
        match driver.expect(action.expect) {
            Ok(()) => {
                if let Some(reply) = action.reply {
                    driver.send_line(reply)?;
                }
            }
            Err(err) => {
                if action.optional {
                    continue;
                }
                return Err(err);
            }
        }
    }

    drop(driver);
    let wait_status = process.wait()?;
    if !matches!(wait_status, WaitStatus::Exited(_, 0)) {
        let log_path = home_handle
            .path()
            .join(".local/share/omarchy-syncd/install.log");
        let log_snippet = read_log_tail(&log_path);
        return Err(anyhow!(
            "installer exited abnormally: {wait_status:?}\n--- install.log ---\n{log_snippet}"
        ));
    }

    let summary_path = home_handle
        .path()
        .join(".local/share/omarchy-syncd/done-message.txt");
    let summary = fs::read_to_string(&summary_path)
        .with_context(|| format!("reading install summary at {:?}", summary_path))?;

    Ok(InstallRun {
        home: home_handle,
        summary,
    })
}

fn init_git_config(home: &Path) -> Result<()> {
    let git_config_dir = home.join(".config/git");
    fs::create_dir_all(&git_config_dir)
        .with_context(|| format!("creating git config dir at {:?}", git_config_dir))?;
    let config_body = "[user]\n\tname = Omarchy Tester\n\temail = tester@example.com\n";
    fs::write(git_config_dir.join("config"), config_body).context("writing git config")?;
    Ok(())
}

enum HomeHandle {
    Owned(TempDir),
    Borrowed(PathBuf),
}

impl HomeHandle {
    fn path(&self) -> &Path {
        match self {
            HomeHandle::Owned(temp) => temp.path(),
            HomeHandle::Borrowed(path) => path.as_path(),
        }
    }
}

struct InstallRun {
    home: HomeHandle,
    summary: String,
}

impl InstallRun {
    fn home_path(&self) -> &Path {
        self.home.path()
    }

    fn config_dir(&self) -> PathBuf {
        self.home.path().join(".config/omarchy-syncd")
    }

    fn config_path(&self) -> PathBuf {
        self.config_dir().join("config.toml")
    }

    fn state_dir(&self) -> PathBuf {
        self.home.path().join(".local/share/omarchy-syncd")
    }

    fn summary(&self) -> &str {
        self.summary.trim_end()
    }
}

fn read_log_tail(path: &Path) -> String {
    const MAX_BYTES: usize = 4000;
    match fs::read_to_string(path) {
        Ok(contents) => {
            if contents.len() > MAX_BYTES {
                let start = contents.len() - MAX_BYTES;
                contents[start..].to_string()
            } else {
                contents
            }
        }
        Err(_) => String::from("<install log unavailable>"),
    }
}

struct PromptDriver {
    stream: Stream,
    buffer: String,
}

impl PromptDriver {
    const PROMPT_TIMEOUT: Duration = Duration::from_secs(20);
    const POLL_INTERVAL: Duration = Duration::from_millis(250);

    fn new(stream: Stream) -> Self {
        Self {
            stream,
            buffer: String::new(),
        }
    }

    fn expect(&mut self, needle: &str) -> Result<()> {
        const READ_CHUNK: usize = 1024;
        let fd = self.stream.as_raw_fd();
        let deadline = Instant::now() + Self::PROMPT_TIMEOUT;
        loop {
            if let Some(pos) = self.buffer.find(needle) {
                let end = pos + needle.len();
                self.buffer.drain(..end);
                return Ok(());
            }

            if Instant::now() >= deadline {
                return Err(anyhow!(
                    "timed out waiting for prompt '{needle}'. trailing buffer:\n{}",
                    self.buffer
                ));
            }

            let timeout_ms = Self::POLL_INTERVAL.as_millis() as i32;
            let fd_ref = unsafe { BorrowedFd::borrow_raw(fd) };
            let mut poll_fds = [PollFd::new(&fd_ref, PollFlags::POLLIN)];
            let poll_res = poll(&mut poll_fds, timeout_ms)?;
            if poll_res == 0 {
                continue;
            }

            let mut buf = [0u8; READ_CHUNK];
            match self.stream.read(&mut buf) {
                Ok(0) => {
                    return Err(anyhow!(
                        "process ended before seeing prompt '{needle}'. trailing buffer:\n{}",
                        self.buffer
                    ));
                }
                Ok(read) => {
                    self.buffer.push_str(&String::from_utf8_lossy(&buf[..read]));
                }
                Err(err) if err.kind() == ErrorKind::WouldBlock => {
                    continue;
                }
                Err(err) => return Err(err.into()),
            }
        }
    }

    fn send_line(&mut self, line: &str) -> Result<()> {
        self.stream.write_all(line.as_bytes())?;
        self.stream.write_all(b"\n")?;
        self.stream.flush()?;
        Ok(())
    }
}
