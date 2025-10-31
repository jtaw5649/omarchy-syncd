use anyhow::{Result, anyhow};
use skim::prelude::*;
use std::{
    env,
    io::Write,
    process::{Command, Stdio},
};
use which::which;

#[derive(Clone)]
struct SelectableItem {
    id: String,
    display: String,
}

impl SelectableItem {
    fn new(id: impl Into<String>, display: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            display: display.into(),
        }
    }
}

impl SkimItem for SelectableItem {
    fn text(&self) -> Cow<'_, str> {
        Cow::Borrowed(self.display.as_str())
    }

    fn output(&self) -> Cow<'_, str> {
        Cow::Borrowed(self.id.as_str())
    }
}

pub struct Choice {
    pub id: String,
    pub label: String,
}

pub fn gum_available() -> bool {
    if env::var("OMARCHY_SYNCD_FORCE_NO_GUM").unwrap_or_default() == "1" {
        return false;
    }
    which("gum").is_ok()
}

fn gum_multi_select(header: &str, choices: &[Choice]) -> Result<Vec<String>> {
    if choices.is_empty() {
        return Ok(Vec::new());
    }

    let mut cmd = Command::new("gum");
    cmd.arg("choose")
        .arg("--no-limit")
        .arg("--header")
        .arg(header)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped());

    let mut child = cmd
        .spawn()
        .map_err(|err| anyhow!("Failed launching gum: {err}"))?;
    {
        let mut stdin = child
            .stdin
            .take()
            .ok_or_else(|| anyhow!("Failed to open gum stdin"))?;
        for (idx, choice) in choices.iter().enumerate() {
            if idx > 0 {
                writeln!(stdin)?;
            }
            write!(stdin, "{}", choice.label)?;
        }
    }

    let output = child.wait_with_output()?;
    if !output.status.success() {
        anyhow::bail!("Selection cancelled");
    }

    let stdout = String::from_utf8(output.stdout)?;
    let mut selected = Vec::new();
    for line in stdout.lines() {
        if let Some(choice) = choices.iter().find(|c| c.label == line) {
            selected.push(choice.id.clone());
        }
    }
    Ok(selected)
}

pub fn multi_select(
    prompt: &str,
    header: &str,
    choices: &[Choice],
    extra_binds: &[&str],
) -> Result<Vec<String>> {
    if gum_available() {
        return gum_multi_select(header, choices);
    }

    if choices.is_empty() {
        return Ok(Vec::new());
    }

    let mut binds: Vec<&str> = vec!["tab:toggle", "shift-tab:select-all"];
    binds.extend(extra_binds.iter().copied());

    let options = SkimOptionsBuilder::default()
        .multi(true)
        .prompt(Some(prompt))
        .header(Some(header))
        .bind(binds)
        .build()
        .map_err(|err| anyhow!("Failed creating skim options: {err}"))?;

    let (tx, rx): (SkimItemSender, SkimItemReceiver) = unbounded();
    for choice in choices {
        tx.send(Arc::new(SelectableItem::new(&choice.id, &choice.label)))
            .map_err(|err| anyhow!("Failed queueing selection item: {err}"))?;
    }
    drop(tx);

    let output = Skim::run_with(&options, Some(rx)).ok_or_else(|| anyhow!("Selection aborted"))?;
    if output.is_abort {
        anyhow::bail!("Selection cancelled");
    }

    let selected = output
        .selected_items
        .iter()
        .map(|item| {
            let raw = item.output();
            raw.as_ref().to_string()
        })
        .collect();
    Ok(selected)
}

fn gum_single_select(header: &str, choices: &[Choice]) -> Result<String> {
    if choices.is_empty() {
        anyhow::bail!("No options available");
    }

    let mut cmd = Command::new("gum");
    cmd.arg("choose")
        .arg("--header")
        .arg(header)
        .arg("--selected")
        .arg(&choices[0].label)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped());

    let mut child = cmd
        .spawn()
        .map_err(|err| anyhow!("Failed launching gum: {err}"))?;
    {
        let mut stdin = child
            .stdin
            .take()
            .ok_or_else(|| anyhow!("Failed to open gum stdin"))?;
        for (idx, choice) in choices.iter().enumerate() {
            if idx > 0 {
                writeln!(stdin)?;
            }
            write!(stdin, "{}", choice.label)?;
        }
    }

    let output = child.wait_with_output()?;
    if !output.status.success() {
        anyhow::bail!("Selection cancelled");
    }

    let stdout = String::from_utf8(output.stdout)?;
    let selection = stdout.trim();
    if let Some(choice) = choices.iter().find(|c| c.label == selection) {
        Ok(choice.id.clone())
    } else {
        anyhow::bail!("Selection cancelled")
    }
}

pub fn single_select(
    prompt: &str,
    header: &str,
    choices: &[Choice],
    extra_binds: &[&str],
) -> Result<String> {
    if gum_available() {
        return gum_single_select(header, choices);
    }

    if choices.is_empty() {
        anyhow::bail!("No options available");
    }

    let binds: Vec<&str> = extra_binds.iter().copied().collect();
    let options = SkimOptionsBuilder::default()
        .multi(false)
        .prompt(Some(prompt))
        .header(Some(header))
        .bind(binds)
        .build()
        .map_err(|err| anyhow!("Failed creating skim options: {err}"))?;

    let (tx, rx): (SkimItemSender, SkimItemReceiver) = unbounded();
    for choice in choices {
        tx.send(Arc::new(SelectableItem::new(&choice.id, &choice.label)))
            .map_err(|err| anyhow!("Failed queueing selection item: {err}"))?;
    }
    drop(tx);

    let output = Skim::run_with(&options, Some(rx)).ok_or_else(|| anyhow!("Selection aborted"))?;
    if output.is_abort || output.selected_items.is_empty() {
        anyhow::bail!("Selection cancelled");
    }

    Ok(output.selected_items[0].output().to_string())
}
