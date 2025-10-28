use std::{
    fs,
    path::{Path, PathBuf},
};

use anyhow::{Context, Result};
use fs_extra::dir::{self, CopyOptions};
use serde::{Deserialize, Serialize};
use serde_json;
use walkdir::WalkDir;

#[cfg(unix)]
use std::os::unix::fs::symlink;

const SYMLINK_METADATA_DIR: &str = ".omarchy-syncd";
const SYMLINK_METADATA_FILE: &str = "symlinks.json";

#[derive(Debug, Serialize, Deserialize)]
struct SymlinkEntry {
    path: String,
    target: String,
    is_dir: bool,
}

fn home_dir() -> Result<PathBuf> {
    let home = std::env::var("HOME").context("HOME environment variable not set")?;
    Ok(PathBuf::from(home))
}

fn expand_path(raw: &str) -> Result<PathBuf> {
    let expanded = shellexpand::tilde(raw);
    Ok(PathBuf::from(expanded.into_owned()))
}

fn relative_to_home(path: &Path) -> Result<PathBuf> {
    let home = home_dir()?;
    path.strip_prefix(&home)
        .map(|p| p.to_path_buf())
        .with_context(|| {
            format!(
                "Configured path {} must live under {}",
                path.display(),
                home.display()
            )
        })
}

fn ensure_parent(path: &Path) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("Failed creating directory {}", parent.display()))?;
    }
    Ok(())
}

fn metadata_path(repo_dir: &Path) -> PathBuf {
    repo_dir
        .join(SYMLINK_METADATA_DIR)
        .join(SYMLINK_METADATA_FILE)
}

fn prune_git_dirs(path: &Path) -> Result<()> {
    if !path.exists() {
        return Ok(());
    }

    for entry in WalkDir::new(path).into_iter().filter_map(Result::ok) {
        if entry.file_type().is_dir() && entry.file_name() == ".git" {
            println!(
                "Removing embedded .git directory at {}",
                entry.path().display()
            );
            fs::remove_dir_all(entry.path()).with_context(|| {
                format!(
                    "Failed removing embedded .git directory {}",
                    entry.path().display()
                )
            })?;
        }
    }

    Ok(())
}

fn register_symlink(
    repo_dir: &Path,
    rel: PathBuf,
    target: &Path,
    is_dir: bool,
    entries: &mut Vec<SymlinkEntry>,
) -> Result<()> {
    let rel_string = rel.to_string_lossy().into_owned();
    if entries.iter().any(|entry| entry.path == rel_string) {
        return Ok(());
    }

    let target_string = target.to_string_lossy().into_owned();
    let dest = repo_dir.join(&rel);
    if dest.exists() {
        if dest.is_dir() {
            let _ = fs::remove_dir_all(&dest);
        } else {
            let _ = fs::remove_file(&dest);
        }
    }

    entries.push(SymlinkEntry {
        path: rel_string,
        target: target_string,
        is_dir,
    });

    Ok(())
}

fn collect_symlinks(
    source_root: &Path,
    repo_dir: &Path,
    entries: &mut Vec<SymlinkEntry>,
) -> Result<()> {
    for entry in WalkDir::new(source_root).follow_links(false) {
        let entry = entry?;
        if entry.file_type().is_symlink() {
            let path = entry.path();
            let rel = relative_to_home(path)?;
            let target = fs::read_link(path)
                .with_context(|| format!("Failed reading symlink target {}", path.display()))?;
            let is_dir = path.metadata().map(|m| m.is_dir()).unwrap_or(false);
            register_symlink(repo_dir, rel, &target, is_dir, entries)?;
        }
    }

    Ok(())
}

pub fn snapshot(paths: &[String], repo_dir: &Path) -> Result<()> {
    fs::create_dir_all(repo_dir).with_context(|| {
        format!(
            "Failed to create repository working directory {}",
            repo_dir.display()
        )
    })?;

    let mut symlink_entries: Vec<SymlinkEntry> = Vec::new();

    for raw in paths {
        let expanded = expand_path(raw)?;
        if !expanded.exists() {
            println!(
                "Skipping {} because it does not exist on this machine.",
                raw
            );
            continue;
        }

        let metadata = fs::symlink_metadata(&expanded)
            .with_context(|| format!("Failed to inspect {}", expanded.display()))?;
        if metadata.file_type().is_symlink() {
            let rel = relative_to_home(&expanded)?;
            let target = fs::read_link(&expanded)
                .with_context(|| format!("Failed reading symlink target {}", expanded.display()))?;
            let is_dir = expanded.metadata().map(|m| m.is_dir()).unwrap_or(false);
            register_symlink(repo_dir, rel, &target, is_dir, &mut symlink_entries)?;
            continue;
        }

        let rel = relative_to_home(&expanded)?;
        let dest = repo_dir.join(&rel);

        if expanded.is_dir() {
            if dest.exists() {
                if let Err(err) = fs::remove_dir_all(&dest) {
                    println!(
                        "Skipping {} because destination cleanup failed: {}",
                        raw, err
                    );
                    continue;
                }
            }
            if let Err(err) = ensure_parent(&dest) {
                println!(
                    "Skipping {} because destination parent could not be created: {}",
                    raw, err
                );
                continue;
            }
            let mut options = CopyOptions::new();
            options.copy_inside = false;
            options.overwrite = true;
            if let Err(err) = dir::copy(&expanded, dest.parent().unwrap_or(repo_dir), &options) {
                println!("Skipping {} because copy failed: {}", raw, err);
                continue;
            }

            if let Err(err) = prune_git_dirs(&dest) {
                println!(
                    "Skipping {} because embedded git cleanup failed: {}",
                    raw, err
                );
                continue;
            }

            collect_symlinks(&expanded, repo_dir, &mut symlink_entries)?;
        } else {
            if dest.exists() {
                if let Err(err) = fs::remove_file(&dest) {
                    println!(
                        "Skipping {} because destination cleanup failed: {}",
                        raw, err
                    );
                    continue;
                }
            }
            if let Err(err) = ensure_parent(&dest) {
                println!(
                    "Skipping {} because destination parent could not be created: {}",
                    raw, err
                );
                continue;
            }
            if let Err(err) = fs::copy(&expanded, &dest) {
                println!("Skipping {} because copy failed: {}", raw, err);
                continue;
            }
        }
    }

    let meta_path = metadata_path(repo_dir);
    if symlink_entries.is_empty() {
        if meta_path.exists() {
            let _ = fs::remove_file(&meta_path);
        }
    } else {
        if let Some(parent) = meta_path.parent() {
            fs::create_dir_all(parent).with_context(|| {
                format!("Failed creating metadata directory {}", parent.display())
            })?;
        }
        let data = serde_json::to_vec_pretty(&symlink_entries)?;
        fs::write(&meta_path, data)
            .with_context(|| format!("Failed writing symlink metadata {}", meta_path.display()))?;
    }

    Ok(())
}

pub fn restore(paths: &[String], repo_dir: &Path) -> Result<()> {
    for raw in paths {
        let expanded = expand_path(raw)?;
        let rel = relative_to_home(&expanded)?;
        let source = repo_dir.join(&rel);
        if !source.exists() {
            println!(
                "Skipping {} because it is not present in the repository.",
                raw
            );
            continue;
        }

        if source.is_dir() {
            if expanded.exists() {
                fs::remove_dir_all(&expanded).with_context(|| {
                    format!("Failed removing existing directory {}", expanded.display())
                })?;
            }
            ensure_parent(&expanded)?;
            let mut options = CopyOptions::new();
            options.copy_inside = false;
            options.overwrite = true;
            dir::copy(&source, expanded.parent().unwrap_or(&expanded), &options)
                .with_context(|| format!("Failed restoring directory {}", rel.display()))?;
        } else {
            if expanded.exists() {
                fs::remove_file(&expanded).with_context(|| {
                    format!("Failed removing existing file {}", expanded.display())
                })?;
            }
            ensure_parent(&expanded)?;
            fs::copy(&source, &expanded)
                .with_context(|| format!("Failed restoring file {}", rel.display()))?;
        }
    }

    let meta_path = metadata_path(repo_dir);
    if meta_path.exists() {
        let data = fs::read_to_string(&meta_path)
            .with_context(|| format!("Failed reading symlink metadata {}", meta_path.display()))?;
        let entries: Vec<SymlinkEntry> =
            serde_json::from_str(&data).with_context(|| "Failed parsing symlink metadata")?;
        let home = home_dir()?;
        for entry in entries {
            let dest = home.join(&entry.path);
            if dest.exists() {
                if dest.is_dir() {
                    fs::remove_dir_all(&dest)
                        .with_context(|| format!("Failed removing {}", dest.display()))?;
                } else {
                    fs::remove_file(&dest)
                        .with_context(|| format!("Failed removing {}", dest.display()))?;
                }
            }
            ensure_parent(&dest)?;

            let target_path = PathBuf::from(&entry.target);
            let resolved_target = if target_path.is_absolute() {
                target_path
            } else {
                dest.parent()
                    .unwrap_or_else(|| Path::new("."))
                    .join(target_path)
            };

            #[cfg(unix)]
            {
                symlink(&resolved_target, &dest).with_context(|| {
                    format!(
                        "Failed creating symlink {} -> {}",
                        dest.display(),
                        resolved_target.display()
                    )
                })?;
            }

            #[cfg(windows)]
            {
                use std::os::windows::fs::{symlink_dir, symlink_file};
                if entry.is_dir {
                    symlink_dir(&resolved_target, &dest).with_context(|| {
                        format!(
                            "Failed creating directory symlink {} -> {}",
                            dest.display(),
                            resolved_target.display()
                        )
                    })?;
                } else {
                    symlink_file(&resolved_target, &dest).with_context(|| {
                        format!(
                            "Failed creating file symlink {} -> {}",
                            dest.display(),
                            resolved_target.display()
                        )
                    })?;
                }
            }
        }
    }

    Ok(())
}
