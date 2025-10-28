use std::fs;
use std::path::Path;
use std::process::Command;

use anyhow::{Context, Result};

pub fn clone_repo(url: &str, branch: &str, repo_dir: &Path) -> Result<()> {
    if repo_dir.exists() {
        fs::remove_dir_all(repo_dir)
            .with_context(|| format!("Failed cleaning repo directory {}", repo_dir.display()))?;
    }

    let clone_with_branch = Command::new("git")
        .args(["clone", "--branch", branch, "--single-branch", url])
        .arg(repo_dir)
        .status()
        .context("Failed to execute git clone")?;

    if clone_with_branch.success() {
        return Ok(());
    }

    if repo_dir.exists() {
        fs::remove_dir_all(repo_dir)
            .with_context(|| format!("Failed cleaning repo directory {}", repo_dir.display()))?;
    }

    let fallback_clone = Command::new("git")
        .args(["clone", url])
        .arg(repo_dir)
        .status()
        .context("Failed to execute fallback git clone")?;

    if !fallback_clone.success() {
        anyhow::bail!("git clone exited with status {}", fallback_clone);
    }

    if run_git(repo_dir, &["checkout", branch]).is_err() {
        run_git(repo_dir, &["checkout", "-b", branch])?;
    }

    Ok(())
}

pub fn commit_and_push(repo_dir: &Path, message: &str, branch: &str) -> Result<()> {
    run_git(repo_dir, &["add", "--all", "."])?;
    clean_gitlinks(repo_dir)?;

    let commit_status = Command::new("git")
        .current_dir(repo_dir)
        .args(["commit", "-m", message])
        .status()
        .context("Failed to execute git commit")?;

    if !commit_status.success() {
        if commit_status.code() == Some(1) {
            println!("No changes to commit.");
            return Ok(());
        } else {
            anyhow::bail!("git commit failed with status {:?}", commit_status.code());
        }
    }

    run_git(repo_dir, &["push", "origin", branch])?;

    Ok(())
}

pub fn verify_remote(url: &str, branch: &str) -> Result<()> {
    let status = Command::new("git")
        .args(["ls-remote", "--exit-code", url, branch])
        .status()
        .context("Failed to execute git ls-remote")?;

    if !status.success() {
        anyhow::bail!(
            "git ls-remote could not find branch '{}' on {}",
            branch,
            url
        );
    }

    Ok(())
}

fn clean_gitlinks(repo_dir: &Path) -> Result<()> {
    let output = Command::new("git")
        .current_dir(repo_dir)
        .args(["ls-files", "--stage"])
        .output()
        .context("Failed to list staged files")?;
    let listing =
        String::from_utf8(output.stdout).context("git ls-files produced invalid UTF-8 output")?;

    for line in listing.lines() {
        if let Some((prefix, path)) = line.split_once('\t') {
            if prefix.starts_with("160000 ") {
                run_git(repo_dir, &["rm", "--cached", path])?;
                run_git(repo_dir, &["add", "--force", "--all", path])?;
            }
        }
    }

    Ok(())
}

fn run_git(repo_dir: &Path, args: &[&str]) -> Result<()> {
    let status = Command::new("git")
        .current_dir(repo_dir)
        .args(args)
        .status()
        .with_context(|| format!("Failed running git {:?}", args))?;

    if !status.success() {
        anyhow::bail!(
            "git command {:?} exited with status {:?}",
            args,
            status.code()
        );
    }

    Ok(())
}
