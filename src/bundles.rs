use std::collections::BTreeSet;

use anyhow::{Result, anyhow, bail};

/// Definition of a selectable bundle of dotfiles.
#[derive(Debug, Clone)]
pub struct Bundle {
    pub id: &'static str,
    pub name: &'static str,
    pub description: &'static str,
    pub paths: &'static [&'static str],
}

const BUNDLE_DEFINITIONS: &[Bundle] = &[
    Bundle {
        id: "core_desktop",
        name: "Core Desktop",
        description: "Hyprland, Waybar, Omarchy data, SwayOSD, WayVNC",
        paths: &[
            "~/.config/hypr",
            "~/.config/waybar",
            "~/.config/omarchy",
            "~/.config/swayosd",
            "~/.config/wayvnc",
        ],
    },
    Bundle {
        id: "terminals",
        name: "Terminals",
        description: "Alacritty, Ghostty, Kitty configuration",
        paths: &[
            "~/.config/alacritty",
            "~/.config/ghostty",
            "~/.config/kitty",
        ],
    },
    Bundle {
        id: "cli_tools",
        name: "CLI Tools",
        description: "btop, fastfetch, eza, cava, Walker launcher",
        paths: &[
            "~/.config/btop",
            "~/.config/fastfetch",
            "~/.config/eza",
            "~/.config/cava",
            "~/.config/walker",
        ],
    },
    Bundle {
        id: "editors",
        name: "Editors",
        description: "Neovim and Typora settings",
        paths: &["~/.config/nvim", "~/.config/Typora"],
    },
    Bundle {
        id: "dev_git",
        name: "Git Tooling",
        description: "git, lazygit, gh configuration",
        paths: &["~/.config/git", "~/.config/lazygit", "~/.config/gh"],
    },
    Bundle {
        id: "creative",
        name: "Creative Tools",
        description: "Aether and Elephant assets",
        paths: &["~/.config/aether", "~/.config/elephant"],
    },
    Bundle {
        id: "system",
        name: "System Services",
        description: "User-level systemd units",
        paths: &["~/.config/systemd"],
    },
];

pub const DEFAULT_BUNDLE_IDS: &[&str] = &[
    "core_desktop",
    "terminals",
    "cli_tools",
    "editors",
    "dev_git",
    "creative",
    "system",
];

pub fn all() -> &'static [Bundle] {
    BUNDLE_DEFINITIONS
}

pub fn find(id: &str) -> Option<&'static Bundle> {
    BUNDLE_DEFINITIONS.iter().find(|bundle| bundle.id == id)
}

pub fn resolve_paths(ids: &[String]) -> Result<Vec<String>> {
    let mut set: BTreeSet<String> = BTreeSet::new();
    for id in ids {
        let bundle = find(id).ok_or_else(|| {
            anyhow!(
                "Unknown bundle '{}'. Run `omarchy-syncd bundle list` to see options.",
                id
            )
        })?;
        for path in bundle.paths {
            set.insert((*path).to_string());
        }
    }
    Ok(set.into_iter().collect())
}

pub fn ensure_known(ids: &[String]) -> Result<()> {
    for id in ids {
        if find(id).is_none() {
            bail!("Unknown bundle '{}'", id);
        }
    }
    Ok(())
}
