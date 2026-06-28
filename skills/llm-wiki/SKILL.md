---
name: llm-wiki
description: Maintain the user's local LLM wiki at ~/.codex/wiki and process Raindrop.io bookmarks into agent-readable source and topic notes. Use when Codex needs to bootstrap, inspect, search, ingest, lint, or maintain the wiki, or when working with Raindrop as the source intake queue.
---

# LLM Wiki

The LLM wiki is the canonical local knowledge layer for agents. Raindrop is an
intake queue and source registry, not the wiki ontology.

## Quick Start

```bash
~/.codex/skills/llm-wiki/scripts/wiki.py bootstrap
~/.codex/skills/llm-wiki/scripts/wiki.py raindrop collections
~/.codex/skills/llm-wiki/scripts/wiki.py raindrop inventory --write-report
```

## Paths

| Alias | Path | Purpose |
| --- | --- | --- |
| `WIKI_ROOT` | `~/.codex/wiki` | Canonical local wiki |
| `WIKI_RULES` | `~/.codex/wiki/rules.md` | Ground truth for wiki maintenance |
| `WIKI_SOURCES` | `~/.codex/wiki/sources` | One note per saved source |
| `WIKI_TOPICS` | `~/.codex/wiki/topics` | Living synthesis pages maintained by agents |
| `WIKI_STATE` | `~/.codex/wiki/_state` | Rebuildable sync/cache/bookkeeping state |
| `WIKI_REPORTS` | `~/.codex/wiki/_reports` | Generated reports for human review |

There is intentionally no `collections/` directory. Raindrop collection names
are metadata only. There is intentionally no `arguments/` directory. Durable
session insights should update topic pages only when they are worth preserving.

## Operating Rules

- Read `rules.md` before creating or modifying wiki notes.
- Use `scripts/wiki.py` for bootstrapping and Raindrop inventory/sync work.
- Store Raindrop credentials in macOS Keychain item `raindrop-api` for account
  `$USER`, or in `RAINDROP_TOKEN` for a single command. Never store tokens in
  the wiki or dotfiles.
- By default, process all Raindrop bookmarks except items in `Moose's Corner`
  and `Shopping`. Those collections are excluded from the first ingestion pass.
- Do not treat `Resources`, `Unsorted`, or any other Raindrop collection as a
  topic, folder, or classification scheme.
- Start Raindrop work read-only. Do not add tags, edit notes, move bookmarks, or
  delete anything unless the user explicitly asks after a read-only inventory.
- Treat Raindrop notes as user guidance for ingestion. Preserve the durable
  intent when useful, but do not blindly copy private note text into wiki pages.
- Prefer updating existing topics to creating new ones. A topic should represent
  a durable retrieval concept likely to compound across sources.
- Avoid one-source topic sprawl. One source should usually create one source
  note and only update topic pages when it adds durable reusable knowledge.
- Generated state and reports are useful for agents but are not ontology.

## Wiki Shape

```text
~/.codex/wiki/
  AGENTS.md
  rules.md
  index.md
  log.md
  sources/
  topics/
  _state/
  _reports/
```

### Source Notes

Source notes preserve provenance and concise extraction results. They are the
anchor for claims in topic pages.

Required frontmatter:

```yaml
---
type: source
url: "https://example.com"
canonical_url: "https://example.com"
title: "Source title"
published: "YYYY-MM-DDTHH:MM:SSZ"   # original source publish/create time when known
source_modified: "YYYY-MM-DDTHH:MM:SSZ"
source_type: article
ingest_status: pending | ingested | reference | blocked | skipped
created: "YYYY-MM-DD"
updated: "YYYY-MM-DD"
---
```

Raindrop-sourced notes also include:

```yaml
raindrop_id: 123456
raindrop_collection_at_ingest: "Unsorted"
raindrop_created: "YYYY-MM-DDTHH:MM:SSZ"
saved_at: "YYYY-MM-DDTHH:MM:SSZ"
ingested_at: "YYYY-MM-DDTHH:MM:SSZ"
source_age_days_at_save: 0
source_age_days_at_ingest: 0
raindrop_tags: []
```

`source_age_days_at_save` may be negative when the source's current published
metadata postdates the Raindrop save time. Treat that as a staleness/change
signal, not as a math error.

### Topic Notes

Topic notes are living synthesis pages. They should contain reusable knowledge,
inline source citations via wikilinks, contradictions, and open questions.

Required frontmatter:

```yaml
---
type: topic
tags: []
sources: []
created: "YYYY-MM-DD"
updated: "YYYY-MM-DD"
---
```

## Raindrop Semantics

Use the current Raindrop collection IDs:

- `0`: all bookmarks.
- `-1`: Unsorted.
- `-99`: Trash.

The first pass target is all bookmarks fetched from collection `0`, excluding
items whose current collection title matches `Moose's Corner` or `Shopping`.

## Common Tasks

### Bootstrap The Wiki

```bash
~/.codex/skills/llm-wiki/scripts/wiki.py bootstrap
```

This creates the minimal directory structure and writes `AGENTS.md`, `rules.md`,
`index.md`, and `log.md` if they do not exist.

### Inventory Raindrop

```bash
~/.codex/skills/llm-wiki/scripts/wiki.py raindrop inventory --write-report
```

This fetches bookmark metadata only, excludes `Moose's Corner` and `Shopping`
by default, and writes a JSON state snapshot plus a Markdown report. It does not
ingest page content or write back to Raindrop.

### Ingest A Test Batch

```bash
~/.codex/skills/llm-wiki/scripts/wiki.py raindrop ingest --limit 5 --write-report
```

This creates source notes from the next unprocessed target items. It writes
local wiki files only; it does not write back to Raindrop.

### Backfill Source Dates

```bash
~/.codex/skills/llm-wiki/scripts/wiki.py raindrop enrich-dates
```

This updates existing source notes with original source publication time when
available, Raindrop save time, ingest time, and source age counters. Use this
after changing date extraction logic or importing older source notes.

### Sync Topic Source Frontmatter

```bash
~/.codex/skills/llm-wiki/scripts/wiki.py sync-topic-sources
```

Run this after topic synthesis. It rewrites each topic's `sources` frontmatter
from actual source wikilinks so agents do not maintain duplicate bookkeeping by
hand.

### Answer From The Wiki

1. Read `rules.md`.
2. Read `index.md` when present.
3. Use `rg` over `sources/` and `topics/`.
4. Follow relevant wikilinks.
5. Answer from local notes first. Use the web only when freshness matters or
   local notes are insufficient.
