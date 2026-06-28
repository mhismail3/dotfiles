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
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


API_BASE = "https://api.raindrop.io/rest/v1"
DEFAULT_WIKI_ROOT = Path("~/.codex/wiki").expanduser()
DEFAULT_EXCLUDED_COLLECTIONS = ("Moose's Corner", "Shopping")


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
  _state/
  _reports/
```

- `sources/`: one durable note per saved source.
- `topics/`: living synthesis pages maintained organically from sources.
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
ingest_status: pending | ingested | reference | blocked | skipped
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

Raindrop collection IDs:

- `0`: all bookmarks.
- `-1`: Unsorted.
- `-99`: Trash.

Do not write back to Raindrop until read-only inventory and local ingest have
been verified.

## Generated Files

`index.md` is a rebuildable content map. `_state/` and `_reports/` are generated
agent work products. They are useful, but they do not define the ontology.
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
        root / "_state",
        root / "_reports",
    ):
        if not directory.exists():
            directory.mkdir(parents=True, exist_ok=True)
            created.append(str(directory))

    files = {
        root / "rules.md": BOOTSTRAP_RULES.format(date=today()),
        root / "AGENTS.md": BOOTSTRAP_AGENTS,
        root / "index.md": f"---\ntype: index\nupdated: \"{utc_now().isoformat()}\"\npage_count: 0\n---\n\n# Wiki Index\n\n## Sources\n\n## Topics\n",
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


def api_get(path: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
    token = get_token()
    url = f"{API_BASE}{path}"
    if params:
        url = f"{url}?{urllib.parse.urlencode(params)}"
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:500]
        raise SystemExit(f"Raindrop API error {exc.code} for {path}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise SystemExit(f"Could not reach Raindrop API for {path}: {exc.reason}") from exc


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


def http_get(url: str, timeout: int = 35, max_bytes: int = 1_500_000) -> tuple[str, bytes]:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X) Codex LLM Wiki/1.0",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,text/plain;q=0.8,*/*;q=0.5",
        },
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        content_type = response.headers.get("content-type", "")
        body = response.read(max_bytes + 1)
    if len(body) > max_bytes:
        raise ValueError(f"response exceeded {max_bytes} bytes")
    return content_type, body


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
        return {
            "source_type": "reference",
            "ingest_status": "blocked",
            "title": "",
            "summary": "Could not extract readable content during the first-pass ingest.",
            "extract": "",
            "error": f"{type(exc).__name__}: {exc}",
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
    if extraction.get("ingest_status") == "blocked" and item_excerpt:
        summary = f"{item_excerpt}\n\nFetch blocked during first-pass ingest: {extraction.get('error')}"
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


def note_title(path: Path) -> str:
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return path.stem
    match = re.search(r"(?m)^#\s+(.+)$", text)
    return clean_text(match.group(1), 140) if match else path.stem


def rebuild_index(root: Path) -> Path:
    source_paths = sorted((root / "sources").glob("*.md"))
    topic_paths = sorted((root / "topics").glob("*.md"))
    lines = [
        "---",
        "type: index",
        f"updated: {yaml_value(utc_now().isoformat())}",
        f"page_count: {len(source_paths) + len(topic_paths)}",
        "---",
        "",
        "# Wiki Index",
        "",
        f"## Sources ({len(source_paths)})",
        "",
    ]
    for path in source_paths:
        lines.append(f"- [[{path.stem}]] - {markdown_escape(note_title(path))}")
    lines.extend(["", f"## Topics ({len(topic_paths)})", ""])
    for path in topic_paths:
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
