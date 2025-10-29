use std::{borrow::Cow, sync::Arc};

use anyhow::{Result, anyhow};
use skim::prelude::*;

#[derive(Clone)]
struct SelectableItem {
    line: String,
}

impl SelectableItem {
    fn new(id: impl Into<String>, display: impl Into<String>) -> Self {
        let id_str = id.into();
        let label_str = display.into();
        let mut line = id_str.clone();
        if !label_str.is_empty() {
            line.push('\t');
            line.push_str(&label_str);
        }
        Self { line }
    }
}

impl SkimItem for SelectableItem {
    fn text(&self) -> Cow<'_, str> {
        Cow::Borrowed(self.line.as_str())
    }
}

pub struct Choice {
    pub id: String,
    pub label: String,
}

pub fn multi_select(prompt: &str, header: &str, choices: &[Choice]) -> Result<Vec<String>> {
    if choices.is_empty() {
        return Ok(Vec::new());
    }

    let options = SkimOptionsBuilder::default()
        .multi(true)
        .prompt(Some(prompt))
        .header(Some(header))
        .bind(vec!["tab:toggle", "shift-tab:toggle+up"])
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
            let raw = item.text();
            let raw_str = raw.as_ref();
            raw_str
                .split_once('\t')
                .map(|(id, _)| id.to_string())
                .unwrap_or_else(|| raw_str.to_string())
        })
        .collect();
    Ok(selected)
}

pub fn single_select(prompt: &str, header: &str, choices: &[Choice]) -> Result<String> {
    if choices.is_empty() {
        anyhow::bail!("No options available");
    }

    let options = SkimOptionsBuilder::default()
        .multi(false)
        .prompt(Some(prompt))
        .header(Some(header))
        .bind(vec!["tab:down", "shift-tab:up"])
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

    let raw = output.selected_items[0].text();
    let raw_str = raw.as_ref();
    let selected = raw_str
        .split_once('\t')
        .map(|(id, _)| id.to_string())
        .unwrap_or_else(|| raw_str.to_string());
    Ok(selected)
}
