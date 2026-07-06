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
| `WIKI_VIEWS` | `~/.codex/wiki/_views` | Stable generated review surfaces |
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
- The user explicitly wants processed Unsorted links moved to `Resources`.
  Recover blocked sources first, then run `raindrop move-processed --apply`.
  Links that are confirmed deleted or unavailable should be marked `gone`, not
  retried forever as `blocked`.
- Treat Raindrop notes as user guidance for ingestion. Preserve the durable
  intent when useful, but do not blindly copy private note text into wiki pages.
- Treat recency as a ranking prior. Newer intake should be reviewed first, and
  newer source dates should win when factual claims conflict and quality is
  comparable. Older sources remain useful as background, history, or prior art.
- Prefer updating existing topics to creating new ones. A topic should represent
  a durable retrieval concept likely to compound across sources.
- Avoid one-source topic sprawl. One source should usually create one source
  note and only update topic pages when it adds durable reusable knowledge.
- Generated state, views, and reports are useful for agents but are not ontology.

## Wiki Shape

```text
~/.codex/wiki/
  AGENTS.md
  rules.md
  index.md
  log.md
  sources/
  topics/
  _views/
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
ingest_status: pending | ingested | reference | blocked | gone | skipped
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
agent_attention: []
agent_attention_reason: ""
source_facets: []
source_entities: []
```

`source_age_days_at_save` may be negative when the source's current published
metadata postdates the Raindrop save time. Treat that as a staleness/change
signal, not as a math error.

### Recency Semantics

The wiki is not a flat bag of notes. Use recency as a ranking prior while
preserving older material for context.

- `source recency`: `source_modified` or `published`; freshness of the source's
  claims.
- `intake recency`: `saved_at`, `raindrop_created`, or `ingested_at`; when the
  user or agent brought the source into the system.

For review queues and scans, prioritize intake recency first because newly
saved material usually reflects current attention. For topic synthesis and
answers, prioritize source recency when claims conflict and source quality is
comparable. Do not flatten old and new claims together without date context.

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

### Refresh Raindrop Tags

```bash
~/.codex/skills/llm-wiki/scripts/wiki.py raindrop refresh-tags \
  --collection -1 \
  --tag test-for-me \
  --tag test-for-agent \
  --tag interesting-to-read \
  --write-report
```

Run this after the user curates Raindrop tags. It updates existing source-note
`raindrop_tags` frontmatter from current Raindrop metadata and writes a local
action report. It also regenerates `~/.codex/wiki/_views/experiment-scan.md`
when tags are supplied. Treat Raindrop tags as human workflow signals, not wiki
ontology or the only source of attention.

### Classify Source Facets

```bash
~/.codex/skills/llm-wiki/scripts/wiki.py sources classify-facets --write-report
```

Run this after ingestion when retrieval facets should be updated. It writes
local-only `source_facets` and `source_entities` frontmatter. It preserves
existing values by default; use `--replace` only for a deliberate full
reclassification.

### Recover Blocked Sources

```bash
~/.codex/skills/llm-wiki/scripts/wiki.py sources recover-blocked --write-report
```

Run this after ingestion or when blocked sources matter. Recovery tries direct
fetch with a larger response budget, Raindrop's cached copy when available, and
Jina Reader as a Markdown fallback. It updates existing source notes and writes
a recovery report. Durable gone signals such as HTTP 404 or 410 from the
original source should become `ingest_status: gone` with the saved provenance
preserved.

### Move Processed Items

```bash
~/.codex/skills/llm-wiki/scripts/wiki.py raindrop move-processed --to-collection Resources
~/.codex/skills/llm-wiki/scripts/wiki.py raindrop move-processed --to-collection Resources --apply
```

Run the dry-run first, then `--apply` after the candidate count looks right.
This moves current Raindrop Unsorted records whose matching source note is
`ingested`, `reference`, or `gone`. It matches by Raindrop ID and canonical URL
so duplicate bookmarks for the same processed source are moved too. It does not
move notes still marked `blocked`; use `--exclude-gone` if dead links should
stay in Unsorted for manual review.

### Scan Experiments

```bash
~/.codex/skills/llm-wiki/scripts/wiki.py actions scan \
  --signal test-for-me \
  --signal test-for-agent \
  --signal interesting-to-read
```

Run this when the user wants to scan things to try without calling Raindrop. The
scan includes sources matching either human `raindrop_tags` or local
`agent_attention` frontmatter, excluding sources marked `gone`. It writes:

- `~/.codex/wiki/_views/experiment-scan.md`: stable human/agent scan view with
  one entry per source link.
- `~/.codex/wiki/_state/experiment-scan.json`: machine-readable action state.

### Scan Recent Sources

```bash
~/.codex/skills/llm-wiki/scripts/wiki.py actions recent --limit 80
```

Run this when the user or an agent needs the recency-biased entry point into the
wiki. It writes:

- `~/.codex/wiki/_views/recent-sources.md`: newest intake first, source dates
  shown explicitly.
- `~/.codex/wiki/_state/recent-sources.json`: machine-readable recent-source
  state.

### Cross-Reference Previously Unsorted Sources

```bash
~/.codex/skills/llm-wiki/scripts/wiki.py actions unsorted-crosswalk
```

Run this when the user wants to review links that were originally in Raindrop
Unsorted against experiment signals and recency. It writes:

- `~/.codex/wiki/_views/previously-unsorted-crosswalk.md`: all source notes
  whose `raindrop_collection_at_ingest` is `Unsorted`, grouped by action bucket
  and annotated with experiment rank plus recency rank.
- `~/.codex/wiki/_state/previously-unsorted-crosswalk.json`:
  machine-readable crosswalk state.

### Filter By Source Facet

```bash
~/.codex/skills/llm-wiki/scripts/wiki.py actions facet --facet model-release
```

Run this when the user wants a retrieval-oriented view such as all model
releases, voice/audio model items, or document/OCR model items. Useful facets:

- `model-release`: new or notable AI model release.
- `model-guide`: practical guide for running, training, or using a model.
- `local-model`: local/open/quantized model capability.
- `voice-audio`: speech, transcription, TTS, or voice model capability.
- `vision-document-ai`: vision, OCR, multimodal, or document extraction model.
- `embedding-retrieval`: embedding, retrieval, or RAG-oriented capability.

### Agent Attention

The user may tag links manually in Raindrop, but agents must also use judgment.
When ingesting or reviewing a source, add local-only source-note frontmatter if
the source should be surfaced:

```yaml
agent_attention: ["test-for-agent"]
agent_attention_reason: "Concise reason this should be scanned or discussed."
```

Use the same signal names as Raindrop tags:

- `test-for-me`: try on the user's Mac, iPhone, apps, or personal setup.
- `test-for-agent`: test in the Codex/agent harness, skills, config, workflow,
  memory, or verification setup.
- `interesting-to-read`: deliberate reading/reflection because it may affect
  judgment, strategy, or first-principles thinking.

Do not write agent judgments back to Raindrop unless the user explicitly asks.

Action signals are not retrieval facets. Use `agent_attention` for actions the
user may want to take, and use `source_facets` plus `source_entities` for later
filtering/searching. Facets are local wiki metadata, not Raindrop tags and not
ontology folders.

### Sync Topic Source Frontmatter

```bash
~/.codex/skills/llm-wiki/scripts/wiki.py sync-topic-sources
```

Run this after topic synthesis. It rewrites each topic's `sources` frontmatter
from actual source wikilinks so agents do not maintain duplicate bookkeeping by
hand.

### Answer From The Wiki

1. Read `rules.md`.
2. Read `_views/recent-sources.md` when present to establish the current
   recency-weighted context.
3. Read `index.md` when present.
4. Use `rg` over `sources/` and `topics/`.
5. Follow relevant wikilinks.
6. Answer from local notes first. Use the web only when freshness matters or
   local notes are insufficient.
