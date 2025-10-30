use anyhow::{Result, anyhow};
use skim::prelude::*;

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

pub fn multi_select(
    prompt: &str,
    header: &str,
    choices: &[Choice],
    extra_binds: &[&str],
) -> Result<Vec<String>> {
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

pub fn single_select(
    prompt: &str,
    header: &str,
    choices: &[Choice],
    extra_binds: &[&str],
) -> Result<String> {
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
