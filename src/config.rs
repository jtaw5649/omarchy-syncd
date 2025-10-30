use std::{collections::BTreeSet, fs, path::PathBuf};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

use crate::bundles;

const CONFIG_DIR_NAME: &str = "omarchy-syncd";

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct RepoConfig {
    pub url: String,
    #[serde(default = "default_branch")]
    pub branch: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct FileConfig {
    pub paths: Vec<String>,
    #[serde(default)]
    pub bundles: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct SyncConfig {
    pub repo: RepoConfig,
    pub files: FileConfig,
}

impl SyncConfig {
    pub fn ensure_non_empty_paths(&self) -> Result<()> {
        if self.resolved_paths()?.is_empty() {
            anyhow::bail!(
                "No paths configured. Run 'omarchy-syncd init --path <path>' or rerun init with --include-defaults."
            );
        }
        Ok(())
    }

    pub fn resolved_paths(&self) -> Result<Vec<String>> {
        let mut set: BTreeSet<String> = self.files.paths.iter().cloned().collect();
        let from_bundles = bundles::resolve_paths(&self.files.bundles)?;
        for path in from_bundles {
            set.insert(path);
        }
        Ok(set.into_iter().collect())
    }

    pub fn sorted_bundles(&self) -> Vec<String> {
        let mut bundles = self.files.bundles.clone();
        bundles.sort();
        bundles.dedup();
        bundles
    }
}

pub fn default_branch() -> String {
    "main".to_string()
}

pub fn config_dir() -> Result<PathBuf> {
    let base = if let Some(xdg) = std::env::var_os("XDG_CONFIG_HOME") {
        PathBuf::from(xdg)
    } else {
        let home = std::env::var_os("HOME").context("HOME environment variable not set")?;
        PathBuf::from(home).join(".config")
    };
    Ok(base.join(CONFIG_DIR_NAME))
}

pub fn config_file_path() -> Result<PathBuf> {
    Ok(config_dir()?.join("config.toml"))
}

pub fn load_config() -> Result<SyncConfig> {
    let path = config_file_path()?;
    let raw = fs::read_to_string(&path).with_context(|| {
        format!(
            "Missing config at {}. Run 'omarchy-syncd init'.",
            path.display()
        )
    })?;
    let cfg: SyncConfig = toml::from_str(&raw)
        .with_context(|| format!("Failed to parse config TOML at {}", path.display()))?;
    Ok(cfg)
}

pub fn write_config(cfg: &SyncConfig) -> Result<()> {
    let dir = config_dir()?;
    fs::create_dir_all(&dir)
        .with_context(|| format!("Failed to create config directory {}", dir.display()))?;
    let mut normalized = cfg.clone();
    normalized.files.paths.sort();
    normalized.files.paths.dedup();
    normalized.files.bundles = normalized.sorted_bundles();
    bundles::ensure_known(&normalized.files.bundles)?;
    let raw = toml::to_string_pretty(&normalized)?;
    let path = dir.join("config.toml");
    fs::write(&path, raw)
        .with_context(|| format!("Failed to write config file {}", path.display()))?;
    Ok(())
}
