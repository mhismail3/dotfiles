#!/usr/bin/env python3
"""LLM wiki and Raindrop.io helper for Codex.

The script starts with read-only inventory because Raindrop is the intake queue,
not the knowledge ontology. Ingestion and write-back should be added only after
the inventory path has been verified against the user's real account.
"""

from __future__ import annotations

import argparse
import datetime as dt
import email.utils
import hashlib
import html
from html.parser import HTMLParser
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


API_BASE = "https://api.raindrop.io/rest/v1"
DEFAULT_WIKI_ROOT = Path("~/.codex/wiki").expanduser()
DEFAULT_EXCLUDED_COLLECTIONS = ("Moose's Corner", "Shopping")
DEFAULT_ACTION_TAGS = ("test-for-me", "test-for-agent", "interesting-to-read")
DEFAULT_RECENT_LIMIT = 80
DEFAULT_FACET_LIMIT = 120
GONE_HTTP_CODES = {404, 410}


BOOTSTRAP_RULES = """---
type: rules
version: 1
updated: "{date}"
---

# LLM Wiki Rules

This is the ground truth for maintaining the local LLM wiki. The human curates
sources, directs analysis, asks questions, and decides what matters. Agents do
the bookkeeping: ingestion, dedupe, source notes, topic synthesis, cross-links,
staleness checks, contradictions, and reports.

## Structure

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

- `sources/`: one durable note per saved source.
- `topics/`: living synthesis pages maintained organically from sources.
- `_views/`: stable generated review surfaces for human/agent scanning.
- `_state/`: rebuildable sync/cache/bookkeeping state.
- `_reports/`: generated review reports.

There is no `collections/` directory. Raindrop collections are source metadata,
not ontology.

There is no `arguments/` directory. When a chat/session produces durable value,
integrate it into a topic only if it is worth preserving.

## Source Notes

Source notes anchor provenance and extraction. Use one source note per canonical
URL unless two URLs are genuinely different sources.

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

For Raindrop-sourced notes, include:

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

`source_age_days_at_save` may be negative when current source metadata postdates
the Raindrop save time. Preserve that value as a changed-source signal.

## Topic Notes

Topic notes are living synthesis. They should be concise, source-linked, and
useful for future retrieval or ideation.

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

Create a topic only when the concept has a durable retrieval job and is likely
to compound. Prefer extending existing topics over creating one-source topics.

After editing topic pages, run `wiki.py sync-topic-sources` so each topic's
`sources` frontmatter is rebuilt from actual source wikilinks instead of kept
by hand.

## Wikilinks

Use `[[source-slug]]` and `[[topic-slug]]` for meaningful links. Every factual
claim in a topic should cite at least one source note.

## Raindrop

Raindrop is an intake queue and source registry. Do not mirror its collection
structure into the wiki. The default ingestion target is all bookmarks except
items in `Moose's Corner` and `Shopping`.

Raindrop tags are workflow signals, not wiki ontology:

- `test-for-me`: candidate to try on the user's own Mac, iPhone, apps, or
  personal setup.
- `test-for-agent`: candidate to test in the Codex/agent harness, skills,
  config, workflow, memory, or verification setup.
- `interesting-to-read`: candidate for deliberate reading/reflection because it
  may change judgment, strategy, or first-principles thinking.

Use these tags to propose experiments, Things actions, and setup changes. Do
not create topic folders from tag names.

Raindrop tags are human signals only. Agents should also use their own judgment
when ingesting or reviewing sources. If a source should be surfaced even without
a human tag, write local-only source-note frontmatter:

```yaml
agent_attention: ["test-for-agent"]
agent_attention_reason: "Reason this should be scanned or discussed."
```

Use the same signal names as Raindrop tags. Do not write agent judgments back to
Raindrop unless the user explicitly asks.

Action signals are not retrieval facets. Use `agent_attention` for actions the
user may want to take, and use `source_facets` plus `source_entities` for later
filtering/searching. Example retrieval facets include:

- `model-release`: new or notable AI model release.
- `model-guide`: practical guide for running, training, or using a model.
- `local-model`: local/open/quantized model capability.
- `voice-audio`: speech, transcription, TTS, or voice model capability.
- `vision-document-ai`: vision, OCR, multimodal, or document extraction model.
- `embedding-retrieval`: embedding, retrieval, or RAG-oriented capability.

Facets are local wiki metadata, not Raindrop tags and not ontology folders.

Generated action scans should exclude sources marked `gone`. The source note
stays in the wiki for provenance, but dead links should not remain actionable
test or reading candidates.

## Recency

Recency is a ranking prior, not an ontology. Agents should inspect newer source
notes before older ones, but older sources remain useful as foundation, history,
and contradiction evidence.

Use two separate dates:

- `source recency`: `source_modified` or `published`; this is the freshness of
  the source's claims.
- `intake recency`: `saved_at`, `raindrop_created`, or `ingested_at`; this is
  when the user or agent brought the source into the system.

For action scans and review queues, prioritize intake recency first because
newly saved material is usually closest to the user's current attention. For
topic synthesis and answers, prioritize source recency first when factual
claims conflict and source quality is comparable. Do not flatten old and new
claims together without date context; phrase older material as background,
prior art, or historical context.

Raindrop collection IDs:

- `0`: all bookmarks.
- `-1`: Unsorted.
- `-99`: Trash.

Do not write back to Raindrop until read-only inventory and local ingest have
been verified.

If a source returns durable gone signals such as HTTP 404 or 410 from the
original source or a source-specific metadata endpoint, mark the source note
`ingest_status: gone`. Preserve the Raindrop ID, URL, saved date, and blocker
details. Do not keep retrying `gone` sources as normal blocked sources.

The user explicitly wants processed Unsorted links moved to `Resources`.
Recover blocked sources first, then move source notes with `ingest_status` of
`ingested`, `reference`, or `gone`. Do not move sources that are still
`blocked`.

## Generated Files

`index.md` is a rebuildable content map. `_views/`, `_state/`, and `_reports/`
are generated agent work products. They are useful, but they do not define the
ontology.
"""


BOOTSTRAP_AGENTS = """# LLM Wiki Agent Notes

Read `rules.md` before editing wiki notes.

The wiki has two primary knowledge primitives:

- `sources/`: saved source records and extraction summaries.
- `topics/`: living synthesis maintained from sources.

Raindrop collection names are provenance only. Do not create folders or topics
from `Resources`, `Unsorted`, `Moose's Corner`, or `Shopping`.

Default Raindrop policy:

- Include all bookmarks except `Moose's Corner` and `Shopping`.
- Run read-only inventory before ingesting.
- Do not write tags, move bookmarks, edit notes, or delete anything unless the
  user explicitly asks.
- Treat Raindrop notes as ingestion guidance, not content to copy blindly.
"""


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0)


def today() -> str:
    return dt.date.today().isoformat()


def parse_datetime(value: Any) -> dt.datetime | None:
    text = str(value or "").strip()
    if not text:
        return None
    normalized = text.replace("Z", "+00:00")
    try:
        parsed = dt.datetime.fromisoformat(normalized)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=dt.timezone.utc)
        return parsed.astimezone(dt.timezone.utc).replace(microsecond=0)
    except ValueError:
        pass
    try:
        parsed = email.utils.parsedate_to_datetime(text)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=dt.timezone.utc)
        return parsed.astimezone(dt.timezone.utc).replace(microsecond=0)
    except (TypeError, ValueError):
        pass
    for fmt in ("%B %d, %Y", "%b %d, %Y", "%B %d %Y", "%b %d %Y", "%Y-%m-%d"):
        try:
            parsed_date = dt.datetime.strptime(text, fmt)
            return parsed_date.replace(tzinfo=dt.timezone.utc)
        except ValueError:
            continue
    return None


def iso_datetime(value: Any) -> str:
    parsed = parse_datetime(value)
    return parsed.isoformat().replace("+00:00", "Z") if parsed else ""


def age_days(older: Any, newer: Any) -> int | None:
    older_dt = parse_datetime(older)
    newer_dt = parse_datetime(newer)
    if older_dt is None or newer_dt is None:
        return None
    return (newer_dt.date() - older_dt.date()).days


def print_json(data: Any) -> None:
    print(json.dumps(data, indent=2, ensure_ascii=False, sort_keys=True))


class ReadableHTMLParser(HTMLParser):
    """Small stdlib HTML text extractor.

    This is intentionally conservative. It captures enough text for a source
    note preview without trying to archive full copyrighted pages.
    """

    BLOCK_TAGS = {"p", "h1", "h2", "h3", "h4", "li", "blockquote", "pre"}
    SKIP_TAGS = {"script", "style", "noscript", "svg", "canvas"}

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.skip_depth = 0
        self.current_tag = ""
        self.title_parts: list[str] = []
        self.text_parts: list[str] = []
        self.meta: dict[str, str] = {}
        self.time_datetimes: list[str] = []
        self.json_ld_parts: list[str] = []
        self.current_script_type = ""

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.current_tag = tag
        attr_map = {key.casefold(): value or "" for key, value in attrs}
        if tag == "script":
            self.current_script_type = attr_map.get("type", "")
        if tag in self.SKIP_TAGS:
            self.skip_depth += 1
        if tag == "meta":
            key = attr_map.get("property") or attr_map.get("name") or attr_map.get("itemprop")
            content = attr_map.get("content")
            if key and content:
                self.meta[key.casefold()] = clean_text(content)
        if tag == "time" and attr_map.get("datetime"):
            self.time_datetimes.append(clean_text(attr_map["datetime"]))

    def handle_endtag(self, tag: str) -> None:
        if tag in self.SKIP_TAGS and self.skip_depth:
            self.skip_depth -= 1
        if tag == "script":
            self.current_script_type = ""
        self.current_tag = ""

    def handle_data(self, data: str) -> None:
        if self.current_tag == "script" and "ld+json" in self.current_script_type:
            self.json_ld_parts.append(data)
            return
        if self.skip_depth:
            return
        text = re.sub(r"\s+", " ", data).strip()
        if not text:
            return
        if self.current_tag == "title":
            self.title_parts.append(text)
        elif self.current_tag in self.BLOCK_TAGS:
            self.text_parts.append(text)

    @property
    def title(self) -> str:
        return clean_text(" ".join(self.title_parts))

    @property
    def text(self) -> str:
        return clean_text("\n\n".join(self.text_parts))

    def metadata_date(self, keys: tuple[str, ...]) -> str:
        for key in keys:
            value = self.meta.get(key.casefold())
            if value:
                return value
        return ""


def iter_jsonld_values(value: Any) -> list[Any]:
    if isinstance(value, dict):
        output: list[Any] = [value]
        graph = value.get("@graph")
        if graph is not None:
            output.extend(iter_jsonld_values(graph))
        for nested in value.values():
            if isinstance(nested, (dict, list)):
                output.extend(iter_jsonld_values(nested))
        return output
    if isinstance(value, list):
        output: list[Any] = []
        for item in value:
            output.extend(iter_jsonld_values(item))
        return output
    return []


def jsonld_date(json_ld_parts: list[str], keys: tuple[str, ...]) -> str:
    wanted = {key.casefold() for key in keys}
    for part in json_ld_parts:
        try:
            payload = json.loads(part)
        except json.JSONDecodeError:
            continue
        for obj in iter_jsonld_values(payload):
            for key, value in obj.items():
                if key.casefold() in wanted:
                    parsed = iso_datetime(value)
                    if parsed:
                        return parsed
    return ""


def visible_date(text: str, labels: tuple[str, ...]) -> str:
    month = r"(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Sept|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)"
    date_patterns = (
        rf"{month}\s+\d{{1,2}},\s+\d{{4}}",
        rf"{month}\s+\d{{1,2}}\s+\d{{4}}",
        r"\d{4}-\d{2}-\d{2}",
    )
    label_pattern = "|".join(re.escape(label) for label in labels)
    for date_pattern in date_patterns:
        match = re.search(
            rf"\b(?:{label_pattern})\b\s*(?:on\s+)?[:\-]?\s*({date_pattern})",
            text,
            flags=re.I,
        )
        if match:
            parsed = iso_datetime(match.group(1))
            if parsed:
                return parsed
    return ""


def clean_text(value: str, limit: int | None = None) -> str:
    text = html.unescape(value or "")
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    text = text.strip()
    if limit is not None and len(text) > limit:
        text = text[:limit].rstrip() + "..."
    return text


def yaml_value(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False)


def domain_from_url(url: str) -> str:
    host = urllib.parse.urlparse(url).netloc.lower()
    return host.removeprefix("www.") or "unknown"


def canonical_url(url: str) -> str:
    parsed = urllib.parse.urlparse(url)
    scheme = (parsed.scheme or "https").lower()
    host = parsed.netloc.lower().removeprefix("www.")
    path = parsed.path or "/"

    if host in {"twitter.com", "x.com", "fxtwitter.com", "fixupx.com"}:
        match = re.search(r"/([^/]+)/status/(\d+)", path)
        if match:
            return f"https://x.com/{match.group(1)}/status/{match.group(2)}"

    drop_params = {
        "fbclid",
        "gclid",
        "igsh",
        "mc_cid",
        "mc_eid",
        "s",
        "t",
    }
    query_pairs = []
    for key, value in urllib.parse.parse_qsl(parsed.query, keep_blank_values=True):
        if key.startswith("utm_") or key in drop_params:
            continue
        query_pairs.append((key, value))
    query = urllib.parse.urlencode(query_pairs)
    normalized = urllib.parse.urlunparse((scheme, host, path.rstrip("/") or "/", "", query, ""))
    return normalized


def safe_slug(value: str, limit: int = 96) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.casefold())
    slug = slug.strip("-")
    if len(slug) > limit:
        slug = slug[:limit].rstrip("-")
    return slug or "untitled"


def markdown_escape(value: str) -> str:
    return (value or "").replace("|", "\\|")


def normalize_collection_title(value: str) -> str:
    return (
        value.casefold()
        .replace("\u2019", "'")
        .replace("`", "'")
        .replace("'", "")
        .strip()
    )


def wiki_root(args: argparse.Namespace) -> Path:
    return Path(args.wiki_root).expanduser()


def require_rules(root: Path) -> None:
    rules = root / "rules.md"
    if not rules.exists():
        raise SystemExit(f"Wiki rules missing. Run: {sys.argv[0]} --wiki-root {root} bootstrap")


def bootstrap(root: Path) -> dict[str, Any]:
    created: list[str] = []
    for directory in (
        root,
        root / "sources",
        root / "topics",
        root / "_views",
        root / "_state",
        root / "_reports",
    ):
        if not directory.exists():
            directory.mkdir(parents=True, exist_ok=True)
            created.append(str(directory))

    files = {
        root / "rules.md": BOOTSTRAP_RULES.format(date=today()),
        root / "AGENTS.md": BOOTSTRAP_AGENTS,
        root / "index.md": f"---\ntype: index\nupdated: \"{utc_now().isoformat()}\"\npage_count: 0\n---\n\n# Wiki Index\n\n## Sources\n\n## Topics\n\n## Views\n",
        root / "log.md": "# Wiki Log\n",
    }
    for path, content in files.items():
        if not path.exists():
            path.write_text(content, encoding="utf-8")
            created.append(str(path))

    return {"wiki_root": str(root), "created": created}


def get_token() -> str:
    token = os.environ.get("RAINDROP_TOKEN")
    if token:
        return token

    user = os.environ.get("USER", "")
    proc = subprocess.run(
        ["security", "find-generic-password", "-a", user, "-s", "raindrop-api", "-w"],
        text=True,
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        raise SystemExit(
            "Raindrop token not found. Save it in Keychain item 'raindrop-api' "
            "for account $USER, or set RAINDROP_TOKEN for this command."
        )
    token = proc.stdout.strip()
    if not token:
        raise SystemExit("Raindrop token lookup returned an empty value.")
    return token


def api_request(
    method: str,
    path: str,
    params: dict[str, Any] | None = None,
    body: dict[str, Any] | None = None,
) -> dict[str, Any]:
    token = get_token()
    url = f"{API_BASE}{path}"
    if params:
        url = f"{url}?{urllib.parse.urlencode(params)}"
    payload = None
    headers = {"Authorization": f"Bearer {token}"}
    if body is not None:
        payload = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(url, data=payload, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:500]
        raise SystemExit(f"Raindrop API error {exc.code} for {method} {path}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise SystemExit(f"Could not reach Raindrop API for {method} {path}: {exc.reason}") from exc


def api_get(path: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
    return api_request("GET", path, params=params)


def api_put(path: str, body: dict[str, Any]) -> dict[str, Any]:
    return api_request("PUT", path, body=body)


def collection_id(collection: dict[str, Any]) -> int | None:
    raw = collection.get("_id")
    if raw is None:
        raw = collection.get("id")
    try:
        return int(raw)
    except (TypeError, ValueError):
        return None


def collection_title(collection: dict[str, Any]) -> str:
    return str(collection.get("title") or collection.get("name") or "")


def item_collection_id(item: dict[str, Any]) -> int | None:
    collection = item.get("collection")
    if isinstance(collection, dict):
        for key in ("$id", "_id", "id"):
            if key in collection:
                try:
                    return int(collection[key])
                except (TypeError, ValueError):
                    return None
    try:
        return int(collection)
    except (TypeError, ValueError):
        return None


def fetch_collections() -> list[dict[str, Any]]:
    response = api_get("/collections")
    items = response.get("items")
    if not isinstance(items, list):
        raise SystemExit("Unexpected Raindrop collections response.")

    try:
        child_response = api_get("/collections/childrens")
        child_items = child_response.get("items")
        if isinstance(child_items, list):
            items.extend(child_items)
    except SystemExit:
        pass

    seen: set[int] = set()
    unique: list[dict[str, Any]] = []
    for item in items:
        cid = collection_id(item)
        if cid is None or cid in seen:
            continue
        seen.add(cid)
        unique.append(item)
    return unique


def collection_names_by_id() -> dict[int, str]:
    collections = fetch_collections()
    names = {
        cid: collection_title(collection)
        for collection in collections
        if (cid := collection_id(collection)) is not None
    }
    names.update({0: "All", -1: "Unsorted", -99: "Trash"})
    return names


def collection_id_by_title(title: str) -> int:
    normalized = normalize_collection_title(title)
    matches = [
        cid
        for cid, candidate in collection_names_by_id().items()
        if normalize_collection_title(candidate) == normalized
    ]
    if not matches:
        raise SystemExit(f"Raindrop collection not found: {title}")
    return matches[0]


def fetch_raindrops(collection: int, max_items: int | None = None) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    page = 0
    perpage = 50
    while True:
        response = api_get(
            f"/raindrops/{collection}",
            {"page": page, "perpage": perpage, "sort": "-created"},
        )
        page_items = response.get("items")
        if not isinstance(page_items, list) or not page_items:
            break
        items.extend(page_items)
        if max_items is not None and len(items) >= max_items:
            return items[:max_items]
        if len(page_items) < perpage:
            break
        page += 1
    return items


def http_get(
    url: str,
    timeout: int = 35,
    max_bytes: int = 1_500_000,
    headers: dict[str, str] | None = None,
) -> tuple[str, bytes]:
    request_headers = {
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X) Codex LLM Wiki/1.0",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,text/plain;q=0.8,*/*;q=0.5",
    }
    if headers:
        request_headers.update(headers)
    request = urllib.request.Request(
        url,
        headers=request_headers,
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        content_type = response.headers.get("content-type", "")
        body = response.read(max_bytes + 1)
    if len(body) > max_bytes:
        raise ValueError(f"response exceeded {max_bytes} bytes")
    return content_type, body


def is_gone_exception(exc: Exception) -> bool:
    return isinstance(exc, urllib.error.HTTPError) and exc.code in GONE_HTTP_CODES


def gone_result(
    reason: str,
    method: str,
    attempts: list[str] | None = None,
    errors: list[str] | None = None,
) -> dict[str, Any]:
    summary = "Source appears to be deleted or no longer publicly available."
    if reason:
        summary = f"{summary} {reason}"
    return {
        "source_type": "reference",
        "ingest_status": "gone",
        "title": "",
        "summary": summary,
        "extract": "",
        "error": reason,
        "method": method,
        "attempts": attempts or [],
        "errors": errors or [],
    }


def raindrop_cache_get(raindrop_id: str, timeout: int = 45, max_bytes: int = 12_000_000) -> tuple[str, bytes]:
    token = get_token()
    request = urllib.request.Request(
        f"{API_BASE}/raindrop/{raindrop_id}/cache",
        headers={"Authorization": f"Bearer {token}"},
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        content_type = response.headers.get("content-type", "")
        body = response.read(max_bytes + 1)
    if len(body) > max_bytes:
        raise ValueError(f"Raindrop cache response exceeded {max_bytes} bytes")
    return content_type, body


def pdf_text(body: bytes) -> str:
    pdftotext = shutil.which("pdftotext")
    if not pdftotext:
        return ""
    with tempfile.NamedTemporaryFile(suffix=".pdf") as handle:
        handle.write(body)
        handle.flush()
        proc = subprocess.run(
            [pdftotext, "-layout", handle.name, "-"],
            text=True,
            capture_output=True,
            check=False,
            timeout=60,
        )
    if proc.returncode != 0:
        return ""
    return clean_text(proc.stdout)


def extract_response_body(
    url: str,
    content_type: str,
    body: bytes,
    method: str,
) -> dict[str, Any]:
    if "pdf" in content_type.lower() or body.startswith(b"%PDF"):
        text = pdf_text(body)
        if text:
            return {
                "source_type": "pdf",
                "ingest_status": "ingested",
                "title": "",
                "summary": clean_text(text, 1400),
                "extract": clean_text(text, 3000),
                "error": "",
                "method": method,
            }
        return {
            "source_type": "pdf",
            "ingest_status": "reference",
            "title": "",
            "summary": "PDF source saved as a reference. Local pdftotext extraction was unavailable or returned no readable text.",
            "extract": "",
            "error": "",
            "method": method,
        }

    raw = decode_body(body, content_type)
    if "html" in content_type.lower() or "<html" in raw[:500].casefold():
        parser = ReadableHTMLParser()
        parser.feed(raw)
        text = parser.text
        if len(text) < 200:
            return {
                "source_type": "reference",
                "ingest_status": "reference",
                "title": parser.title,
                "summary": "Reference page saved, but the static HTML did not expose enough readable article text.",
                "extract": clean_text(text, 1200),
                "error": "",
                "published": "",
                "modified": "",
                "method": method,
            }
        return {
            "source_type": "article",
            "ingest_status": "ingested",
            "title": parser.title,
            "summary": clean_text(text, 1400),
            "extract": clean_text(text, 3000),
            "error": "",
            "published": "",
            "modified": "",
            "method": method,
        }

    text = clean_text(raw)
    if len(text) < 80:
        return {
            "source_type": "reference",
            "ingest_status": "reference",
            "title": "",
            "summary": "Reference saved, but the response did not contain readable text.",
            "extract": clean_text(text, 1200),
            "error": "",
            "method": method,
        }
    return {
        "source_type": "text",
        "ingest_status": "ingested",
        "title": "",
        "summary": clean_text(text, 1400),
        "extract": clean_text(text, 3000),
        "error": "",
        "method": method,
    }


def extract_jina_reader(url: str) -> dict[str, Any]:
    reader_url = f"https://r.jina.ai/{url}"
    content_type, body = http_get(
        reader_url,
        timeout=60,
        max_bytes=3_000_000,
        headers={"Accept": "application/json"},
    )
    raw = decode_body(body, content_type)
    title = ""
    content = ""
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        payload = None
    if isinstance(payload, dict):
        data = payload.get("data") if isinstance(payload.get("data"), dict) else payload
        title = clean_text(str(data.get("title") or "")) if isinstance(data, dict) else ""
        content = clean_text(str(data.get("content") or data.get("text") or "")) if isinstance(data, dict) else ""
    if not content:
        content = re.sub(r"(?is)^.*?Markdown Content:\s*", "", raw, count=1)
        title_match = re.search(r"(?im)^Title:\s*(.+)$", raw)
        title = clean_text(title_match.group(1)) if title_match else title
    content = clean_text(content)
    if len(content) < 120:
        raise ValueError("Jina Reader did not return enough readable content")
    return {
        "source_type": "article",
        "ingest_status": "ingested",
        "title": title,
        "summary": clean_text(content, 1400),
        "extract": clean_text(content, 3000),
        "error": "",
        "method": "jina-reader",
    }


def decode_body(body: bytes, content_type: str) -> str:
    charset = "utf-8"
    match = re.search(r"charset=([^;]+)", content_type, flags=re.I)
    if match:
        charset = match.group(1).strip()
    try:
        return body.decode(charset, errors="replace")
    except LookupError:
        return body.decode("utf-8", errors="replace")


def extract_html_page(url: str) -> dict[str, Any]:
    content_type, body = http_get(url)
    if "pdf" in content_type.lower():
        return {
            "source_type": "pdf",
            "ingest_status": "reference",
            "title": "",
            "summary": "PDF source saved as a reference. Full PDF extraction is not implemented in this helper yet.",
            "extract": "",
            "error": "",
        }
    if body.startswith(b"%PDF"):
        return {
            "source_type": "pdf",
            "ingest_status": "reference",
            "title": "",
            "summary": "PDF source saved as a reference. Full PDF extraction is not implemented in this helper yet.",
            "extract": "",
            "error": "",
        }

    raw = decode_body(body, content_type)
    if "html" in content_type.lower() or "<html" in raw[:500].casefold():
        parser = ReadableHTMLParser()
        parser.feed(raw)
        text = parser.text
        published = iso_datetime(
            parser.metadata_date(
                (
                    "article:published_time",
                    "article:published",
                    "datepublished",
                    "date",
                    "pubdate",
                    "publishdate",
                    "sailthru.date",
                    "dc.date",
                    "dc.date.issued",
                )
            )
            or (parser.time_datetimes[0] if parser.time_datetimes else "")
            or jsonld_date(
                parser.json_ld_parts,
                (
                    "datePublished",
                    "dateCreated",
                    "uploadDate",
                    "date",
                ),
            )
            or visible_date(text, ("Published", "Posted", "Released"))
        )
        modified = iso_datetime(
            parser.metadata_date(
                (
                    "article:modified_time",
                    "datemodified",
                    "modified",
                    "lastmod",
                    "og:updated_time",
                )
            )
            or jsonld_date(
                parser.json_ld_parts,
                (
                    "dateModified",
                    "dateUpdated",
                    "updated",
                ),
            )
            or visible_date(text, ("Updated", "Last updated", "Modified"))
        )
        if len(text) < 200:
            return {
                "source_type": "reference",
                "ingest_status": "reference",
                "title": parser.title,
                "summary": "Reference page saved, but the static HTML did not expose enough readable article text.",
                "extract": clean_text(text, 1200),
                "error": "",
                "published": published,
                "modified": modified,
            }
        return {
            "source_type": "article",
            "ingest_status": "ingested",
            "title": parser.title,
            "summary": clean_text(text, 700),
            "extract": clean_text(text, 2200),
            "error": "",
            "published": published,
            "modified": modified,
        }

    text = clean_text(raw)
    if len(text) < 80:
        return {
            "source_type": "reference",
            "ingest_status": "reference",
            "title": "",
            "summary": "Reference saved, but the response did not contain readable text.",
            "extract": clean_text(text, 1200),
            "error": "",
        }
    return {
        "source_type": "text",
        "ingest_status": "ingested",
        "title": "",
        "summary": clean_text(text, 700),
        "extract": clean_text(text, 2200),
        "error": "",
    }


def x_status_id(url: str) -> str | None:
    parsed = urllib.parse.urlparse(url)
    if parsed.netloc.lower().removeprefix("www.") not in {"x.com", "twitter.com", "fxtwitter.com", "fixupx.com"}:
        return None
    match = re.search(r"/status/(\d+)", parsed.path)
    return match.group(1) if match else None


def extract_x_status(url: str) -> dict[str, Any]:
    status_id = x_status_id(url)
    if not status_id:
        raise ValueError("not an X/Twitter status URL")
    api_url = f"https://api.fxtwitter.com/2/status/{status_id}"
    content_type, body = http_get(api_url)
    data = json.loads(decode_body(body, content_type))
    status = data.get("status") or {}
    author = status.get("author") or data.get("author") or {}
    article = status.get("article") or {}
    if article:
        blocks = (((article.get("content") or {}).get("blocks")) or [])
        block_text = "\n\n".join(clean_text(block.get("text") or "") for block in blocks if block.get("text"))
        article_title = clean_text(article.get("title") or f"X Article {article.get('id') or status_id}")
        preview = clean_text(article.get("preview_text") or "")
        summary_parts = [part for part in (preview, block_text) if part]
        summary = clean_text("\n\n".join(summary_parts), 900)
        return {
            "source_type": "x_article",
            "ingest_status": "ingested" if block_text or preview else "reference",
            "title": article_title,
            "summary": summary or f"X Article by {author.get('screen_name') or 'unknown author'}",
            "extract": clean_text(block_text or preview, 2400),
            "error": "",
            "extra": {
                "x_status_id": status_id,
                "x_article_id": str(article.get("id") or ""),
                "x_author": clean_text(author.get("screen_name") or ""),
                "x_author_name": clean_text(author.get("name") or ""),
                "x_fetch_url": api_url,
            },
            "published": iso_datetime(article.get("created_at") or status.get("created_at")),
            "modified": iso_datetime(article.get("modified_at")),
        }

    text = clean_text(status.get("text") or status.get("raw_text", {}).get("text") or "")
    author_name = clean_text(author.get("name") or author.get("screen_name") or "")
    screen_name = clean_text(author.get("screen_name") or "")
    title = text.split("\n", 1)[0] if text else f"X post {status_id}"
    status_value = "reference" if re.fullmatch(r"https?://\S+", text or "") else "ingested"
    summary = f"X post by {author_name or screen_name}: {clean_text(text, 650)}"
    return {
        "source_type": "tweet",
        "ingest_status": status_value if text else "reference",
        "title": title,
        "summary": summary,
        "extract": text,
        "error": "",
        "extra": {
            "x_status_id": status_id,
            "x_author": screen_name,
            "x_author_name": author_name,
            "x_fetch_url": api_url,
        },
        "published": iso_datetime(status.get("created_at")),
        "modified": "",
    }


def extract_url(url: str) -> dict[str, Any]:
    try:
        if x_status_id(url):
            return extract_x_status(url)
        return extract_html_page(url)
    except Exception as exc:  # noqa: BLE001 - this is a bounded per-source ingest.
        if is_gone_exception(exc):
            method = "x-status" if x_status_id(url) else "direct"
            return gone_result(f"{type(exc).__name__}: HTTP {exc.code}: {exc.reason}", method=method)
        return {
            "source_type": "reference",
            "ingest_status": "blocked",
            "title": "",
            "summary": "Could not extract readable content during the first-pass ingest.",
            "extract": "",
            "error": f"{type(exc).__name__}: {exc}",
        }


def recover_url(url: str, raindrop_id: str | None = None) -> dict[str, Any]:
    attempts: list[str] = []
    errors: list[str] = []
    gone_errors: list[str] = []
    methods: list[tuple[str, Any]] = [
        ("direct-large", lambda: extract_response_body(url, *http_get(url, max_bytes=12_000_000), method="direct-large")),
    ]
    if raindrop_id:
        methods.append(
            (
                "raindrop-cache",
                lambda: extract_response_body(url, *raindrop_cache_get(raindrop_id), method="raindrop-cache"),
            )
        )
    methods.append(("jina-reader", lambda: extract_jina_reader(url)))

    best: dict[str, Any] | None = None
    for method, fn in methods:
        attempts.append(method)
        try:
            result = fn()
        except Exception as exc:  # noqa: BLE001 - bounded per-source recovery.
            error = f"{method}: {type(exc).__name__}: {exc}"
            errors.append(error)
            if method == "direct-large" and is_gone_exception(exc):
                gone_errors.append(error)
            continue
        result["method"] = result.get("method") or method
        if result.get("ingest_status") == "ingested":
            result["attempts"] = attempts
            result["errors"] = errors
            return result
        if best is None:
            best = result
    if best is not None:
        best["attempts"] = attempts
        best["errors"] = errors
        return best
    if gone_errors:
        return gone_result(
            "Original source returned a durable gone status: " + "; ".join(gone_errors),
            method="gone",
            attempts=attempts,
            errors=errors,
        )
    return {
        "source_type": "reference",
        "ingest_status": "blocked",
        "title": "",
        "summary": "Could not recover readable content from direct fetch, Raindrop cache, or Jina Reader.",
        "extract": "",
        "error": "; ".join(errors),
        "method": "none",
        "attempts": attempts,
        "errors": errors,
    }


def existing_raindrop_ids(root: Path) -> set[int]:
    ids: set[int] = set()
    for path in (root / "sources").glob("*.md"):
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for match in re.finditer(r"(?m)^raindrop_id:\s*['\"]?(\d+)['\"]?\s*$", text):
            ids.add(int(match.group(1)))
    return ids


def existing_raindrop_paths(root: Path) -> dict[int, Path]:
    paths: dict[int, Path] = {}
    for path in (root / "sources").glob("*.md"):
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        match = re.search(r"(?m)^raindrop_id:\s*['\"]?(\d+)['\"]?\s*$", text)
        if match:
            paths[int(match.group(1))] = path
    return paths


def frontmatter_scalar(text: str, key: str) -> str | None:
    match = re.search(rf"(?m)^{re.escape(key)}:\s*(.+?)\s*$", text)
    if not match:
        return None
    raw = match.group(1).strip()
    try:
        value = json.loads(raw)
    except json.JSONDecodeError:
        value = raw.strip("'\"")
    return str(value)


def frontmatter_value(text: str, key: str) -> Any:
    raw = parse_frontmatter_map(text).get(key)
    if raw is None:
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return raw.strip("'\"")


def frontmatter_list(text: str, key: str) -> list[str]:
    value = frontmatter_value(text, key)
    if value is None or value == "":
        return []
    if isinstance(value, list):
        return [str(item) for item in value if str(item)]
    return [str(value)]


def parse_frontmatter_map(text: str) -> dict[str, str]:
    if not text.startswith("---\n"):
        return {}
    end = text.find("\n---", 4)
    if end == -1:
        return {}
    fields: dict[str, str] = {}
    for line in text[4:end].splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        fields[key.strip()] = value.strip()
    return fields


def update_frontmatter(text: str, updates: dict[str, Any], force: bool = False) -> str:
    if not text.startswith("---\n"):
        return text
    end = text.find("\n---", 4)
    if end == -1:
        return text
    before = text[4:end].splitlines()
    after = text[end:]
    current = parse_frontmatter_map(text)
    remaining = dict(updates)
    lines: list[str] = []
    for line in before:
        if ":" not in line:
            lines.append(line)
            continue
        key = line.split(":", 1)[0].strip()
        if key in remaining:
            value = remaining.pop(key)
            if force or current.get(key, "") in {"", '""', "null"}:
                lines.append(f"{key}: {yaml_value(value)}")
            else:
                lines.append(line)
        else:
            lines.append(line)
    for key, value in remaining.items():
        if force or key not in current:
            lines.append(f"{key}: {yaml_value(value)}")
    return "---\n" + "\n".join(lines) + after


def replace_markdown_section(text: str, heading: str, content: str) -> str:
    section = f"## {heading}\n\n{content.strip()}\n"
    pattern = rf"(?ms)^##\s+{re.escape(heading)}\s*\n.*?(?=^##\s+|\Z)"
    if re.search(pattern, text):
        return re.sub(pattern, section, text, count=1)
    return text.rstrip() + "\n\n" + section


def remove_markdown_section(text: str, heading: str) -> str:
    pattern = rf"(?ms)^##\s+{re.escape(heading)}\s*\n.*?(?=^##\s+|\Z)"
    return re.sub(pattern, "", text, count=1).rstrip() + "\n"


def existing_identity_paths(root: Path) -> tuple[dict[int, Path], dict[str, Path]]:
    id_paths: dict[int, Path] = {}
    url_paths: dict[str, Path] = {}
    for path in (root / "sources").glob("*.md"):
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        rid = frontmatter_scalar(text, "raindrop_id")
        if rid and rid.isdigit():
            id_paths[int(rid)] = path
        for key in ("canonical_url", "url"):
            url = frontmatter_scalar(text, key)
            if url:
                url_paths[canonical_url(url)] = path
    return id_paths, url_paths


def minimal_item(item: dict[str, Any], collection_names: dict[int, str]) -> dict[str, Any]:
    cid = item_collection_id(item)
    return {
        "id": item.get("_id"),
        "title": item.get("title") or "",
        "url": item.get("link") or "",
        "domain": item.get("domain") or "",
        "created": item.get("created") or "",
        "last_update": item.get("lastUpdate") or "",
        "collection_id": cid,
        "collection_title": collection_names.get(cid or 0, ""),
        "tags": item.get("tags") or [],
        "note_present": bool(item.get("note")),
        "highlight_count": len(item.get("highlights") or []),
    }


def build_inventory(
    root: Path,
    excluded_titles: list[str],
    max_items: int | None,
) -> dict[str, Any]:
    require_rules(root)
    collections = fetch_collections()
    collection_names = {
        cid: collection_title(collection)
        for collection in collections
        if (cid := collection_id(collection)) is not None
    }
    collection_names.update({0: "All", -1: "Unsorted", -99: "Trash"})
    normalized_exclusions = {normalize_collection_title(title) for title in excluded_titles}
    excluded_ids = {
        cid
        for cid, title in collection_names.items()
        if normalize_collection_title(title) in normalized_exclusions
    }

    all_items = fetch_raindrops(0, max_items=max_items)
    existing_id_paths, existing_url_paths = existing_identity_paths(root)
    target_items = []
    excluded_items = []
    unknown_collection_items = []
    for item in all_items:
        cid = item_collection_id(item)
        if cid in excluded_ids:
            excluded_items.append(item)
        else:
            target_items.append(item)
        if cid is None:
            unknown_collection_items.append(item)

    by_collection: dict[str, dict[str, Any]] = {}
    for item in all_items:
        cid = item_collection_id(item)
        key = str(cid) if cid is not None else "unknown"
        entry = by_collection.setdefault(
            key,
            {
                "collection_id": cid,
                "collection_title": collection_names.get(cid or 0, ""),
                "fetched_count": 0,
                "target_count": 0,
                "excluded_count": 0,
            },
        )
        entry["fetched_count"] += 1
        if cid in excluded_ids:
            entry["excluded_count"] += 1
        else:
            entry["target_count"] += 1

    pending_target_items = [
        item
        for item in target_items
        if isinstance(item.get("_id"), int)
        and item["_id"] not in existing_id_paths
        and canonical_url(str(item.get("link") or "")) not in existing_url_paths
    ]

    return {
        "generated_at": utc_now().isoformat(),
        "wiki_root": str(root),
        "policy": {
            "source": "raindrop",
            "all_collection_id": 0,
            "excluded_collection_titles": excluded_titles,
            "excluded_collection_ids": sorted(excluded_ids),
            "write_back_enabled": False,
            "page_ingest_enabled": False,
        },
        "collections": [
            {
                "id": collection_id(collection),
                "title": collection_title(collection),
                "count": collection.get("count"),
                "public": collection.get("public"),
                "view": collection.get("view"),
            }
            for collection in sorted(collections, key=lambda c: (collection_title(c).casefold(), collection_id(c) or 0))
        ],
        "counts": {
            "fetched_from_all": len(all_items),
            "target_items": len(target_items),
            "excluded_items": len(excluded_items),
            "existing_source_notes_with_raindrop_id": len(existing_id_paths),
            "existing_source_note_canonical_urls": len(existing_url_paths),
            "pending_target_items": len(pending_target_items),
            "unknown_collection_items": len(unknown_collection_items),
            "max_items_applied": max_items,
        },
        "by_collection": sorted(
            by_collection.values(),
            key=lambda x: (str(x.get("collection_title") or "").casefold(), x.get("collection_id") or 0),
        ),
        "samples": {
            "newest_target_items": [
                minimal_item(item, collection_names) for item in pending_target_items[:20]
            ]
        },
    }


def write_inventory(root: Path, inventory: dict[str, Any]) -> tuple[Path, Path]:
    state_path = root / "_state" / "raindrop-inventory.json"
    state_path.write_text(json.dumps(inventory, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")

    timestamp = utc_now().strftime("%Y%m%dT%H%M%SZ")
    report_path = root / "_reports" / f"raindrop-inventory-{timestamp}.md"
    counts = inventory["counts"]
    policy = inventory["policy"]
    lines = [
        f"# Raindrop Inventory - {inventory['generated_at']}",
        "",
        "## Policy",
        "",
        f"- Source collection: all bookmarks (`{policy['all_collection_id']}`)",
        f"- Excluded collection titles: {', '.join(policy['excluded_collection_titles']) or 'none'}",
        f"- Excluded collection IDs: {policy['excluded_collection_ids']}",
        "- Write-back: disabled",
        "- Page ingestion: disabled",
        "",
        "## Counts",
        "",
        f"- Fetched from all: {counts['fetched_from_all']}",
        f"- Target items: {counts['target_items']}",
        f"- Excluded items: {counts['excluded_items']}",
        f"- Existing source notes with Raindrop ID: {counts['existing_source_notes_with_raindrop_id']}",
        f"- Existing source note canonical URLs: {counts['existing_source_note_canonical_urls']}",
        f"- Pending target items: {counts['pending_target_items']}",
        f"- Unknown collection items: {counts['unknown_collection_items']}",
        "",
        "## Collection Breakdown",
        "",
        "| Collection | ID | Fetched | Target | Excluded |",
        "| --- | ---: | ---: | ---: | ---: |",
    ]
    for entry in inventory["by_collection"]:
        title = entry.get("collection_title") or "Unknown"
        lines.append(
            f"| {title} | {entry.get('collection_id')} | {entry['fetched_count']} | {entry['target_count']} | {entry['excluded_count']} |"
        )

    lines.extend(["", "## Newest Target Samples", ""])
    for item in inventory["samples"]["newest_target_items"]:
        title = str(item["title"] or item["url"] or item["id"]).replace("|", "\\|")
        lines.append(f"- {title} ({item['collection_title']}, Raindrop {item['id']})")
    if not inventory["samples"]["newest_target_items"]:
        lines.append("- None")

    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return state_path, report_path


def target_raindrop_items(
    root: Path,
    excluded_titles: list[str],
    max_items: int | None = None,
) -> tuple[list[dict[str, Any]], dict[int, str], list[int]]:
    require_rules(root)
    collections = fetch_collections()
    collection_names = {
        cid: collection_title(collection)
        for collection in collections
        if (cid := collection_id(collection)) is not None
    }
    collection_names.update({0: "All", -1: "Unsorted", -99: "Trash"})
    normalized_exclusions = {normalize_collection_title(title) for title in excluded_titles}
    excluded_ids = sorted(
        cid
        for cid, title in collection_names.items()
        if normalize_collection_title(title) in normalized_exclusions
    )
    existing_ids, existing_urls = existing_identity_paths(root)
    all_items = fetch_raindrops(0, max_items=max_items)
    target_items = [
        item
        for item in all_items
        if item_collection_id(item) not in set(excluded_ids)
        and isinstance(item.get("_id"), int)
        and item["_id"] not in existing_ids
        and canonical_url(str(item.get("link") or "")) not in existing_urls
    ]
    return target_items, collection_names, excluded_ids


def source_path_for_item(root: Path, item: dict[str, Any], title: str) -> Path:
    created = str(item.get("created") or today())
    date_part = created[:10] if re.match(r"\d{4}-\d{2}-\d{2}", created) else today()
    url = str(item.get("link") or "")
    domain = domain_from_url(url)
    base = safe_slug(f"{domain}-{title or item.get('title') or item.get('_id')}")
    candidate = root / "sources" / f"{date_part}-{base}.md"
    if not candidate.exists():
        return candidate
    return root / "sources" / f"{date_part}-{base}-{item.get('_id')}.md"


def frontmatter_lines(fields: dict[str, Any]) -> list[str]:
    lines = ["---"]
    for key, value in fields.items():
        lines.append(f"{key}: {yaml_value(value)}")
    lines.append("---")
    return lines


def write_source_note(
    root: Path,
    item: dict[str, Any],
    collection_names: dict[int, str],
) -> dict[str, Any]:
    url = str(item.get("link") or "")
    normalized_url = canonical_url(url) if url else ""
    extraction = extract_url(url) if url else {
        "source_type": "reference",
        "ingest_status": "blocked",
        "title": "",
        "summary": "Raindrop item has no URL.",
        "extract": "",
        "error": "missing URL",
    }
    title = clean_text(extraction.get("title") or item.get("title") or url or f"Raindrop {item.get('_id')}")
    item_excerpt = clean_text(item.get("excerpt") or "", 700)
    terminal_status = str(extraction.get("ingest_status") or "")
    if terminal_status in {"blocked", "gone"} and item_excerpt:
        summary = f"{item_excerpt}\n\nFetch {terminal_status} during first-pass ingest: {extraction.get('error')}"
    else:
        summary = clean_text(extraction.get("summary") or item_excerpt or "Reference saved without extracted summary.", 1400)
    extract = clean_text(extraction.get("extract") or item.get("excerpt") or "", 2600)
    digest_material = "\n".join([url, title, summary, extract])
    digest = hashlib.sha256(digest_material.encode("utf-8")).hexdigest()[:16]
    cid = item_collection_id(item)
    path = source_path_for_item(root, item, title)
    slug = path.stem
    extra = extraction.get("extra") if isinstance(extraction.get("extra"), dict) else {}
    published = iso_datetime(extraction.get("published"))
    source_modified = iso_datetime(extraction.get("modified"))
    saved_at = iso_datetime(item.get("created"))
    ingested_at = utc_now().isoformat().replace("+00:00", "Z")
    save_age = age_days(published, saved_at)
    ingest_age = age_days(published, ingested_at)

    fields: dict[str, Any] = {
        "type": "source",
        "url": url,
        "canonical_url": normalized_url,
        "title": title,
        "published": published,
        "source_modified": source_modified,
        "source_type": extraction.get("source_type") or "reference",
        "ingest_status": extraction.get("ingest_status") or "reference",
        "created": today(),
        "updated": today(),
        "raindrop_id": item.get("_id"),
        "raindrop_collection_at_ingest": collection_names.get(cid or 0, ""),
        "raindrop_created": item.get("created") or "",
        "saved_at": saved_at,
        "raindrop_tags": item.get("tags") or [],
        "agent_attention": [],
        "agent_attention_reason": "",
        "source_facets": [],
        "source_entities": [],
        "raindrop_note_present": bool(item.get("note")),
        "content_digest": digest,
        "extracted_at": ingested_at,
        "ingested_at": ingested_at,
        "source_age_days_at_save": save_age if save_age is not None else "",
        "source_age_days_at_ingest": ingest_age if ingest_age is not None else "",
        "extractor": "llm-wiki/wiki.py",
    }
    if extraction.get("error"):
        fields["blocker"] = extraction["error"]
    if extraction.get("ingest_status") == "gone":
        fields["gone_reason"] = extraction.get("error") or "Source appears deleted or unavailable."
    for key, value in extra.items():
        fields[key] = value

    lines = frontmatter_lines(fields)
    lines.extend(
        [
            "",
            f"# {title}",
            "",
            "## Summary",
            "",
            summary,
            "",
        ]
    )
    if extract:
        lines.extend(["## Key Extract", "", extract, ""])
    if extraction.get("error"):
        lines.extend(["## Blocker", "", str(extraction["error"]), ""])
    lines.extend(
        [
            "## Ingestion Notes",
            "",
            f"- Raindrop collection at ingest: {collection_names.get(cid or 0, '')}",
            f"- Raindrop ID: {item.get('_id')}",
            f"- Raindrop note present: {'yes' if item.get('note') else 'no'}",
            "- Topic synthesis: pending agent review.",
            "",
        ]
    )
    path.write_text("\n".join(lines), encoding="utf-8")
    return {
        "raindrop_id": item.get("_id"),
        "title": title,
        "url": url,
        "path": str(path),
        "slug": slug,
        "status": fields["ingest_status"],
        "source_type": fields["source_type"],
        "blocker": fields.get("blocker", ""),
    }


def recover_source_note(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    url = frontmatter_scalar(text, "url") or frontmatter_scalar(text, "canonical_url") or ""
    rid = frontmatter_scalar(text, "raindrop_id")
    if not url:
        return {"path": str(path), "slug": path.stem, "status": "skipped", "reason": "missing url"}

    previous_status = frontmatter_scalar(text, "ingest_status") or ""
    previous_blocker = frontmatter_scalar(text, "blocker") or ""
    result = recover_url(url, rid if rid and rid.isdigit() else None)
    recovered_at = utc_now().isoformat().replace("+00:00", "Z")
    result_status = result.get("ingest_status") or "reference"
    updates: dict[str, Any] = {
        "source_type": result.get("source_type") or "reference",
        "ingest_status": result_status,
        "recovered_at": recovered_at,
        "recovery_method": result.get("method") or "",
        "recovery_attempts": result.get("attempts") or [],
        "updated": today(),
    }
    if previous_blocker:
        updates["previous_blocker"] = previous_blocker
    if result.get("error"):
        updates["blocker"] = result["error"]
    else:
        updates["blocker"] = ""
    if result_status == "gone":
        updates["gone_at"] = recovered_at
        updates["gone_reason"] = result.get("error") or "Source appears deleted or unavailable."
    if result.get("title") and not frontmatter_scalar(text, "title"):
        updates["title"] = result["title"]
    next_text = update_frontmatter(text, updates, force=True)
    summary = clean_text(str(result.get("summary") or ""), 1800)
    extract = clean_text(str(result.get("extract") or ""), 3600)
    if summary:
        next_text = replace_markdown_section(next_text, "Summary", summary)
    if extract:
        next_text = replace_markdown_section(next_text, "Key Extract", extract)
    if result.get("error"):
        next_text = replace_markdown_section(next_text, "Blocker", str(result["error"]))
    elif previous_status == "blocked":
        next_text = remove_markdown_section(next_text, "Blocker")
    next_text = replace_markdown_section(
        next_text,
        "Recovery Notes",
        "\n".join(
            [
                f"- Recovered at: {recovered_at}",
                f"- Recovery method: {result.get('method') or 'none'}",
                f"- Attempts: {', '.join(result.get('attempts') or [])}",
                f"- Previous status: {previous_status or 'unknown'}",
            ]
        ),
    )
    if next_text != text:
        path.write_text(next_text, encoding="utf-8")
    return {
        "path": str(path),
        "slug": path.stem,
        "url": url,
        "previous_status": previous_status,
        "status": result_status,
        "source_type": result.get("source_type") or "reference",
        "method": result.get("method") or "",
        "attempts": result.get("attempts") or [],
        "errors": result.get("errors") or [],
    }


def note_title(path: Path) -> str:
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return path.stem
    match = re.search(r"(?m)^#\s+(.+)$", text)
    return clean_text(match.group(1), 140) if match else path.stem


def markdown_section(text: str, heading: str, limit: int = 520) -> str:
    pattern = rf"(?ms)^##\s+{re.escape(heading)}\s*\n(.*?)(?=^##\s+|\Z)"
    match = re.search(pattern, text)
    if not match:
        return ""
    section = re.sub(r"\n#+\s+", "\n", match.group(1))
    return clean_text(section, limit)


def source_brief(text: str, limit: int = 320) -> str:
    summary = markdown_section(text, "Summary", limit=2200)
    if not summary:
        return ""
    paragraphs = [
        clean_text(re.sub(r"\s*\n+\s*", " ", paragraph))
        for paragraph in re.split(r"\n\s*\n", summary)
    ]
    candidates = [paragraph for paragraph in paragraphs[:8] if len(paragraph) >= 80]
    if not candidates:
        return clean_text(re.sub(r"\s*\n+\s*", " ", summary), limit)
    chosen = max(candidates, key=len)
    return clean_text(chosen, limit)


MODEL_ENTITY_PATTERNS: tuple[tuple[str, str], ...] = (
    ("Qwen3-TTS", r"\bqwen3[-\s]?tts\b"),
    ("Qwen3.6", r"\bqwen3[.\-]?6\b"),
    ("Qwen3-VL-Embedding-8B", r"\bqwen3[-\s]?vl[-\s]?embedding[-\s]?8b\b"),
    ("Gemma 4", r"\bgemma\s*4\b"),
    ("MedMO-4B", r"\bmedmo[-\s]?4b\b"),
    ("GLM-OCR", r"\bglm[-\s]?ocr\b"),
    ("Cohere Transcribe", r"\bcohere\s+transcribe\b"),
    ("VibeVoice-ASR", r"\bvibevoice[-\s]?asr\b"),
    ("Whisper", r"\bwhisper\b"),
    ("OpenAI voice models", r"\bopenai\b.*\bvoice\b|\bvoice intelligence\b"),
    ("Microsoft ASR 7B", r"\bmicrosoft\b.*\b7b\b.*\b(transcribes|transcription|audio|asr)\b"),
    ("Quranic Arabic speech model", r"\bquran(ic)?\b.*\b(speech|recitation|transcrib|whisper|arabic)\b"),
    ("Omnilingual ASR", r"\bomnilingual[-\s]?asr\b"),
)


def source_classification_text(text: str) -> str:
    fields = parse_frontmatter_map(text)
    generated_fields = {
        "agent_attention",
        "agent_attention_reason",
        "source_facets",
        "source_entities",
        "updated",
    }
    frontmatter_values = " ".join(
        value for key, value in fields.items() if key not in generated_fields
    )
    summary = markdown_section(text, "Summary", limit=1800)
    extract = markdown_section(text, "Key Extract", limit=1600)
    return clean_text(" ".join([frontmatter_values, summary, extract]), 6000)


def infer_source_facets(text: str) -> tuple[list[str], list[str]]:
    fields = parse_frontmatter_map(text)
    surface = clean_text(
        " ".join(
            [
                fields.get("url", ""),
                fields.get("canonical_url", ""),
                fields.get("title", ""),
            ]
        ),
        1200,
    ).casefold()
    haystack = source_classification_text(text).casefold()
    facets: set[str] = set()
    entities: set[str] = set()

    for entity, pattern in MODEL_ENTITY_PATTERNS:
        if re.search(pattern, haystack, flags=re.I):
            entities.add(entity)

    hf_model_page = "huggingface.co/" in surface and "/blog/" not in surface
    strong_modelish = bool(entities) or any(
        marker in haystack
        for marker in (
            " language model",
            " multimodal model",
            " open-source model",
            " open source model",
            " parameter model",
            " foundation model",
            " model card",
            " ai model",
            " llm model",
            " asr",
            " tts",
            " embedding model",
            " speech recognition",
            " text-to-speech",
            " transcribe",
            " transcription model",
            " ocr model",
            " optical character recognition model",
        )
    ) or hf_model_page
    guideish = bool(
        re.search(
            r"\b(guide|documentation|docs|fine[- ]tuning|train|training|how to run|tutorial)\b",
            surface,
        )
    )
    releaseish = bool(
        re.search(
            r"\b(introducing|officially live|open[- ]sourced|released|latest|new models?|models? to date|state-of-the-art|meet|is here|launched?|launch)\b",
            surface,
        )
    ) or (strong_modelish and any(marker in surface for marker in ("mlx", "quant", "model card")))
    model_project_page = bool(entities) and not guideish and any(
        marker in surface
        for marker in (
            "huggingface.co/",
            "github.com/",
            "blog.google/",
            "openai.com/",
            "cohere.com/",
        )
    )

    if strong_modelish and (releaseish or model_project_page):
        facets.add("model-release")
        facets.add("ai-release")
    elif strong_modelish and hf_model_page:
        facets.add("model-release")
        facets.add("ai-release")
    if strong_modelish and guideish:
        facets.add("model-guide")
    if strong_modelish and (
        any(marker in surface for marker in ("mlx", "quant", "open-source", "open source", "huggingface.co/", "unsloth"))
        or any(marker in haystack for marker in ("run local", "local llm", "local model", "mlx", "quantized", "quantization"))
    ):
        facets.add("local-model")
    if strong_modelish and any(
        marker in haystack
        for marker in (
            "tts",
            "asr",
            "text-to-speech",
            "speech recognition",
            "transcrib",
            "transcription",
            "whisper",
            "audio model",
            "voice intelligence",
            "voice model",
            "recitation",
        )
    ):
        facets.add("voice-audio")
    if strong_modelish and any(
        marker in haystack
        for marker in (
            "ocr",
            "vision-language",
            "image model",
            "medical image",
            "medical images",
            "x-ray",
            "multimodal",
            "document extraction",
            "vl-embedding",
        )
    ):
        facets.add("vision-document-ai")
    if any(marker in haystack for marker in ("embedding", "retrieval", "rag", "vector")):
        facets.add("embedding-retrieval")
    if any(marker in haystack for marker in ("benchmark", "bench", "eval", "accuracy", "performance")) and strong_modelish:
        facets.add("model-eval")

    return sorted(facets), sorted(entities)


def date_display(value: Any) -> str:
    parsed = parse_datetime(value)
    if parsed is None:
        return "unknown"
    return parsed.date().isoformat()


def slug_date(path: Path) -> str:
    match = re.match(r"^(\d{4}-\d{2}-\d{2})-", path.stem)
    return match.group(1) if match else ""


def source_recency_value(text: str, path: Path | None = None) -> str:
    return frontmatter_scalar(text, "source_modified") or frontmatter_scalar(text, "published") or ""


def intake_recency_value(text: str, path: Path | None = None) -> str:
    value = (
        frontmatter_scalar(text, "saved_at")
        or frontmatter_scalar(text, "raindrop_created")
        or frontmatter_scalar(text, "ingested_at")
        or frontmatter_scalar(text, "extracted_at")
        or frontmatter_scalar(text, "created")
        or ""
    )
    if not value and path is not None:
        value = slug_date(path)
    return value


def source_recency_timestamp(text: str, path: Path | None = None) -> float:
    return sort_timestamp(source_recency_value(text, path))


def intake_recency_timestamp(text: str, path: Path | None = None) -> float:
    return sort_timestamp(intake_recency_value(text, path))


def source_priority_key(path: Path) -> tuple[float, float, str]:
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        text = ""
    return (
        -intake_recency_timestamp(text, path),
        -source_recency_timestamp(text, path),
        note_title(path).casefold(),
    )


def topic_links_by_source(root: Path) -> dict[str, list[str]]:
    by_source: dict[str, list[str]] = {}
    source_slugs = {path.stem for path in (root / "sources").glob("*.md")}
    for topic_path in sorted((root / "topics").glob("*.md")):
        text = topic_path.read_text(encoding="utf-8")
        for slug in topic_source_links(text, source_slugs):
            by_source.setdefault(slug, []).append(topic_path.stem)
    return by_source


def rebuild_index(root: Path) -> Path:
    source_paths = sorted((root / "sources").glob("*.md"), key=source_priority_key)
    topic_paths = sorted((root / "topics").glob("*.md"))
    view_paths = sorted((root / "_views").glob("*.md"))
    lines = [
        "---",
        "type: index",
        f"updated: {yaml_value(utc_now().isoformat())}",
        f"page_count: {len(source_paths) + len(topic_paths) + len(view_paths)}",
        "---",
        "",
        "# Wiki Index",
        "",
        f"## Sources ({len(source_paths)})",
        "",
        "Sources are sorted by intake recency, with source recency shown for context.",
        "",
    ]
    for path in source_paths:
        text = path.read_text(encoding="utf-8")
        status = frontmatter_scalar(text, "ingest_status") or "unknown"
        intake = date_display(intake_recency_value(text, path))
        source = date_display(source_recency_value(text, path))
        lines.append(
            f"- [[{path.stem}]] - {markdown_escape(note_title(path))} "
            f"(intake {intake}; source {source}; `{status}`)"
        )
    lines.extend(["", f"## Topics ({len(topic_paths)})", ""])
    for path in topic_paths:
        lines.append(f"- [[{path.stem}]] - {markdown_escape(note_title(path))}")
    lines.extend(["", f"## Views ({len(view_paths)})", ""])
    for path in view_paths:
        lines.append(f"- [[{path.stem}]] - {markdown_escape(note_title(path))}")
    index_path = root / "index.md"
    index_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return index_path


def append_log(root: Path, operation: str, note_type: str, slug: str, description: str) -> None:
    log_path = root / "log.md"
    if not log_path.exists():
        log_path.write_text("# Wiki Log\n", encoding="utf-8")
    with log_path.open("a", encoding="utf-8") as handle:
        handle.write(f"{utc_now().isoformat()} | {operation} | {note_type} | {slug} | {description}\n")


def write_ingest_report(root: Path, results: list[dict[str, Any]], excluded_ids: list[int]) -> Path:
    timestamp = utc_now().strftime("%Y%m%dT%H%M%SZ")
    report_path = root / "_reports" / f"raindrop-ingest-{timestamp}.md"
    counts: dict[str, int] = {}
    for result in results:
        counts[str(result["status"])] = counts.get(str(result["status"]), 0) + 1

    lines = [
        f"# Raindrop Ingest - {utc_now().isoformat()}",
        "",
        "## Policy",
        "",
        f"- Excluded collection IDs: {excluded_ids}",
        "- Raindrop write-back: disabled",
        "- Topic synthesis: pending agent review",
        "",
        "## Counts",
        "",
    ]
    for status, count in sorted(counts.items()):
        lines.append(f"- {status}: {count}")
    if not counts:
        lines.append("- No source notes created")
    lines.extend(["", "## Sources", ""])
    for result in results:
        lines.append(f"- {result['status']} - [[{result['slug']}]] - {markdown_escape(result['title'])}")
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return report_path


def write_recovery_report(root: Path, results: list[dict[str, Any]]) -> Path:
    timestamp = utc_now().strftime("%Y%m%dT%H%M%SZ")
    report_path = root / "_reports" / f"source-recovery-{timestamp}.md"
    counts: dict[str, int] = {}
    for result in results:
        counts[str(result.get("status") or "unknown")] = counts.get(str(result.get("status") or "unknown"), 0) + 1
    lines = [
        f"# Source Recovery - {utc_now().isoformat()}",
        "",
        "## Counts",
        "",
    ]
    for status, count in sorted(counts.items()):
        lines.append(f"- {status}: {count}")
    if not counts:
        lines.append("- No sources recovered")
    lines.extend(["", "## Results", ""])
    for result in results:
        lines.append(
            f"- {result.get('status')} / {result.get('method') or 'none'} - [[{result['slug']}]]"
        )
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return report_path


def write_facet_classification_report(root: Path, rows: list[dict[str, Any]]) -> Path:
    timestamp = utc_now().strftime("%Y%m%dT%H%M%SZ")
    report_path = root / "_reports" / f"source-facet-classification-{timestamp}.md"
    lines = [
        f"# Source Facet Classification - {utc_now().isoformat()}",
        "",
        f"- Updated sources: {sum(1 for row in rows if row.get('updated'))}",
        f"- Reviewed sources: {len(rows)}",
        "",
        "## Updated",
        "",
    ]
    updated_rows = [row for row in rows if row.get("updated")]
    if not updated_rows:
        lines.append("- None")
    for row in updated_rows:
        facets = ", ".join(f"`{facet}`" for facet in row.get("source_facets", [])) or "none"
        entities = ", ".join(f"`{entity}`" for entity in row.get("source_entities", [])) or "none"
        lines.append(f"- [[{row['slug']}]] - facets: {facets}; entities: {entities}")
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return report_path


def processed_unsorted_source_rows(
    root: Path,
    include_reference: bool = True,
    include_gone: bool = True,
    source_collection: int = -1,
) -> list[dict[str, Any]]:
    allowed_statuses = {"ingested"}
    if include_reference:
        allowed_statuses.add("reference")
    if include_gone:
        allowed_statuses.add("gone")
    by_id: dict[int, tuple[Path, str, str, str, str]] = {}
    by_url: dict[str, tuple[Path, str, str, str, str]] = {}
    for path in sorted((root / "sources").glob("*.md")):
        text = path.read_text(encoding="utf-8")
        status = frontmatter_scalar(text, "ingest_status") or ""
        if status not in allowed_statuses:
            continue
        title = frontmatter_scalar(text, "title") or note_title(path)
        source_type = frontmatter_scalar(text, "source_type") or ""
        url = frontmatter_scalar(text, "canonical_url") or frontmatter_scalar(text, "url") or ""
        payload = (path, title, status, source_type, url)
        rid = frontmatter_scalar(text, "raindrop_id")
        if rid and rid.isdigit():
            by_id[int(rid)] = payload
        if url:
            by_url[canonical_url(url)] = payload

    rows: list[dict[str, Any]] = []
    seen_ids: set[int] = set()
    for item in fetch_raindrops(source_collection):
        rid = item.get("_id")
        if not isinstance(rid, int) or rid in seen_ids:
            continue
        payload = by_id.get(rid) or by_url.get(canonical_url(str(item.get("link") or "")))
        if payload is None:
            continue
        seen_ids.add(rid)
        path, title, status, source_type, url = payload
        rows.append(
            {
                "path": str(path),
                "slug": path.stem,
                "raindrop_id": rid,
                "title": title,
                "status": status,
                "source_type": source_type,
                "url": url,
            }
        )
    return rows


def write_move_report(
    root: Path,
    rows: list[dict[str, Any]],
    target_title: str,
    applied: bool,
    response: dict[str, Any] | None,
    allowed_statuses: set[str],
) -> Path:
    timestamp = utc_now().strftime("%Y%m%dT%H%M%SZ")
    report_path = root / "_reports" / f"raindrop-move-processed-{timestamp}.md"
    lines = [
        f"# Raindrop Move Processed - {utc_now().isoformat()}",
        "",
        "## Policy",
        "",
        "- Source collection: Unsorted",
        f"- Target collection: {target_title}",
        f"- Applied: {'yes' if applied else 'no'}",
        "- Selection: source notes with `ingest_status` of "
        + ", ".join(f"`{status}`" for status in sorted(allowed_statuses)),
        "",
        "## Counts",
        "",
        f"- Candidate items: {len(rows)}",
        "",
        "## Items",
        "",
    ]
    if not rows:
        lines.append("- None")
    for row in rows:
        lines.append(f"- {row['status']} - Raindrop {row['raindrop_id']} - [[{row['slug']}]] - {markdown_escape(row['title'])}")
    if response is not None:
        lines.extend(["", "## Raindrop Response", "", "```json", json.dumps(response, indent=2, ensure_ascii=False, sort_keys=True), "```"])
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return report_path


def write_tag_report(root: Path, rows: list[dict[str, Any]], tags: list[str], collection: int) -> tuple[Path, Path]:
    rows = dedupe_rows_by_slug(rows)
    timestamp = utc_now().strftime("%Y%m%dT%H%M%SZ")
    state_path = root / "_state" / "raindrop-tag-actions.json"
    report_path = root / "_reports" / f"raindrop-tags-{timestamp}.md"
    state = {
        "generated_at": utc_now().isoformat(),
        "collection": collection,
        "tags": tags,
        "count": len(rows),
        "items": rows,
    }
    state_path.write_text(json.dumps(state, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")

    lines = [
        f"# Raindrop Tagged Actions - {utc_now().isoformat()}",
        "",
        "## Policy",
        "",
        "- Source: Raindrop metadata",
        "- Raindrop write-back: disabled",
        f"- Collection: {collection}",
        f"- Tags: {', '.join(tags)}",
        "",
        "## Counts",
        "",
    ]
    for tag in tags:
        count = sum(1 for row in rows if tag in row["tags"])
        lines.append(f"- {tag}: {count}")
    lines.extend(["", "## Items", ""])
    if not rows:
        lines.append("- No matching tagged items found.")
    for tag in tags:
        tagged = [row for row in rows if tag in row["tags"]]
        if not tagged:
            continue
        lines.extend([f"### {tag}", ""])
        for row in tagged:
            lines.append(f"- [[{row['slug']}]] - {markdown_escape(row['title'])}")
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return state_path, report_path


def dedupe_rows_by_slug(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    by_slug: dict[str, dict[str, Any]] = {}
    for row in rows:
        slug = str(row.get("slug") or "")
        if not slug:
            continue
        existing = by_slug.get(slug)
        if existing is None:
            copied = dict(row)
            copied["tags"] = sorted({str(tag) for tag in row.get("tags", [])})
            by_slug[slug] = copied
            continue
        existing["tags"] = sorted({*existing.get("tags", []), *(str(tag) for tag in row.get("tags", []))})
    return list(by_slug.values())


def action_score(tags: list[str]) -> int:
    tag_set = {tag.casefold() for tag in tags}
    score = 0
    if "interesting-to-read" in tag_set:
        score += 400
    if "test-for-agent" in tag_set:
        score += 200
    if "test-for-me" in tag_set:
        score += 100
    return score


def sort_timestamp(value: Any) -> float:
    parsed = parse_datetime(value)
    if parsed is None:
        return 0.0
    return parsed.timestamp()


def scan_action_sources(root: Path, tags: list[str]) -> list[dict[str, Any]]:
    wanted = {tag.casefold() for tag in tags}
    topics_by_source = topic_links_by_source(root)
    rows: list[dict[str, Any]] = []
    for path in sorted((root / "sources").glob("*.md")):
        text = path.read_text(encoding="utf-8")
        human_tags = sorted(frontmatter_list(text, "raindrop_tags"))
        agent_attention = sorted(frontmatter_list(text, "agent_attention"))
        attention_signals = sorted({*human_tags, *agent_attention})
        source_facets = sorted(frontmatter_list(text, "source_facets"))
        source_entities = sorted(frontmatter_list(text, "source_entities"))
        if wanted and not ({tag.casefold() for tag in attention_signals} & wanted):
            continue
        ingest_status = frontmatter_scalar(text, "ingest_status") or ""
        if ingest_status == "gone":
            continue
        title = frontmatter_scalar(text, "title") or note_title(path)
        saved_at = frontmatter_scalar(text, "saved_at") or frontmatter_scalar(text, "raindrop_created") or ""
        published = frontmatter_scalar(text, "published") or ""
        source_recency = source_recency_value(text, path)
        intake_recency = intake_recency_value(text, path)
        summary = source_brief(text)
        rows.append(
            {
                "slug": path.stem,
                "path": str(path),
                "title": title,
                "url": frontmatter_scalar(text, "canonical_url") or frontmatter_scalar(text, "url") or "",
                "tags": attention_signals,
                "raindrop_tags": human_tags,
                "agent_attention": agent_attention,
                "agent_attention_reason": frontmatter_scalar(text, "agent_attention_reason") or "",
                "source_facets": source_facets,
                "source_entities": source_entities,
                "source_type": frontmatter_scalar(text, "source_type") or "",
                "ingest_status": ingest_status,
                "published": published,
                "saved_at": saved_at,
                "source_recency": source_recency,
                "intake_recency": intake_recency,
                "source_age_days_at_save": frontmatter_scalar(text, "source_age_days_at_save") or "",
                "raindrop_collection_current": frontmatter_scalar(text, "raindrop_collection_current")
                or frontmatter_scalar(text, "raindrop_collection_at_ingest")
                or "",
                "topics": topics_by_source.get(path.stem, []),
                "summary": summary,
                "score": action_score(attention_signals),
            }
        )
    rows.sort(
        key=lambda row: (
            -sort_timestamp(row.get("intake_recency")),
            -sort_timestamp(row.get("source_recency")),
            -int(row.get("score") or 0),
            str(row.get("title") or "").casefold(),
        )
    )
    return rows


def write_experiment_scan(root: Path, tags: list[str]) -> tuple[Path, Path, list[dict[str, Any]]]:
    (root / "_views").mkdir(parents=True, exist_ok=True)
    (root / "_state").mkdir(parents=True, exist_ok=True)
    rows = scan_action_sources(root, tags)
    generated = utc_now().isoformat()
    state_path = root / "_state" / "experiment-scan.json"
    view_path = root / "_views" / "experiment-scan.md"
    counts = {tag: sum(1 for row in rows if tag in row["tags"]) for tag in tags}
    state = {
        "generated_at": generated,
        "tags": tags,
        "item_count": len(rows),
        "counts": counts,
        "items": rows,
    }
    state_path.write_text(json.dumps(state, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")

    command = "~/.codex/skills/llm-wiki/scripts/wiki.py actions scan"
    if tags:
        command += " " + " ".join(f"--signal {tag}" for tag in tags)
    lines = [
        "---",
        "type: view",
        "view: experiment-scan",
        f"generated: {yaml_value(generated)}",
        f"tags: {yaml_value(tags)}",
        f"item_count: {len(rows)}",
        "---",
        "",
        "# Experiment Scan",
        "",
        "This is a generated scan view of source notes tagged for testing, setup work, or deliberate reading. It is not ontology.",
        "",
        "Regenerate it with:",
        "",
        "```bash",
        command,
        "```",
        "",
        "## Counts",
        "",
        "| Signal | Items |",
        "| --- | ---: |",
    ]
    for tag in tags:
        lines.append(f"| `{tag}` | {counts[tag]} |")
    lines.extend(["", "## Scan List", ""])
    if not rows:
        lines.append("No matching sources found.")
    for index, row in enumerate(rows, start=1):
        topics = ", ".join(f"[[{topic}]]" for topic in row["topics"]) or "none"
        signal_text = ", ".join(f"`{tag}`" for tag in row["tags"]) or "none"
        human_text = ", ".join(f"`{tag}`" for tag in row.get("raindrop_tags", [])) or "none"
        agent_text = ", ".join(f"`{tag}`" for tag in row.get("agent_attention", [])) or "none"
        facets_text = ", ".join(f"`{facet}`" for facet in row.get("source_facets", [])) or "none"
        entities_text = ", ".join(f"`{entity}`" for entity in row.get("source_entities", [])) or "none"
        age = str(row.get("source_age_days_at_save") or "").strip()
        age_text = f"{age} days old at save" if age not in {"", "None"} else "source date unknown at save"
        url = str(row.get("url") or "")
        lines.extend(
            [
                f"### {index:03d}. {markdown_escape(str(row['title']))}",
                "",
                f"- Source: [[{row['slug']}]]",
                f"- Signals: {signal_text}",
                f"- Human tags: {human_text}",
                f"- Agent attention: {agent_text}",
                f"- Facets: {facets_text}",
                f"- Entities: {entities_text}",
                f"- Status: `{row['ingest_status']}` / `{row['source_type']}`",
                f"- Dates: intake {date_display(row.get('intake_recency'))}, source {date_display(row.get('source_recency'))}, published {date_display(row.get('published'))}, saved {date_display(row.get('saved_at'))}, {age_text}",
                f"- Collection: {markdown_escape(str(row.get('raindrop_collection_current') or 'unknown'))}",
                f"- Topics: {topics}",
            ]
        )
        reason = str(row.get("agent_attention_reason") or "").strip()
        if reason:
            lines.append(f"- Agent reason: {markdown_escape(reason)}")
        if url:
            lines.append(f"- URL: {url}")
        summary = str(row.get("summary") or "").strip()
        if summary:
            lines.extend(["", f"Brief: {summary}"])
        lines.append("")
    view_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    append_log(root, "maintain", "view", "experiment-scan", f"Generated experiment scan with {len(rows)} items")
    return state_path, view_path, rows


def recent_source_rows(root: Path, limit: int, include_gone: bool = False) -> list[dict[str, Any]]:
    topics_by_source = topic_links_by_source(root)
    rows: list[dict[str, Any]] = []
    for path in sorted((root / "sources").glob("*.md")):
        text = path.read_text(encoding="utf-8")
        status = frontmatter_scalar(text, "ingest_status") or ""
        if status == "gone" and not include_gone:
            continue
        human_tags = sorted(frontmatter_list(text, "raindrop_tags"))
        agent_attention = sorted(frontmatter_list(text, "agent_attention"))
        signals = sorted({*human_tags, *agent_attention})
        source_facets = sorted(frontmatter_list(text, "source_facets"))
        source_entities = sorted(frontmatter_list(text, "source_entities"))
        source_recency = source_recency_value(text, path)
        intake_recency = intake_recency_value(text, path)
        rows.append(
            {
                "slug": path.stem,
                "path": str(path),
                "title": frontmatter_scalar(text, "title") or note_title(path),
                "url": frontmatter_scalar(text, "canonical_url") or frontmatter_scalar(text, "url") or "",
                "status": status,
                "source_type": frontmatter_scalar(text, "source_type") or "",
                "published": frontmatter_scalar(text, "published") or "",
                "saved_at": frontmatter_scalar(text, "saved_at") or frontmatter_scalar(text, "raindrop_created") or "",
                "source_recency": source_recency,
                "intake_recency": intake_recency,
                "signals": signals,
                "source_facets": source_facets,
                "source_entities": source_entities,
                "raindrop_collection_current": frontmatter_scalar(text, "raindrop_collection_current")
                or frontmatter_scalar(text, "raindrop_collection_at_ingest")
                or "",
                "topics": topics_by_source.get(path.stem, []),
                "summary": source_brief(text),
            }
        )
    rows.sort(
        key=lambda row: (
            -sort_timestamp(row.get("intake_recency")),
            -sort_timestamp(row.get("source_recency")),
            str(row.get("title") or "").casefold(),
        )
    )
    return rows[:limit] if limit else rows


def write_recent_sources(root: Path, limit: int = DEFAULT_RECENT_LIMIT, include_gone: bool = False) -> tuple[Path, Path, list[dict[str, Any]]]:
    (root / "_views").mkdir(parents=True, exist_ok=True)
    (root / "_state").mkdir(parents=True, exist_ok=True)
    rows = recent_source_rows(root, limit=limit, include_gone=include_gone)
    generated = utc_now().isoformat()
    state_path = root / "_state" / "recent-sources.json"
    view_path = root / "_views" / "recent-sources.md"
    state = {
        "generated_at": generated,
        "limit": limit,
        "include_gone": include_gone,
        "item_count": len(rows),
        "items": rows,
    }
    state_path.write_text(json.dumps(state, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")

    command = f"~/.codex/skills/llm-wiki/scripts/wiki.py actions recent --limit {limit}"
    if include_gone:
        command += " --include-gone"
    lines = [
        "---",
        "type: view",
        "view: recent-sources",
        f"generated: {yaml_value(generated)}",
        f"limit: {limit}",
        f"include_gone: {yaml_value(include_gone)}",
        f"item_count: {len(rows)}",
        "---",
        "",
        "# Recent Sources",
        "",
        "This generated view is the default recency-biased review surface. It is sorted by intake recency first, then source recency. It is not ontology.",
        "",
        "Regenerate it with:",
        "",
        "```bash",
        command,
        "```",
        "",
        "## Sources",
        "",
    ]
    if not rows:
        lines.append("No source notes found.")
    for index, row in enumerate(rows, start=1):
        topics = ", ".join(f"[[{topic}]]" for topic in row["topics"]) or "none"
        signals = ", ".join(f"`{signal}`" for signal in row.get("signals", [])) or "none"
        facets = ", ".join(f"`{facet}`" for facet in row.get("source_facets", [])) or "none"
        entities = ", ".join(f"`{entity}`" for entity in row.get("source_entities", [])) or "none"
        lines.extend(
            [
                f"### {index:03d}. {markdown_escape(str(row['title']))}",
                "",
                f"- Source: [[{row['slug']}]]",
                f"- Dates: intake {date_display(row.get('intake_recency'))}, source {date_display(row.get('source_recency'))}, published {date_display(row.get('published'))}, saved {date_display(row.get('saved_at'))}",
                f"- Status: `{row['status']}` / `{row['source_type']}`",
                f"- Signals: {signals}",
                f"- Facets: {facets}",
                f"- Entities: {entities}",
                f"- Collection: {markdown_escape(str(row.get('raindrop_collection_current') or 'unknown'))}",
                f"- Topics: {topics}",
            ]
        )
        url = str(row.get("url") or "")
        if url:
            lines.append(f"- URL: {url}")
        summary = str(row.get("summary") or "").strip()
        if summary:
            lines.extend(["", f"Brief: {summary}"])
        lines.append("")
    view_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    append_log(root, "maintain", "view", "recent-sources", f"Generated recent sources view with {len(rows)} items")
    return state_path, view_path, rows


def state_slug_ranks(path: Path) -> dict[str, int]:
    if not path.exists():
        return {}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}
    ranks: dict[str, int] = {}
    for index, item in enumerate(payload.get("items") or [], start=1):
        slug = str(item.get("slug") or "")
        if slug:
            ranks[slug] = index
    return ranks


def unsorted_crosswalk_bucket(signals: list[str], status: str) -> str:
    signal_set = set(signals)
    if status == "gone":
        return "Terminal / gone"
    if "test-for-agent" in signal_set:
        return "Agent experiments"
    if "test-for-me" in signal_set:
        return "Personal setup experiments"
    if "interesting-to-read" in signal_set:
        return "Reflection reads"
    return "No experiment signal yet"


def recency_tier(rank: int) -> str:
    if rank <= 15:
        return "hot"
    if rank <= 45:
        return "warm"
    return "long-tail"


def previously_unsorted_crosswalk_rows(root: Path) -> list[dict[str, Any]]:
    experiment_rank = state_slug_ranks(root / "_state" / "experiment-scan.json")
    global_recent_rank = state_slug_ranks(root / "_state" / "recent-sources.json")
    topics_by_source = topic_links_by_source(root)
    action_signals = set(DEFAULT_ACTION_TAGS)
    rows: list[dict[str, Any]] = []
    for path in sorted((root / "sources").glob("*.md")):
        text = path.read_text(encoding="utf-8")
        if frontmatter_scalar(text, "raindrop_collection_at_ingest") != "Unsorted":
            continue
        human_tags = sorted(frontmatter_list(text, "raindrop_tags"))
        agent_attention = sorted(frontmatter_list(text, "agent_attention"))
        signals = sorted(({*human_tags, *agent_attention}) & action_signals)
        source_facets = sorted(frontmatter_list(text, "source_facets"))
        source_entities = sorted(frontmatter_list(text, "source_entities"))
        status = frontmatter_scalar(text, "ingest_status") or ""
        intake_recency = intake_recency_value(text, path)
        source_recency = source_recency_value(text, path)
        rows.append(
            {
                "slug": path.stem,
                "path": str(path),
                "title": frontmatter_scalar(text, "title") or note_title(path),
                "url": frontmatter_scalar(text, "canonical_url") or frontmatter_scalar(text, "url") or "",
                "status": status,
                "source_type": frontmatter_scalar(text, "source_type") or "",
                "signals": signals,
                "raindrop_tags": human_tags,
                "agent_attention": agent_attention,
                "source_facets": source_facets,
                "source_entities": source_entities,
                "experiment_rank": experiment_rank.get(path.stem),
                "global_recent_rank": global_recent_rank.get(path.stem),
                "intake_recency": intake_recency,
                "source_recency": source_recency,
                "published": frontmatter_scalar(text, "published") or "",
                "saved_at": frontmatter_scalar(text, "saved_at") or frontmatter_scalar(text, "raindrop_created") or "",
                "source_age_days_at_save": frontmatter_scalar(text, "source_age_days_at_save") or "",
                "collection_current": frontmatter_scalar(text, "raindrop_collection_current")
                or frontmatter_scalar(text, "raindrop_collection_at_ingest")
                or "",
                "topics": topics_by_source.get(path.stem, []),
                "summary": source_brief(text, limit=260),
            }
        )
    rows.sort(
        key=lambda row: (
            -sort_timestamp(row.get("intake_recency")),
            -sort_timestamp(row.get("source_recency")),
            str(row.get("title") or "").casefold(),
        )
    )
    for index, row in enumerate(rows, start=1):
        row["previously_unsorted_recency_rank"] = index
        row["recency_tier"] = recency_tier(index)
        row["bucket"] = unsorted_crosswalk_bucket(row["signals"], row["status"])
    return rows


def write_previously_unsorted_crosswalk(root: Path) -> tuple[Path, Path, list[dict[str, Any]]]:
    (root / "_views").mkdir(parents=True, exist_ok=True)
    (root / "_state").mkdir(parents=True, exist_ok=True)
    rows = previously_unsorted_crosswalk_rows(root)
    generated = utc_now().isoformat()
    bucket_order = [
        "Agent experiments",
        "Personal setup experiments",
        "Reflection reads",
        "No experiment signal yet",
        "Terminal / gone",
    ]
    counts_by_bucket = {bucket: sum(1 for row in rows if row["bucket"] == bucket) for bucket in bucket_order}
    counts_by_status: dict[str, int] = {}
    counts_by_signal: dict[str, int] = {signal: 0 for signal in DEFAULT_ACTION_TAGS}
    counts_by_signal["no-signal"] = 0
    for row in rows:
        counts_by_status[row["status"]] = counts_by_status.get(row["status"], 0) + 1
        if row["signals"]:
            for signal in row["signals"]:
                counts_by_signal[signal] = counts_by_signal.get(signal, 0) + 1
        else:
            counts_by_signal["no-signal"] += 1

    state_path = root / "_state" / "previously-unsorted-crosswalk.json"
    view_path = root / "_views" / "previously-unsorted-crosswalk.md"
    state = {
        "generated_at": generated,
        "definition": "Sources with raindrop_collection_at_ingest == Unsorted, cross-referenced against experiment-scan and recency.",
        "item_count": len(rows),
        "counts_by_bucket": counts_by_bucket,
        "counts_by_status": counts_by_status,
        "counts_by_signal": counts_by_signal,
        "items": rows,
    }
    state_path.write_text(json.dumps(state, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")

    lines = [
        "---",
        "type: view",
        "view: previously-unsorted-crosswalk",
        f"generated: {yaml_value(generated)}",
        f"item_count: {len(rows)}",
        "---",
        "",
        "# Previously Unsorted Crosswalk",
        "",
        "This generated view cross-references sources originally saved in Raindrop Unsorted against experiment signals and recency. It is not ontology.",
        "",
        "Sorting: intake recency first, then source recency, then title. `Experiment rank` is the current rank in `experiment-scan`; `none` means the source is not currently an experiment/action candidate.",
        "",
        "Regenerate it with:",
        "",
        "```bash",
        "~/.codex/skills/llm-wiki/scripts/wiki.py actions unsorted-crosswalk",
        "```",
        "",
        "## Counts",
        "",
        f"- Total originally Unsorted sources: {len(rows)}",
    ]
    for bucket in bucket_order:
        lines.append(f"- {bucket}: {counts_by_bucket.get(bucket, 0)}")
    lines.append("- Status counts: " + ", ".join(f"`{status}` {count}" for status, count in sorted(counts_by_status.items())))
    lines.append("- Signal counts: " + ", ".join(f"`{signal}` {count}" for signal, count in sorted(counts_by_signal.items())))
    lines.append("")

    for bucket in bucket_order:
        bucket_rows = [row for row in rows if row["bucket"] == bucket]
        if not bucket_rows:
            continue
        lines.extend(["", f"## {bucket} ({len(bucket_rows)})", ""])
        for row in bucket_rows:
            signals = ", ".join(f"`{signal}`" for signal in row["signals"]) or "none"
            facets = ", ".join(f"`{facet}`" for facet in row.get("source_facets", [])) or "none"
            entities = ", ".join(f"`{entity}`" for entity in row.get("source_entities", [])) or "none"
            topics = ", ".join(f"[[{topic}]]" for topic in row["topics"]) or "none"
            experiment_rank = row["experiment_rank"] if row["experiment_rank"] is not None else "none"
            global_recent_rank = row["global_recent_rank"] if row["global_recent_rank"] is not None else "outside top recent view"
            lines.extend(
                [
                    f"### {int(row['previously_unsorted_recency_rank']):03d}. {markdown_escape(str(row['title']))}",
                    "",
                    f"- Source: [[{row['slug']}]]",
                    f"- Signals: {signals}",
                    f"- Facets: {facets}",
                    f"- Entities: {entities}",
                    f"- Experiment rank: {experiment_rank}",
                    f"- Previously-Unsorted recency rank: {row['previously_unsorted_recency_rank']} ({row['recency_tier']})",
                    f"- Global recent rank: {global_recent_rank}",
                    f"- Dates: intake {date_display(row.get('intake_recency'))}, source {date_display(row.get('source_recency'))}, saved {date_display(row.get('saved_at'))}, published {date_display(row.get('published'))}",
                    f"- Status: `{row['status']}` / `{row['source_type']}`",
                    f"- Current collection: {markdown_escape(str(row.get('collection_current') or 'unknown'))}",
                    f"- Topics: {topics}",
                ]
            )
            url = str(row.get("url") or "")
            if url:
                lines.append(f"- URL: {url}")
            summary = str(row.get("summary") or "").strip()
            if summary:
                lines.extend(["", f"Brief: {summary}"])
            lines.append("")
    view_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    append_log(root, "maintain", "view", "previously-unsorted-crosswalk", f"Generated previously Unsorted crosswalk with {len(rows)} items")
    return state_path, view_path, rows


def facet_slug(facets: list[str]) -> str:
    return safe_slug("-".join(facets) if facets else "all-facets", limit=80)


def facet_rows(root: Path, facets: list[str], limit: int, include_gone: bool = False) -> list[dict[str, Any]]:
    wanted = {facet.casefold() for facet in facets}
    topics_by_source = topic_links_by_source(root)
    rows: list[dict[str, Any]] = []
    for path in sorted((root / "sources").glob("*.md")):
        text = path.read_text(encoding="utf-8")
        status = frontmatter_scalar(text, "ingest_status") or ""
        if status == "gone" and not include_gone:
            continue
        source_facets = sorted(frontmatter_list(text, "source_facets"))
        if wanted and not ({facet.casefold() for facet in source_facets} & wanted):
            continue
        source_entities = sorted(frontmatter_list(text, "source_entities"))
        human_tags = sorted(frontmatter_list(text, "raindrop_tags"))
        agent_attention = sorted(frontmatter_list(text, "agent_attention"))
        rows.append(
            {
                "slug": path.stem,
                "path": str(path),
                "title": frontmatter_scalar(text, "title") or note_title(path),
                "url": frontmatter_scalar(text, "canonical_url") or frontmatter_scalar(text, "url") or "",
                "status": status,
                "source_type": frontmatter_scalar(text, "source_type") or "",
                "source_facets": source_facets,
                "source_entities": source_entities,
                "signals": sorted({*human_tags, *agent_attention}),
                "intake_recency": intake_recency_value(text, path),
                "source_recency": source_recency_value(text, path),
                "published": frontmatter_scalar(text, "published") or "",
                "saved_at": frontmatter_scalar(text, "saved_at") or frontmatter_scalar(text, "raindrop_created") or "",
                "collection_current": frontmatter_scalar(text, "raindrop_collection_current")
                or frontmatter_scalar(text, "raindrop_collection_at_ingest")
                or "",
                "topics": topics_by_source.get(path.stem, []),
                "summary": source_brief(text),
            }
        )
    rows.sort(
        key=lambda row: (
            -sort_timestamp(row.get("intake_recency")),
            -sort_timestamp(row.get("source_recency")),
            str(row.get("title") or "").casefold(),
        )
    )
    return rows[:limit] if limit else rows


def write_facet_view(root: Path, facets: list[str], limit: int = DEFAULT_FACET_LIMIT, include_gone: bool = False) -> tuple[Path, Path, list[dict[str, Any]]]:
    (root / "_views").mkdir(parents=True, exist_ok=True)
    (root / "_state").mkdir(parents=True, exist_ok=True)
    normalized_facets = sorted({facet for facet in facets if facet})
    rows = facet_rows(root, normalized_facets, limit=limit, include_gone=include_gone)
    generated = utc_now().isoformat()
    slug = facet_slug(normalized_facets)
    state_path = root / "_state" / f"facet-{slug}.json"
    view_path = root / "_views" / f"facet-{slug}.md"
    state = {
        "generated_at": generated,
        "facets": normalized_facets,
        "limit": limit,
        "include_gone": include_gone,
        "item_count": len(rows),
        "items": rows,
    }
    state_path.write_text(json.dumps(state, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")
    command = "~/.codex/skills/llm-wiki/scripts/wiki.py actions facet " + " ".join(f"--facet {facet}" for facet in normalized_facets)
    if limit:
        command += f" --limit {limit}"
    if include_gone:
        command += " --include-gone"
    title = "Facet Scan: " + (", ".join(normalized_facets) if normalized_facets else "all facets")
    lines = [
        "---",
        "type: view",
        "view: facet-scan",
        f"generated: {yaml_value(generated)}",
        f"facets: {yaml_value(normalized_facets)}",
        f"item_count: {len(rows)}",
        "---",
        "",
        f"# {title}",
        "",
        "This generated view filters source notes by `source_facets` and sorts by intake recency first, then source recency. It is not ontology.",
        "",
        "Regenerate it with:",
        "",
        "```bash",
        command.strip(),
        "```",
        "",
        "## Sources",
        "",
    ]
    if not rows:
        lines.append("No matching sources found.")
    for index, row in enumerate(rows, start=1):
        topics = ", ".join(f"[[{topic}]]" for topic in row["topics"]) or "none"
        facets_text = ", ".join(f"`{facet}`" for facet in row["source_facets"]) or "none"
        entities_text = ", ".join(f"`{entity}`" for entity in row["source_entities"]) or "none"
        signals_text = ", ".join(f"`{signal}`" for signal in row["signals"]) or "none"
        lines.extend(
            [
                f"### {index:03d}. {markdown_escape(str(row['title']))}",
                "",
                f"- Source: [[{row['slug']}]]",
                f"- Facets: {facets_text}",
                f"- Entities: {entities_text}",
                f"- Signals: {signals_text}",
                f"- Dates: intake {date_display(row.get('intake_recency'))}, source {date_display(row.get('source_recency'))}, saved {date_display(row.get('saved_at'))}, published {date_display(row.get('published'))}",
                f"- Status: `{row['status']}` / `{row['source_type']}`",
                f"- Collection: {markdown_escape(str(row.get('collection_current') or 'unknown'))}",
                f"- Topics: {topics}",
            ]
        )
        url = str(row.get("url") or "")
        if url:
            lines.append(f"- URL: {url}")
        summary = str(row.get("summary") or "").strip()
        if summary:
            lines.extend(["", f"Brief: {summary}"])
        lines.append("")
    view_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    append_log(root, "maintain", "view", f"facet-{slug}", f"Generated facet view for {', '.join(normalized_facets) or 'all facets'} with {len(rows)} items")
    return state_path, view_path, rows


def topic_source_links(text: str, source_slugs: set[str]) -> list[str]:
    links = set()
    for link in re.findall(r"\[\[([^\]]+)\]\]", text):
        target = link.split("|", 1)[0]
        if target in source_slugs:
            links.add(target)
    return sorted(links)


def cmd_bootstrap(args: argparse.Namespace) -> None:
    print_json(bootstrap(wiki_root(args)))


def cmd_sync_topic_sources(args: argparse.Namespace) -> None:
    root = wiki_root(args)
    require_rules(root)
    source_slugs = {path.stem for path in (root / "sources").glob("*.md")}
    updated: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []
    for path in sorted((root / "topics").glob("*.md")):
        text = path.read_text(encoding="utf-8")
        sources = topic_source_links(text, source_slugs)
        next_text = update_frontmatter(text, {"sources": sources, "updated": today()}, force=True)
        if next_text != text:
            path.write_text(next_text, encoding="utf-8")
            updated.append({"path": str(path), "slug": path.stem, "source_count": len(sources)})
            append_log(root, "maintain", "topic", path.stem, f"Synced {len(sources)} source links into frontmatter")
        else:
            skipped.append({"path": str(path), "slug": path.stem, "source_count": len(sources)})
    index_path = rebuild_index(root)
    print_json(
        {
            "updated_count": len(updated),
            "skipped_count": len(skipped),
            "updated": updated,
            "skipped": skipped,
            "index": str(index_path),
        }
    )


def cmd_raindrop_collections(args: argparse.Namespace) -> None:
    collections = fetch_collections()
    print_json(
        [
            {
                "id": collection_id(collection),
                "title": collection_title(collection),
                "count": collection.get("count"),
                "public": collection.get("public"),
                "view": collection.get("view"),
            }
            for collection in sorted(collections, key=lambda c: (collection_title(c).casefold(), collection_id(c) or 0))
        ]
    )


def cmd_raindrop_inventory(args: argparse.Namespace) -> None:
    root = wiki_root(args)
    inventory = build_inventory(root, args.exclude_collection, args.max_items)
    if args.write_report:
        state_path, report_path = write_inventory(root, inventory)
        inventory["written"] = {"state": str(state_path), "report": str(report_path)}
    print_json(inventory)


def cmd_raindrop_ingest(args: argparse.Namespace) -> None:
    root = wiki_root(args)
    target_items, collection_names, excluded_ids = target_raindrop_items(
        root,
        args.exclude_collection,
        max_items=args.scan_max,
    )
    if args.oldest:
        target_items = list(reversed(target_items))
    selected = target_items[: args.limit]
    results = [write_source_note(root, item, collection_names) for item in selected]
    rebuild_index(root)
    for result in results:
        append_log(
            root,
            "raindrop",
            "source",
            result["slug"],
            f"Raindrop ID: {result['raindrop_id']} - {result['status']}",
        )
    report_path = None
    if args.write_report:
        report_path = write_ingest_report(root, results, excluded_ids)
    state_path = root / "_state" / "raindrop-last-ingest.json"
    state = {
        "generated_at": utc_now().isoformat(),
        "limit": args.limit,
        "scan_max": args.scan_max,
        "oldest": args.oldest,
        "excluded_collection_titles": args.exclude_collection,
        "excluded_collection_ids": excluded_ids,
        "created_count": len(results),
        "results": results,
        "report": str(report_path) if report_path else "",
    }
    state_path.write_text(json.dumps(state, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")
    print_json(state)


def cmd_raindrop_refresh_tags(args: argparse.Namespace) -> None:
    root = wiki_root(args)
    require_rules(root)
    collections = fetch_collections()
    collection_names = {
        cid: collection_title(collection)
        for collection in collections
        if (cid := collection_id(collection)) is not None
    }
    collection_names.update({0: "All", -1: "Unsorted", -99: "Trash"})
    items = fetch_raindrops(args.collection, max_items=args.max_items)
    id_paths, url_paths = existing_identity_paths(root)
    wanted_tags = args.tag or []
    wanted_set = {tag.casefold() for tag in wanted_tags}
    updated: list[dict[str, Any]] = []
    missing: list[dict[str, Any]] = []
    duplicate_matches: list[dict[str, Any]] = []
    tagged_rows: list[dict[str, Any]] = []
    seen_paths: set[Path] = set()
    for item in items:
        rid = item.get("_id")
        path = id_paths.get(rid) if isinstance(rid, int) else None
        if path is None:
            path = url_paths.get(canonical_url(str(item.get("link") or "")))
        if path is None:
            missing.append(
                {
                    "raindrop_id": rid,
                    "title": item.get("title") or "",
                    "url": item.get("link") or "",
                    "tags": item.get("tags") or [],
                }
            )
            continue
        tags = sorted(str(tag) for tag in (item.get("tags") or []))
        if path in seen_paths:
            duplicate_matches.append(
                {
                    "path": str(path),
                    "slug": path.stem,
                    "raindrop_id": rid,
                    "title": item.get("title") or "",
                    "url": item.get("link") or "",
                    "tags": tags,
                }
            )
            for row in tagged_rows:
                if row["slug"] == path.stem:
                    row["tags"] = sorted({*row.get("tags", []), *tags})
                    break
            continue
        seen_paths.add(path)
        text = path.read_text(encoding="utf-8")
        cid = item_collection_id(item)
        updates = {
            "raindrop_tags": tags,
            "raindrop_collection_current": collection_names.get(cid or args.collection, ""),
            "raindrop_last_update": item.get("lastUpdate") or "",
            "updated": today(),
        }
        next_text = update_frontmatter(text, updates, force=True)
        if next_text != text:
            path.write_text(next_text, encoding="utf-8")
            updated.append({"path": str(path), "slug": path.stem, "raindrop_id": rid, "tags": tags})
            append_log(root, "raindrop", "source", path.stem, f"Refreshed Raindrop tags: {', '.join(tags) or 'none'}")
        if wanted_set and not ({tag.casefold() for tag in tags} & wanted_set):
            continue
        if wanted_set:
            title = frontmatter_scalar(next_text, "title") or str(item.get("title") or path.stem)
            tagged_rows.append(
                {
                    "slug": path.stem,
                    "path": str(path),
                    "raindrop_id": rid,
                    "title": title,
                    "url": frontmatter_scalar(next_text, "canonical_url") or str(item.get("link") or ""),
                    "tags": tags,
                    "saved_at": frontmatter_scalar(next_text, "saved_at") or str(item.get("created") or ""),
                }
            )
    tagged_rows = dedupe_rows_by_slug(tagged_rows)
    state_path = report_path = scan_state_path = scan_view_path = None
    scan_rows: list[dict[str, Any]] = []
    if args.write_report:
        state_path, report_path = write_tag_report(root, tagged_rows, wanted_tags, args.collection)
        if wanted_tags:
            scan_state_path, scan_view_path, scan_rows = write_experiment_scan(root, wanted_tags)
    rebuild_index(root)
    print_json(
        {
            "collection": args.collection,
            "fetched_count": len(items),
            "updated_count": len(updated),
            "missing_source_count": len(missing),
            "duplicate_match_count": len(duplicate_matches),
            "matched_tagged_count": len(tagged_rows),
            "tags": wanted_tags,
            "updated": updated,
            "matched_tagged": tagged_rows,
            "missing_sources": missing[:20],
            "duplicate_matches": duplicate_matches[:20],
            "state": str(state_path) if state_path else "",
            "report": str(report_path) if report_path else "",
            "scan_state": str(scan_state_path) if scan_state_path else "",
            "scan_view": str(scan_view_path) if scan_view_path else "",
            "scan_item_count": len(scan_rows),
        }
    )


def cmd_raindrop_move_processed(args: argparse.Namespace) -> None:
    root = wiki_root(args)
    require_rules(root)
    target_id = collection_id_by_title(args.to_collection)
    allowed_statuses = {"ingested"}
    if not args.only_ingested:
        allowed_statuses.add("reference")
    if not args.exclude_gone:
        allowed_statuses.add("gone")
    rows = processed_unsorted_source_rows(
        root,
        include_reference=not args.only_ingested,
        include_gone=not args.exclude_gone,
        source_collection=args.from_collection,
    )
    ids = [int(row["raindrop_id"]) for row in rows]
    responses: list[dict[str, Any]] = []
    if args.apply and ids:
        for start in range(0, len(ids), args.batch_size):
            batch = ids[start : start + args.batch_size]
            response = api_put(
                f"/raindrops/{args.from_collection}",
                {"ids": batch, "collection": {"$id": target_id}},
            )
            responses.append(response)
        moved_at = utc_now().isoformat().replace("+00:00", "Z")
        for row in rows:
            path = Path(str(row["path"]))
            text = path.read_text(encoding="utf-8")
            next_text = update_frontmatter(
                text,
                {
                    "raindrop_collection_current": args.to_collection,
                    "raindrop_moved_after_process_at": moved_at,
                    "updated": today(),
                },
                force=True,
            )
            if next_text != text:
                path.write_text(next_text, encoding="utf-8")
            append_log(root, "raindrop", "source", path.stem, f"Moved processed bookmark to {args.to_collection}")
    report_path = write_move_report(
        root,
        rows,
        args.to_collection,
        args.apply,
        {"responses": responses} if responses else None,
        allowed_statuses,
    )
    rebuild_index(root)
    print_json(
        {
            "apply": args.apply,
            "from_collection": args.from_collection,
            "to_collection": args.to_collection,
            "to_collection_id": target_id,
            "candidate_count": len(rows),
            "moved_count": len(ids) if args.apply else 0,
            "report": str(report_path),
            "items": rows[:50],
        }
    )


def cmd_actions_scan(args: argparse.Namespace) -> None:
    root = wiki_root(args)
    require_rules(root)
    tags = [*args.tag, *args.signal] or list(DEFAULT_ACTION_TAGS)
    state_path, view_path, rows = write_experiment_scan(root, tags)
    index_path = rebuild_index(root)
    print_json(
        {
            "tags": tags,
            "item_count": len(rows),
            "state": str(state_path),
            "view": str(view_path),
            "index": str(index_path),
        }
    )


def cmd_actions_recent(args: argparse.Namespace) -> None:
    root = wiki_root(args)
    require_rules(root)
    state_path, view_path, rows = write_recent_sources(root, limit=args.limit, include_gone=args.include_gone)
    index_path = rebuild_index(root)
    print_json(
        {
            "limit": args.limit,
            "include_gone": args.include_gone,
            "item_count": len(rows),
            "state": str(state_path),
            "view": str(view_path),
            "index": str(index_path),
        }
    )


def cmd_actions_unsorted_crosswalk(args: argparse.Namespace) -> None:
    root = wiki_root(args)
    require_rules(root)
    state_path, view_path, rows = write_previously_unsorted_crosswalk(root)
    index_path = rebuild_index(root)
    print_json(
        {
            "item_count": len(rows),
            "state": str(state_path),
            "view": str(view_path),
            "index": str(index_path),
        }
    )


def cmd_actions_facet(args: argparse.Namespace) -> None:
    root = wiki_root(args)
    require_rules(root)
    facets = args.facet or []
    state_path, view_path, rows = write_facet_view(root, facets=facets, limit=args.limit, include_gone=args.include_gone)
    index_path = rebuild_index(root)
    print_json(
        {
            "facets": facets,
            "limit": args.limit,
            "include_gone": args.include_gone,
            "item_count": len(rows),
            "state": str(state_path),
            "view": str(view_path),
            "index": str(index_path),
        }
    )


def cmd_sources_classify_facets(args: argparse.Namespace) -> None:
    root = wiki_root(args)
    require_rules(root)
    rows: list[dict[str, Any]] = []
    for path in sorted((root / "sources").glob("*.md"), key=source_priority_key):
        text = path.read_text(encoding="utf-8")
        inferred_facets, inferred_entities = infer_source_facets(text)
        existing_facets = sorted(frontmatter_list(text, "source_facets"))
        existing_entities = sorted(frontmatter_list(text, "source_entities"))
        if args.replace:
            next_facets = inferred_facets
            next_entities = inferred_entities
        else:
            next_facets = sorted({*existing_facets, *inferred_facets})
            next_entities = sorted({*existing_entities, *inferred_entities})
        changed = next_facets != existing_facets or next_entities != existing_entities
        if changed:
            next_text = update_frontmatter(
                text,
                {
                    "source_facets": next_facets,
                    "source_entities": next_entities,
                    "updated": today(),
                },
                force=True,
            )
            path.write_text(next_text, encoding="utf-8")
            append_log(root, "maintain", "source", path.stem, f"Classified facets: {', '.join(next_facets) or 'none'}")
        if changed or args.include_unchanged:
            rows.append(
                {
                    "path": str(path),
                    "slug": path.stem,
                    "title": note_title(path),
                    "updated": changed,
                    "source_facets": next_facets,
                    "source_entities": next_entities,
                }
            )
    report_path = write_facet_classification_report(root, rows) if args.write_report else None
    rebuild_index(root)
    print_json(
        {
            "updated_count": sum(1 for row in rows if row.get("updated")),
            "reported_count": len(rows),
            "replace": args.replace,
            "report": str(report_path) if report_path else "",
            "updated": [row for row in rows if row.get("updated")][:80],
        }
    )


def cmd_sources_recover_blocked(args: argparse.Namespace) -> None:
    root = wiki_root(args)
    require_rules(root)
    statuses = {"blocked"}
    if args.include_reference:
        statuses.add("reference")
    candidates: list[Path] = []
    for path in sorted((root / "sources").glob("*.md")):
        text = path.read_text(encoding="utf-8")
        status = frontmatter_scalar(text, "ingest_status") or ""
        if status in statuses:
            candidates.append(path)
    if args.limit:
        candidates = candidates[: args.limit]
    results = [recover_source_note(path) for path in candidates]
    report_path = write_recovery_report(root, results) if args.write_report else None
    rebuild_index(root)
    print_json(
        {
            "candidate_count": len(candidates),
            "updated_count": len(results),
            "statuses": sorted(statuses),
            "report": str(report_path) if report_path else "",
            "results": results,
        }
    )


def cmd_raindrop_enrich_dates(args: argparse.Namespace) -> None:
    root = wiki_root(args)
    require_rules(root)
    source_paths = sorted((root / "sources").glob("*.md"))
    updated: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []
    for path in source_paths:
        text = path.read_text(encoding="utf-8")
        rid_text = frontmatter_scalar(text, "raindrop_id")
        if not rid_text or not rid_text.isdigit():
            skipped.append({"path": str(path), "reason": "missing raindrop_id"})
            continue
        current = parse_frontmatter_map(text)
        required_keys = {"canonical_url", "published", "source_modified", "saved_at", "ingested_at", "source_age_days_at_save", "source_age_days_at_ingest"}
        if not args.force and required_keys.issubset(current.keys()):
            skipped.append({"path": str(path), "reason": "date fields already present"})
            continue
        item_response = api_get(f"/raindrop/{rid_text}")
        item = item_response.get("item") or {}
        url = frontmatter_scalar(text, "url") or str(item.get("link") or "")
        extraction = extract_url(url) if url else {}
        published = iso_datetime(extraction.get("published"))
        source_modified = iso_datetime(extraction.get("modified"))
        saved_at = iso_datetime(item.get("created") or frontmatter_scalar(text, "raindrop_created"))
        ingested_at = iso_datetime(frontmatter_scalar(text, "ingested_at") or frontmatter_scalar(text, "extracted_at") or utc_now())
        updates: dict[str, Any] = {
            "canonical_url": canonical_url(url),
            "published": published,
            "source_modified": source_modified,
            "saved_at": saved_at,
            "ingested_at": ingested_at,
            "updated": today(),
        }
        save_age = age_days(published, saved_at)
        ingest_age = age_days(published, ingested_at)
        updates["source_age_days_at_save"] = save_age if save_age is not None else ""
        updates["source_age_days_at_ingest"] = ingest_age if ingest_age is not None else ""
        next_text = update_frontmatter(text, updates, force=args.force)
        if next_text != text:
            path.write_text(next_text, encoding="utf-8")
            updated.append(
                {
                    "path": str(path),
                    "slug": path.stem,
                    "raindrop_id": int(rid_text),
                    "published": published,
                    "saved_at": saved_at,
                    "source_age_days_at_save": save_age,
                    "source_age_days_at_ingest": ingest_age,
                }
            )
            append_log(root, "maintain", "source", path.stem, "Backfilled source date metadata")
        else:
            skipped.append({"path": str(path), "reason": "no change"})
        if args.limit and len(updated) >= args.limit:
            break
    rebuild_index(root)
    print_json({"updated_count": len(updated), "skipped_count": len(skipped), "updated": updated, "skipped": skipped[:20]})


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Maintain the local LLM wiki.")
    parser.add_argument("--wiki-root", default=str(DEFAULT_WIKI_ROOT), help="Wiki root path")
    subparsers = parser.add_subparsers(dest="command", required=True)

    bootstrap_parser = subparsers.add_parser("bootstrap", help="Create minimal wiki structure")
    bootstrap_parser.set_defaults(func=cmd_bootstrap)

    sync_parser = subparsers.add_parser("sync-topic-sources", help="Sync topic frontmatter sources from source wikilinks")
    sync_parser.set_defaults(func=cmd_sync_topic_sources)

    sources_parser = subparsers.add_parser("sources", help="Source-note maintenance helpers")
    sources_subparsers = sources_parser.add_subparsers(dest="sources_command", required=True)

    recover_parser = sources_subparsers.add_parser("recover-blocked", help="Retry blocked source notes through recovery fallbacks")
    recover_parser.add_argument("--include-reference", action="store_true", help="Also retry reference notes with weak extraction")
    recover_parser.add_argument("--limit", type=int, default=0, help="Maximum source notes to retry; 0 means no limit")
    recover_parser.add_argument("--write-report", action="store_true", help="Write a recovery report under _reports")
    recover_parser.set_defaults(func=cmd_sources_recover_blocked)

    classify_facets_parser = sources_subparsers.add_parser("classify-facets", help="Infer local source_facets/source_entities on source notes")
    classify_facets_parser.add_argument("--replace", action="store_true", help="Replace existing facets/entities with inferred values instead of merging")
    classify_facets_parser.add_argument("--include-unchanged", action="store_true", help="Include unchanged sources in command output/report")
    classify_facets_parser.add_argument("--write-report", action="store_true", help="Write a classification report under _reports")
    classify_facets_parser.set_defaults(func=cmd_sources_classify_facets)

    actions_parser = subparsers.add_parser("actions", help="Generated action and experiment views")
    actions_subparsers = actions_parser.add_subparsers(dest="actions_command", required=True)

    scan_parser = actions_subparsers.add_parser("scan", help="Generate the stable experiment scan view from source-note tags")
    scan_parser.add_argument("--tag", action="append", default=[], help="Attention signal to include. Backward-compatible alias for --signal")
    scan_parser.add_argument("--signal", action="append", default=[], help="Attention signal to include from raindrop_tags or agent_attention. Can be repeated")
    scan_parser.set_defaults(func=cmd_actions_scan)

    recent_parser = actions_subparsers.add_parser("recent", help="Generate the recency-biased recent sources view")
    recent_parser.add_argument("--limit", type=int, default=DEFAULT_RECENT_LIMIT, help=f"Maximum sources to include. Defaults to {DEFAULT_RECENT_LIMIT}")
    recent_parser.add_argument("--include-gone", action="store_true", help="Include terminal gone/deleted sources")
    recent_parser.set_defaults(func=cmd_actions_recent)

    unsorted_parser = actions_subparsers.add_parser(
        "unsorted-crosswalk",
        help="Cross-reference originally Unsorted sources against experiments and recency",
    )
    unsorted_parser.set_defaults(func=cmd_actions_unsorted_crosswalk)

    facet_parser = actions_subparsers.add_parser("facet", help="Generate a source_facets filtered view")
    facet_parser.add_argument("--facet", action="append", default=[], help="Facet to include. Can be repeated; matching is OR")
    facet_parser.add_argument("--limit", type=int, default=DEFAULT_FACET_LIMIT, help=f"Maximum sources to include. Defaults to {DEFAULT_FACET_LIMIT}")
    facet_parser.add_argument("--include-gone", action="store_true", help="Include terminal gone/deleted sources")
    facet_parser.set_defaults(func=cmd_actions_facet)

    raindrop_parser = subparsers.add_parser("raindrop", help="Raindrop.io helpers")
    raindrop_subparsers = raindrop_parser.add_subparsers(dest="raindrop_command", required=True)

    collections_parser = raindrop_subparsers.add_parser("collections", help="List Raindrop collections")
    collections_parser.set_defaults(func=cmd_raindrop_collections)

    inventory_parser = raindrop_subparsers.add_parser("inventory", help="Read-only Raindrop inventory")
    inventory_parser.add_argument(
        "--exclude-collection",
        action="append",
        default=list(DEFAULT_EXCLUDED_COLLECTIONS),
        help="Collection title to exclude. Defaults to Moose's Corner.",
    )
    inventory_parser.add_argument("--max-items", type=int, default=None, help="Limit fetched all-bookmark items")
    inventory_parser.add_argument("--write-report", action="store_true", help="Write _state JSON and _reports Markdown")
    inventory_parser.set_defaults(func=cmd_raindrop_inventory)

    ingest_parser = raindrop_subparsers.add_parser("ingest", help="Create local source notes from Raindrop items")
    ingest_parser.add_argument(
        "--exclude-collection",
        action="append",
        default=list(DEFAULT_EXCLUDED_COLLECTIONS),
        help="Collection title to exclude. Defaults to Moose's Corner and Shopping.",
    )
    ingest_parser.add_argument("--limit", type=int, default=5, help="Number of source notes to create")
    ingest_parser.add_argument("--scan-max", type=int, default=None, help="Limit fetched all-bookmark items before filtering")
    ingest_parser.add_argument("--oldest", action="store_true", help="Ingest oldest pending target items first")
    ingest_parser.add_argument("--write-report", action="store_true", help="Write _reports Markdown")
    ingest_parser.set_defaults(func=cmd_raindrop_ingest)

    refresh_tags_parser = raindrop_subparsers.add_parser("refresh-tags", help="Refresh Raindrop tags on existing source notes")
    refresh_tags_parser.add_argument("--collection", type=int, default=-1, help="Raindrop collection ID to refresh. Defaults to Unsorted (-1)")
    refresh_tags_parser.add_argument("--max-items", type=int, default=None, help="Limit fetched items")
    refresh_tags_parser.add_argument("--tag", action="append", default=[], help="Tag to include in the action report. Can be repeated")
    refresh_tags_parser.add_argument("--write-report", action="store_true", help="Write _state JSON and _reports Markdown for matching tags")
    refresh_tags_parser.set_defaults(func=cmd_raindrop_refresh_tags)

    move_parser = raindrop_subparsers.add_parser("move-processed", help="Move processed Unsorted bookmarks into another Raindrop collection")
    move_parser.add_argument("--from-collection", type=int, default=-1, help="Source Raindrop collection ID. Defaults to Unsorted (-1)")
    move_parser.add_argument("--to-collection", default="Resources", help="Target Raindrop collection title. Defaults to Resources")
    move_parser.add_argument("--only-ingested", action="store_true", help="Move only fully ingested notes, not reference notes")
    move_parser.add_argument("--exclude-gone", action="store_true", help="Do not move terminal gone/deleted source notes")
    move_parser.add_argument("--batch-size", type=int, default=100, help="Batch size for Raindrop update calls")
    move_parser.add_argument("--apply", action="store_true", help="Actually move Raindrop bookmarks. Omit for dry-run")
    move_parser.set_defaults(func=cmd_raindrop_move_processed)

    enrich_parser = raindrop_subparsers.add_parser("enrich-dates", help="Backfill source publication/save/ingest date metadata")
    enrich_parser.add_argument("--limit", type=int, default=0, help="Maximum source notes to update; 0 means no limit")
    enrich_parser.add_argument("--force", action="store_true", help="Refresh date fields even when already present")
    enrich_parser.set_defaults(func=cmd_raindrop_enrich_dates)

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
