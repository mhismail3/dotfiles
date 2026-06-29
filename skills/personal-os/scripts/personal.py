#!/usr/bin/env python3
"""Private Personal OS helper for Codex.

This script is intentionally file-first and reversible. It writes only inside
~/.codex/personal-os unless a user explicitly invokes Things writeback or
LaunchAgent automation commands.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import plistlib
import re
import secrets
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

DEFAULT_ROOT = Path("~/.codex/personal-os").expanduser()
CHRONICLE_RESOURCES = Path("~/.codex/memories/extensions/chronicle/resources").expanduser()
THINGS_SCRIPT = Path("~/.codex/skills/things-3/scripts/things.py").expanduser()
LAUNCH_AGENT_LABEL = "com.moose.personal-os.daily"
LAUNCH_AGENT_PATH = Path("~/Library/LaunchAgents").expanduser() / f"{LAUNCH_AGENT_LABEL}.plist"

REQUIRED_DIRS = (
    "inbox",
    "journal",
    "episodes",
    "reflections/daily",
    "profile",
    "files",
    "_views",
    "_state",
    "_state/launchagents",
    "_reports",
    "_logs",
    "_logs/runs",
)

PROFILE_FILES = {
    "preference": "preferences.md",
    "pattern": "patterns.md",
    "routine": "routines.md",
    "value": "values.md",
}

ACTION_RE = re.compile(
    r"^\s*(?:[-*]\s*)?(?:\[\s\]\s*)?(?:(ACTION|TODO|NEXT|FOLLOW\s+UP)\s*[:\-]\s*)(.+?)\s*$",
    re.I,
)
CHECKBOX_RE = re.compile(r"^\s*[-*]\s+\[\s\]\s+(.+?)\s*$")
PROFILE_RE = re.compile(r"^\s*(?:[-*]\s*)?(preference|pattern|routine|value)\s*[:\-]\s*(.+?)\s*$", re.I)
UTC = dt.timezone.utc


def utc_now() -> dt.datetime:
    return dt.datetime.now(UTC).replace(microsecond=0)


def today() -> str:
    return dt.date.today().isoformat()


def parse_day(value: str | None) -> dt.date:
    if not value or value == "today":
        return dt.date.today()
    if value == "yesterday":
        return dt.date.today() - dt.timedelta(days=1)
    try:
        return dt.date.fromisoformat(value)
    except ValueError as exc:
        raise SystemExit(f"Use YYYY-MM-DD, today, or yesterday for dates: {value}") from exc


def slugify(value: str, fallback: str = "entry") -> str:
    value = value.casefold()
    value = re.sub(r"[^a-z0-9]+", "-", value)
    value = re.sub(r"-+", "-", value).strip("-")
    return value[:80] or fallback


def json_quote(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def frontmatter(fields: dict[str, Any]) -> str:
    lines = ["---"]
    for key, value in fields.items():
        if isinstance(value, list):
            rendered = "[" + ", ".join(json_quote(str(item)) for item in value) + "]"
        elif value is None:
            rendered = '""'
        elif isinstance(value, bool):
            rendered = "true" if value else "false"
        else:
            rendered = json_quote(str(value))
        lines.append(f"{key}: {rendered}")
    lines.append("---")
    return "\n".join(lines) + "\n"


def print_json(data: Any) -> None:
    print(json.dumps(data, indent=2, ensure_ascii=False, sort_keys=True))


def root_from_args(args: argparse.Namespace) -> Path:
    return Path(args.root).expanduser()


def relative(root: Path, path: Path) -> str:
    try:
        return str(path.resolve().relative_to(root.resolve()))
    except ValueError:
        return str(path.expanduser())


def ensure_root_exists(root: Path) -> None:
    if not root.exists():
        raise SystemExit(f"Personal OS root does not exist. Run bootstrap first: {root}")


def ensure_under_root(root: Path, path: Path) -> Path:
    resolved = path.expanduser().resolve()
    try:
        resolved.relative_to(root.resolve())
    except ValueError as exc:
        raise SystemExit(f"Refusing path outside Personal OS root: {path}") from exc
    return resolved


def read_stdin(args: argparse.Namespace) -> str:
    if not getattr(args, "stdin", False):
        raise SystemExit("This command requires --stdin for input text.")
    return sys.stdin.read().rstrip() + "\n"


def run_id() -> str:
    return utc_now().strftime("%Y%m%dT%H%M%SZ") + "-" + secrets.token_hex(3)


def run_command(cmd: list[str], input_text: str | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, input=input_text, text=True, capture_output=True, check=False)


def git_head(root: Path) -> str | None:
    if not (root / ".git").exists():
        return None
    proc = run_command(["git", "-C", str(root), "rev-parse", "--verify", "HEAD"])
    if proc.returncode != 0:
        return None
    return proc.stdout.strip()


def git_dirty(root: Path) -> bool:
    if not (root / ".git").exists():
        return False
    proc = run_command(["git", "-C", str(root), "status", "--porcelain"])
    return bool(proc.stdout.strip())


def ensure_private_git(root: Path) -> None:
    if not (root / ".git").exists():
        proc = run_command(["git", "-C", str(root), "init"])
        if proc.returncode != 0:
            raise SystemExit(proc.stderr.strip() or "git init failed")
    if run_command(["git", "-C", str(root), "config", "user.name"]).returncode != 0:
        run_command(["git", "-C", str(root), "config", "user.name", "Personal OS"])
    if run_command(["git", "-C", str(root), "config", "user.email"]).returncode != 0:
        run_command(["git", "-C", str(root), "config", "user.email", "personal-os@localhost"])


def commit_all(root: Path, message: str, no_commit: bool = False) -> str | None:
    if no_commit or not (root / ".git").exists():
        return git_head(root)
    run_command(["git", "-C", str(root), "add", "-A"])
    if not git_dirty(root):
        return git_head(root)
    proc = run_command(["git", "-C", str(root), "commit", "-m", message])
    if proc.returncode != 0:
        raise SystemExit(proc.stderr.strip() or "git commit failed")
    return git_head(root)


def load_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def write_text(path: Path, text: str, touched: list[Path]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    touched.append(path)


def write_json(path: Path, data: Any, touched: list[Path]) -> None:
    write_text(path, json.dumps(data, indent=2, ensure_ascii=False, sort_keys=True) + "\n", touched)


def append_text(path: Path, text: str, touched: list[Path]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(text)
    touched.append(path)


def start_run(args: argparse.Namespace, command: str, root: Path) -> dict[str, Any]:
    return {
        "run_id": run_id(),
        "command": command,
        "root": str(root),
        "started_at": utc_now().isoformat().replace("+00:00", "Z"),
        "finished_at": None,
        "git_commit_before": git_head(root),
        "git_commit_after": None,
        "files_touched": [],
        "things_created": [],
        "things_rolled_back": [],
        "automation": [],
        "rollback": [],
        "errors": [],
    }


def finish_run(
    args: argparse.Namespace,
    root: Path,
    record: dict[str, Any],
    touched: list[Path],
    commit_message: str,
) -> dict[str, Any]:
    record["finished_at"] = utc_now().isoformat().replace("+00:00", "Z")
    log_path = root / "_logs" / "runs" / f"{record['run_id']}.json"
    record["files_touched"] = sorted({relative(root, path) for path in [*touched, log_path]})
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text(json.dumps(record, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")
    content_commit = commit_all(root, commit_message, no_commit=args.no_commit)
    record["git_commit_after"] = content_commit
    log_path.write_text(json.dumps(record, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")
    if not args.no_commit:
        commit_all(root, f"personal-os: log {record['run_id']}", no_commit=False)
    return record


def launch_agent_plist(root: Path, disabled: bool = True) -> dict[str, Any]:
    script = Path(__file__).resolve()
    return {
        "Label": LAUNCH_AGENT_LABEL,
        "ProgramArguments": [
            sys.executable,
            str(script),
            "--root",
            str(root),
            "reflect",
            "daily",
            "--date",
            "today",
            "--write",
        ],
        "StartCalendarInterval": {"Hour": 22, "Minute": 30},
        "RunAtLoad": False,
        "Disabled": disabled,
        "StandardOutPath": str(root / "_logs" / "automation.out.log"),
        "StandardErrorPath": str(root / "_logs" / "automation.err.log"),
        "WorkingDirectory": str(root),
    }


def write_plist(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as handle:
        plistlib.dump(data, handle, sort_keys=True)


def seed_rules() -> str:
    return """---
type: rules
version: 1
privacy: private
---

# Personal OS Rules

Personal OS is private by default. Raw journal entries and episodes stay here.
The external LLM wiki receives only explicit promotion candidates. Codex memory
under `~/.codex/memories` is operational memory and must not be used as the
personal journal.

## Reversibility

- Side effects require explicit commands.
- File writes are committed to this local git repo.
- Things writes are recorded in `_state/things-created.json`.
- Calendar writes are not allowed in v1.
- LaunchAgent automation is opt-in and reversible.

## Profile Notes

Profile notes may be updated automatically only from explicit profile candidate
lines in reflections. Every appended claim must cite a source file path.
"""


def seed_agents() -> str:
    return frontmatter(
        {
            "type": "agent_instructions",
            "privacy": "private",
            "version": 1,
        }
    ) + """
# Personal OS Agent Instructions

This folder contains private personal memory. Read it only for Personal OS,
journaling, reflection, or user-authorized introspection tasks.

Do not copy raw personal content into `~/.codex/wiki` or `~/.codex/memories`.
Use `~/.codex/skills/personal-os/scripts/personal.py` for writes.
"""


def profile_seed(kind: str) -> str:
    title = PROFILE_FILES[kind].replace(".md", "").replace("-", " ").title()
    return frontmatter(
        {
            "type": "profile_note",
            "status": "reviewed",
            "kind": kind,
            "privacy": "private",
            "created": today(),
            "updated": today(),
            "sources": [],
        }
    ) + f"\n# {title}\n\n## Entries\n\n"


def collect_notes(root: Path) -> list[dict[str, Any]]:
    notes: list[dict[str, Any]] = []
    for base in ("journal", "episodes", "reflections", "profile", "files"):
        for path in sorted((root / base).glob("**/*.md")):
            try:
                text = path.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                continue
            stat = path.stat()
            title_match = re.search(r"(?m)^#\s+(.+)$", text)
            notes.append(
                {
                    "path": relative(root, path),
                    "title": title_match.group(1).strip() if title_match else path.stem,
                    "mtime": dt.datetime.fromtimestamp(stat.st_mtime, UTC).isoformat().replace("+00:00", "Z"),
                    "kind": base,
                }
            )
    notes.sort(key=lambda row: row["mtime"], reverse=True)
    return notes


def render_index(root: Path) -> str:
    notes = collect_notes(root)
    lines = [
        frontmatter({"type": "index", "updated": utc_now().isoformat().replace("+00:00", "Z"), "page_count": len(notes)}).rstrip(),
        "",
        "# Personal OS Index",
        "",
        "## Recent Notes",
        "",
    ]
    for note in notes[:120]:
        lines.append(f"- [{note['title']}]({note['path']}) - `{note['kind']}`; updated {note['mtime']}")
    lines.append("")
    return "\n".join(lines)


def cmd_bootstrap(args: argparse.Namespace) -> None:
    root = root_from_args(args)
    root.mkdir(parents=True, exist_ok=True)
    for name in REQUIRED_DIRS:
        (root / name).mkdir(parents=True, exist_ok=True)
    ensure_private_git(root)
    record = start_run(args, "bootstrap", root)
    touched: list[Path] = []

    seeds = {
        root / "rules.md": seed_rules(),
        root / "AGENTS.md": seed_agents(),
        root / "index.md": render_index(root),
        root / ".gitignore": "_logs/*.log\n.DS_Store\n",
    }
    for path, text in seeds.items():
        if not path.exists():
            write_text(path, text, touched)

    for kind, filename in PROFILE_FILES.items():
        path = root / "profile" / filename
        if not path.exists():
            write_text(path, profile_seed(kind), touched)

    template_path = root / "_state" / "launchagents" / f"{LAUNCH_AGENT_LABEL}.plist"
    write_plist(template_path, launch_agent_plist(root, disabled=True))
    touched.append(template_path)
    write_text(root / "index.md", render_index(root), touched)
    record["rollback"].append("Remove ~/.codex/personal-os only if you want to delete the private Personal OS root.")
    finish_run(args, root, record, touched, "personal-os: bootstrap")
    print_json({"root": str(root), "run_id": record["run_id"], "status": "bootstrapped"})


def journal_path(root: Path, day: dt.date) -> Path:
    return root / "journal" / str(day.year) / f"{day.year}-{day.month:02d}" / f"{day.isoformat()}.md"


def episode_path(root: Path, day: dt.date, title: str) -> Path:
    return root / "episodes" / str(day.year) / f"{day.isoformat()}-{slugify(title)}.md"


def cmd_capture_journal(args: argparse.Namespace) -> None:
    root = root_from_args(args)
    ensure_root_exists(root)
    text = read_stdin(args)
    day = parse_day(args.date)
    path = journal_path(root, day)
    record = start_run(args, "capture journal", root)
    touched: list[Path] = []
    if not path.exists():
        body = frontmatter(
            {
                "type": "journal_entry",
                "date": day.isoformat(),
                "privacy": "private",
                "created": utc_now().isoformat().replace("+00:00", "Z"),
                "updated": utc_now().isoformat().replace("+00:00", "Z"),
                "tags": [],
            }
        ) + f"\n# Journal {day.isoformat()}\n\n"
        write_text(path, body, touched)
    append_text(path, f"## {args.title}\n\n{text}\n", touched)
    write_text(root / "index.md", render_index(root), touched)
    record["rollback"].append(f"Use git revert for the commit, or edit {relative(root, path)} to remove this journal section.")
    finish_run(args, root, record, touched, f"personal-os: capture journal {day.isoformat()}")
    print_json({"path": str(path), "run_id": record["run_id"]})


def cmd_capture_episode(args: argparse.Namespace) -> None:
    root = root_from_args(args)
    ensure_root_exists(root)
    text = read_stdin(args)
    day = parse_day(args.date)
    path = episode_path(root, day, args.title)
    record = start_run(args, "capture episode", root)
    touched: list[Path] = []
    body = frontmatter(
        {
            "type": "episode",
            "source": args.source,
            "date": day.isoformat(),
            "privacy": "private",
            "created": utc_now().isoformat().replace("+00:00", "Z"),
            "updated": utc_now().isoformat().replace("+00:00", "Z"),
        }
    ) + f"\n# {args.title}\n\n{text}\n"
    write_text(path, body, touched)
    write_text(root / "index.md", render_index(root), touched)
    record["rollback"].append(f"Use git revert for the commit, or remove {relative(root, path)}.")
    finish_run(args, root, record, touched, f"personal-os: capture episode {day.isoformat()}")
    print_json({"path": str(path), "run_id": record["run_id"]})


def read_day_inputs(root: Path, day: dt.date, include_chronicle: bool = True) -> list[dict[str, str]]:
    inputs: list[dict[str, str]] = []
    jpath = journal_path(root, day)
    if jpath.exists():
        inputs.append({"kind": "journal", "path": str(jpath), "text": jpath.read_text(encoding="utf-8")})
    for path in sorted((root / "episodes").glob(f"**/{day.isoformat()}-*.md")):
        inputs.append({"kind": "episode", "path": str(path), "text": path.read_text(encoding="utf-8")})
    if include_chronicle and CHRONICLE_RESOURCES.exists():
        for path in sorted(CHRONICLE_RESOURCES.glob(f"{day.isoformat()}T*.md")):
            try:
                text = path.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                continue
            inputs.append({"kind": "chronicle", "path": str(path), "text": text})
    return inputs


def excerpt(text: str, limit: int = 900) -> str:
    clean = re.sub(r"\s+", " ", text).strip()
    if len(clean) <= limit:
        return clean
    return clean[: limit - 3].rstrip() + "..."


def explicit_actions_from_text(text: str) -> list[str]:
    actions: list[str] = []
    seen: set[str] = set()
    for line in text.splitlines():
        match = ACTION_RE.match(line) or CHECKBOX_RE.match(line)
        if match:
            title = match.group(match.lastindex or 1).strip()
            key = re.sub(r"\s+", " ", title.casefold()).strip()
            if len(title) >= 3 and key not in seen:
                seen.add(key)
                actions.append(title)
    return actions


def profile_candidates_from_text(text: str) -> list[dict[str, str]]:
    candidates: list[dict[str, str]] = []
    for line in text.splitlines():
        match = PROFILE_RE.match(line)
        if match:
            candidates.append({"kind": match.group(1).casefold(), "text": match.group(2).strip()})
    return candidates


def render_daily_reflection(root: Path, day: dt.date, inputs: list[dict[str, str]]) -> str:
    source_paths = [relative(root, Path(item["path"])) if str(item["path"]).startswith(str(root)) else item["path"] for item in inputs]
    lines = [
        frontmatter(
            {
                "type": "reflection",
                "period_start": day.isoformat(),
                "period_end": day.isoformat(),
                "status": "draft",
                "privacy": "private",
                "created": utc_now().isoformat().replace("+00:00", "Z"),
                "updated": utc_now().isoformat().replace("+00:00", "Z"),
                "inputs": source_paths,
            }
        ).rstrip(),
        "",
        f"# Daily Reflection {day.isoformat()}",
        "",
        "## Inputs",
        "",
    ]
    if not inputs:
        lines.append("- No journal, episode, or Chronicle inputs found.")
    for item in inputs:
        path_text = relative(root, Path(item["path"])) if str(item["path"]).startswith(str(root)) else item["path"]
        lines.append(f"- `{item['kind']}`: {path_text}")
    lines.extend(["", "## Evidence", ""])
    for item in inputs:
        path_text = relative(root, Path(item["path"])) if str(item["path"]).startswith(str(root)) else item["path"]
        lines.append(f"### {item['kind']}: {path_text}")
        lines.append("")
        lines.append(excerpt(item["text"]))
        lines.append("")
    actions = []
    for item in inputs:
        actions.extend(explicit_actions_from_text(item["text"]))
    lines.extend(["## Explicit Action Candidates", ""])
    if actions:
        for action in actions:
            lines.append(f"- [ ] {action}")
    else:
        lines.append("- None found.")
    lines.extend(
        [
            "",
            "## Profile Update Candidates",
            "",
            "Add explicit lines here when appropriate:",
            "",
            "- preference: ...",
            "- pattern: ...",
            "- routine: ...",
            "- value: ...",
            "",
            "## Notes",
            "",
            "Draft generated from available inputs. Edit before treating it as reviewed.",
            "",
        ]
    )
    return "\n".join(lines)


def reflection_path(root: Path, day: dt.date) -> Path:
    return root / "reflections" / "daily" / f"{day.isoformat()}.md"


def cmd_reflect_daily(args: argparse.Namespace) -> None:
    root = root_from_args(args)
    ensure_root_exists(root)
    day = parse_day(args.date)
    inputs = read_day_inputs(root, day, include_chronicle=not args.no_chronicle)
    rendered = render_daily_reflection(root, day, inputs)
    if not args.write:
        print(rendered)
        return
    path = reflection_path(root, day)
    record = start_run(args, "reflect daily", root)
    touched: list[Path] = []
    write_text(path, rendered, touched)
    write_text(root / "_views" / "calendar-candidates.md", calendar_candidates_stub(root), touched)
    write_text(root / "_views" / "wiki-promotion-candidates.md", wiki_promotion_stub(root), touched)
    write_text(root / "index.md", render_index(root), touched)
    record["rollback"].append(f"Use git revert for the commit, or remove {relative(root, path)}.")
    finish_run(args, root, record, touched, f"personal-os: daily reflection {day.isoformat()}")
    print_json({"path": str(path), "run_id": record["run_id"], "input_count": len(inputs)})


def calendar_candidates_stub(root: Path) -> str:
    return frontmatter({"type": "view", "view": "calendar-candidates", "updated": utc_now().isoformat().replace("+00:00", "Z")}) + "\n# Calendar Candidates\n\nCalendar writes are disabled in v1. Add reviewed candidates here manually.\n"


def wiki_promotion_stub(root: Path) -> str:
    return frontmatter({"type": "view", "view": "wiki-promotion-candidates", "updated": utc_now().isoformat().replace("+00:00", "Z")}) + "\n# Wiki Promotion Candidates\n\nNo raw personal content should be promoted. Add reviewed, non-sensitive synthesis candidates here.\n"


def cmd_profile_update(args: argparse.Namespace) -> None:
    root = root_from_args(args)
    ensure_root_exists(root)
    source = ensure_under_root(root, Path(args.from_reflection))
    text = source.read_text(encoding="utf-8")
    candidates = profile_candidates_from_text(text)
    if not args.apply:
        print_json({"source": relative(root, source), "candidates": candidates})
        return
    record = start_run(args, "profile update", root)
    touched: list[Path] = []
    by_file: dict[Path, list[str]] = {}
    for candidate in candidates:
        filename = PROFILE_FILES.get(candidate["kind"])
        if not filename:
            continue
        path = root / "profile" / filename
        line = f"- {candidate['text']} (source: `{relative(root, source)}`; added {today()})\n"
        by_file.setdefault(path, []).append(line)
    for path, lines in by_file.items():
        append_text(path, "".join(lines), touched)
    write_text(root / "index.md", render_index(root), touched)
    record["rollback"].append("Use git revert for the profile update commit.")
    finish_run(args, root, record, touched, "personal-os: profile update")
    print_json({"run_id": record["run_id"], "updated_files": [relative(root, path) for path in by_file]})


def action_plan_from_reflection(root: Path, source: Path) -> dict[str, Any]:
    text = source.read_text(encoding="utf-8")
    tasks = []
    for title in explicit_actions_from_text(text):
        tasks.append(
            {
                "title": title,
                "notes": f"Created from Personal OS reflection: {relative(root, source)}",
                "source": relative(root, source),
                "tag": "Personal OS",
            }
        )
    return {
        "type": "personal_os_action_plan",
        "created": utc_now().isoformat().replace("+00:00", "Z"),
        "source_reflection": relative(root, source),
        "tasks": tasks,
    }


def cmd_actions_plan(args: argparse.Namespace) -> None:
    root = root_from_args(args)
    ensure_root_exists(root)
    source = ensure_under_root(root, Path(args.from_reflection))
    plan = action_plan_from_reflection(root, source)
    if not args.write:
        print_json(plan)
        return
    record = start_run(args, "actions plan", root)
    touched: list[Path] = []
    plan_path = root / "_views" / f"action-plan-{record['run_id']}.json"
    write_json(plan_path, plan, touched)
    record["rollback"].append(f"Remove {relative(root, plan_path)} or use git revert.")
    finish_run(args, root, record, touched, "personal-os: action plan")
    print_json({"run_id": record["run_id"], "plan": str(plan_path), "task_count": len(plan["tasks"])})


def load_action_plan(root: Path, path: Path) -> dict[str, Any]:
    resolved = ensure_under_root(root, path)
    data = json.loads(resolved.read_text(encoding="utf-8"))
    if data.get("type") != "personal_os_action_plan":
        raise SystemExit(f"Not a Personal OS action plan: {path}")
    return data


def call_things(args: list[str]) -> Any:
    if not THINGS_SCRIPT.exists():
        raise SystemExit(f"Things helper not found: {THINGS_SCRIPT}")
    proc = run_command([str(THINGS_SCRIPT), *args])
    if proc.returncode != 0:
        raise SystemExit(proc.stderr.strip() or proc.stdout.strip() or "Things helper failed")
    return json.loads(proc.stdout)


def verify_things_item(item_id: str) -> list[dict[str, Any]]:
    snapshot = call_things(["snapshot"])
    return [todo for todo in snapshot.get("todos", []) if str(todo.get("id")) == str(item_id)]


def things_effective_status(item: dict[str, Any]) -> str:
    if item.get("cancellationDate"):
        return "canceled"
    if item.get("completionDate"):
        return "completed"
    return str(item.get("status") or "unknown")


def things_state_path(root: Path) -> Path:
    return root / "_state" / "things-created.json"


def cmd_actions_apply(args: argparse.Namespace) -> None:
    root = root_from_args(args)
    ensure_root_exists(root)
    plan_path = ensure_under_root(root, Path(args.plan))
    plan = load_action_plan(root, plan_path)
    record = start_run(args, "actions apply", root)
    touched: list[Path] = []
    state = load_json(things_state_path(root), [])
    created = []
    for task in plan.get("tasks", []):
        title = str(task.get("title", "")).strip()
        if not title:
            continue
        notes = f"{task.get('notes', '')}\n\nPersonal OS run: {record['run_id']}"
        result = call_things(["add", title, "--notes", notes, "--tag", "Personal OS", "--list", "Inbox"])
        item_id = result.get("id") or result.get("uuid") or result.get("identifier")
        created_row = {
            "id": item_id,
            "title": result.get("name", title),
            "source": task.get("source", plan.get("source_reflection", "")),
            "plan": relative(root, plan_path),
            "run_id": record["run_id"],
            "created_at": utc_now().isoformat().replace("+00:00", "Z"),
            "rolled_back": False,
        }
        created.append(created_row)
        state.append(created_row)
        if item_id:
            created_row["creation_verification"] = verify_things_item(str(item_id))
            if created_row["creation_verification"]:
                created_row["creation_effective_status"] = things_effective_status(created_row["creation_verification"][0])
    write_json(things_state_path(root), state, touched)
    record["things_created"] = created
    record["rollback"].append(f"Run `personal.py actions rollback --run-id {record['run_id']}` to cancel created Things tasks.")
    finish_run(args, root, record, touched, "personal-os: apply Things actions")
    print_json({"run_id": record["run_id"], "created": created})


def cmd_actions_rollback(args: argparse.Namespace) -> None:
    root = root_from_args(args)
    ensure_root_exists(root)
    state_path = things_state_path(root)
    state = load_json(state_path, [])
    targets = [row for row in state if row.get("run_id") == args.run_id and not row.get("rolled_back")]
    if not targets:
        print_json({"run_id": args.run_id, "rolled_back": [], "message": "No active Things tasks found for run."})
        return
    record = start_run(args, "actions rollback", root)
    touched: list[Path] = []
    rolled_back = []
    for row in targets:
        item_id = row.get("id")
        if item_id:
            try:
                call_things(["cancel", str(item_id)])
                row["rollback_verification"] = verify_things_item(str(item_id))
                if row["rollback_verification"]:
                    row["rollback_effective_status"] = things_effective_status(row["rollback_verification"][0])
                row["rolled_back"] = True
                row["rolled_back_at"] = utc_now().isoformat().replace("+00:00", "Z")
                rolled_back.append(row)
            except SystemExit as exc:
                record["errors"].append(str(exc))
    write_json(state_path, state, touched)
    record["things_rolled_back"] = rolled_back
    record["rollback"].append("Rollback command only cancels tasks created by the target Personal OS run.")
    finish_run(args, root, record, touched, "personal-os: rollback Things actions")
    print_json({"run_id": record["run_id"], "rolled_back": rolled_back, "errors": record["errors"]})


def cmd_automation_install(args: argparse.Namespace) -> None:
    root = root_from_args(args)
    ensure_root_exists(root)
    record = start_run(args, "automation install", root)
    touched: list[Path] = []
    write_plist(LAUNCH_AGENT_PATH, launch_agent_plist(root, disabled=True))
    record["automation"].append({"action": "install", "path": str(LAUNCH_AGENT_PATH), "loaded": False})
    record["rollback"].append("Run `personal.py automation uninstall` to remove the LaunchAgent plist.")
    finish_run(args, root, record, touched, "personal-os: install automation")
    print_json({"run_id": record["run_id"], "plist": str(LAUNCH_AGENT_PATH), "loaded": False})


def launchctl(*args: str) -> dict[str, Any]:
    proc = run_command(["launchctl", *args])
    return {"args": list(args), "returncode": proc.returncode, "stdout": proc.stdout.strip(), "stderr": proc.stderr.strip()}


def cmd_automation_enable(args: argparse.Namespace) -> None:
    root = root_from_args(args)
    ensure_root_exists(root)
    if not LAUNCH_AGENT_PATH.exists():
        raise SystemExit("LaunchAgent is not installed. Run automation install first.")
    record = start_run(args, "automation enable", root)
    touched: list[Path] = []
    write_plist(LAUNCH_AGENT_PATH, launch_agent_plist(root, disabled=False))
    uid = str(os.getuid())
    results = [
        launchctl("bootout", f"gui/{uid}", str(LAUNCH_AGENT_PATH)),
        launchctl("bootstrap", f"gui/{uid}", str(LAUNCH_AGENT_PATH)),
        launchctl("enable", f"gui/{uid}/{LAUNCH_AGENT_LABEL}"),
    ]
    record["automation"].append({"action": "enable", "path": str(LAUNCH_AGENT_PATH), "launchctl": results})
    record["rollback"].append("Run `personal.py automation disable` to unload the LaunchAgent.")
    finish_run(args, root, record, touched, "personal-os: enable automation")
    print_json({"run_id": record["run_id"], "launchctl": results})


def cmd_automation_disable(args: argparse.Namespace) -> None:
    root = root_from_args(args)
    ensure_root_exists(root)
    record = start_run(args, "automation disable", root)
    touched: list[Path] = []
    uid = str(os.getuid())
    results = [launchctl("bootout", f"gui/{uid}", str(LAUNCH_AGENT_PATH))]
    if LAUNCH_AGENT_PATH.exists():
        write_plist(LAUNCH_AGENT_PATH, launch_agent_plist(root, disabled=True))
    record["automation"].append({"action": "disable", "path": str(LAUNCH_AGENT_PATH), "launchctl": results})
    record["rollback"].append("Run `personal.py automation enable` to load the LaunchAgent again.")
    finish_run(args, root, record, touched, "personal-os: disable automation")
    print_json({"run_id": record["run_id"], "launchctl": results})


def cmd_automation_uninstall(args: argparse.Namespace) -> None:
    root = root_from_args(args)
    ensure_root_exists(root)
    record = start_run(args, "automation uninstall", root)
    touched: list[Path] = []
    uid = str(os.getuid())
    results = [launchctl("bootout", f"gui/{uid}", str(LAUNCH_AGENT_PATH))]
    removed = False
    if LAUNCH_AGENT_PATH.exists():
        LAUNCH_AGENT_PATH.unlink()
        removed = True
    record["automation"].append({"action": "uninstall", "path": str(LAUNCH_AGENT_PATH), "removed": removed, "launchctl": results})
    record["rollback"].append("Run `personal.py automation install` to recreate the disabled LaunchAgent plist.")
    finish_run(args, root, record, touched, "personal-os: uninstall automation")
    print_json({"run_id": record["run_id"], "removed": removed, "launchctl": results})


def cmd_scan_recent(args: argparse.Namespace) -> None:
    root = root_from_args(args)
    ensure_root_exists(root)
    print_json({"root": str(root), "items": collect_notes(root)[: args.limit]})


def cmd_index(args: argparse.Namespace) -> None:
    root = root_from_args(args)
    ensure_root_exists(root)
    rendered = render_index(root)
    if not args.write:
        print(rendered)
        return
    record = start_run(args, "index", root)
    touched: list[Path] = []
    write_text(root / "index.md", rendered, touched)
    record["rollback"].append("Use git revert for the index update commit.")
    finish_run(args, root, record, touched, "personal-os: update index")
    print_json({"run_id": record["run_id"], "index": str(root / "index.md")})


def verify_frontmatter(root: Path) -> list[str]:
    errors: list[str] = []
    for path in root.glob("**/*.md"):
        if ".git" in path.parts:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            errors.append(f"Non-UTF8 Markdown file: {relative(root, path)}")
            continue
        if not text.startswith("---\n"):
            errors.append(f"Missing frontmatter: {relative(root, path)}")
    return errors


def verify_run_logs(root: Path, run_logs: list[Path]) -> tuple[list[str], dict[str, Any]]:
    errors: list[str] = []
    latest_daily: dict[str, Any] | None = None
    for path in run_logs:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            errors.append(f"Invalid run log JSON: {relative(root, path)}")
            continue
        for field in ("run_id", "command", "started_at", "finished_at", "rollback"):
            if field not in data:
                errors.append(f"Run log missing {field}: {relative(root, path)}")
        for touched in data.get("files_touched", []):
            touched_path = root / touched
            if not touched_path.exists():
                errors.append(f"Run log touched missing file: {relative(root, path)} -> {touched}")
        if data.get("things_created") and data.get("command") != "actions apply":
            errors.append(f"Unexpected Things creation log: {relative(root, path)}")
        if data.get("command") == "reflect daily":
            if latest_daily is None or str(data.get("started_at", "")) > str(latest_daily.get("started_at", "")):
                latest_daily = data
    return errors, latest_daily or {}


def launch_agent_state(root: Path) -> dict[str, Any]:
    template_path = root / "_state" / "launchagents" / f"{LAUNCH_AGENT_LABEL}.plist"
    state: dict[str, Any] = {
        "template_path": str(template_path),
        "template_exists": template_path.exists(),
        "installed_path": str(LAUNCH_AGENT_PATH),
        "installed": LAUNCH_AGENT_PATH.exists(),
        "installed_disabled": None,
        "launchctl_loaded": False,
        "launchctl_detail": "",
    }
    if LAUNCH_AGENT_PATH.exists():
        try:
            with LAUNCH_AGENT_PATH.open("rb") as handle:
                state["installed_disabled"] = bool(plistlib.load(handle).get("Disabled", False))
        except Exception as exc:  # plistlib can raise several parse errors.
            state["installed_error"] = str(exc)
    uid = str(os.getuid())
    result = launchctl("print", f"gui/{uid}/{LAUNCH_AGENT_LABEL}")
    state["launchctl_loaded"] = result["returncode"] == 0
    state["launchctl_detail"] = result["stdout"] or result["stderr"]
    return state


def verify_things_state(root: Path) -> list[str]:
    errors: list[str] = []
    state_path = things_state_path(root)
    if not state_path.exists():
        return errors
    try:
        data = json.loads(state_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return [f"Invalid Things state JSON: {relative(root, state_path)}"]
    if not isinstance(data, list):
        return [f"Things state must be a list: {relative(root, state_path)}"]
    for index, row in enumerate(data):
        if not isinstance(row, dict):
            errors.append(f"Things state row is not an object at index {index}")
            continue
        for field in ("id", "title", "source", "run_id", "created_at", "rolled_back"):
            if field not in row:
                errors.append(f"Things state row {index} missing {field}")
        if row.get("rolled_back") and row.get("rollback_effective_status") not in ("canceled", "completed"):
            errors.append(f"Things state row {index} marked rolled_back without canceled/completed verification")
    return errors


def cmd_verify(args: argparse.Namespace) -> None:
    root = root_from_args(args)
    errors: list[str] = []
    missing_dirs = [name for name in REQUIRED_DIRS if not (root / name).is_dir()]
    errors.extend(f"Missing directory: {name}" for name in missing_dirs)
    for name in ("AGENTS.md", "rules.md", "index.md"):
        if not (root / name).exists():
            errors.append(f"Missing file: {name}")
    errors.extend(verify_frontmatter(root) if root.exists() else ["Root missing"])
    git_status = None
    if (root / ".git").exists():
        proc = run_command(["git", "-C", str(root), "status", "--porcelain"])
        git_status = proc.stdout.strip()
    else:
        errors.append("Missing private git repo")
    run_logs = sorted((root / "_logs" / "runs").glob("*.json")) if root.exists() else []
    run_log_errors, latest_daily_run = verify_run_logs(root, run_logs)
    errors.extend(run_log_errors)
    errors.extend(verify_things_state(root) if root.exists() else [])
    automation = launch_agent_state(root) if root.exists() else {}
    if root.exists() and not automation.get("template_exists"):
        errors.append("Missing disabled LaunchAgent template in _state/launchagents")
    latest_daily_reflection = None
    if root.exists():
        reflection_files = sorted((root / "reflections" / "daily").glob("*.md"), reverse=True)
        latest_daily_reflection = relative(root, reflection_files[0]) if reflection_files else None
    print_json(
        {
            "root": str(root),
            "ok": not errors,
            "errors": errors,
            "git_head": git_head(root),
            "git_dirty": bool(git_status),
            "git_status": git_status,
            "automation": automation,
            "latest_daily_reflection": latest_daily_reflection,
            "latest_daily_run_id": latest_daily_run.get("run_id"),
            "latest_daily_run_at": latest_daily_run.get("started_at"),
            "run_log_count": len(run_logs),
        }
    )
    if errors:
        raise SystemExit(1)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Maintain the private Personal OS memory layer.")
    parser.add_argument("--root", default=str(DEFAULT_ROOT), help="Personal OS root. Defaults to ~/.codex/personal-os.")
    parser.add_argument("--no-commit", action="store_true", help="Write files without committing the Personal OS git repo.")
    sub = parser.add_subparsers(dest="command", required=True)

    bootstrap = sub.add_parser("bootstrap", help="Create the Personal OS root.")
    bootstrap.set_defaults(func=cmd_bootstrap)

    verify = sub.add_parser("verify", help="Verify Personal OS structure and state.")
    verify.set_defaults(func=cmd_verify)

    capture = sub.add_parser("capture", help="Capture journal or episode text.")
    capture_sub = capture.add_subparsers(dest="capture_command", required=True)
    journal = capture_sub.add_parser("journal", help="Append a journal section for a day.")
    journal.add_argument("--title", required=True)
    journal.add_argument("--date", default="today")
    journal.add_argument("--stdin", action="store_true")
    journal.set_defaults(func=cmd_capture_journal)
    episode = capture_sub.add_parser("episode", help="Create an explicit episode note.")
    episode.add_argument("--source", choices=("codex", "chronicle", "manual"), required=True)
    episode.add_argument("--title", required=True)
    episode.add_argument("--date", default="today")
    episode.add_argument("--stdin", action="store_true")
    episode.set_defaults(func=cmd_capture_episode)

    reflect = sub.add_parser("reflect", help="Generate reflections.")
    reflect_sub = reflect.add_subparsers(dest="reflect_command", required=True)
    daily = reflect_sub.add_parser("daily", help="Generate a daily reflection.")
    daily.add_argument("--date", default="today")
    daily.add_argument("--write", action="store_true")
    daily.add_argument("--no-chronicle", action="store_true")
    daily.set_defaults(func=cmd_reflect_daily)

    profile = sub.add_parser("profile", help="Work with durable profile notes.")
    profile_sub = profile.add_subparsers(dest="profile_command", required=True)
    profile_update = profile_sub.add_parser("update", help="Apply explicit profile candidates from a reflection.")
    profile_update.add_argument("--from-reflection", required=True)
    profile_update.add_argument("--apply", action="store_true")
    profile_update.set_defaults(func=cmd_profile_update)

    actions = sub.add_parser("actions", help="Plan, apply, or rollback Things actions.")
    actions_sub = actions.add_subparsers(dest="actions_command", required=True)
    actions_plan = actions_sub.add_parser("plan", help="Extract explicit Things action candidates.")
    actions_plan.add_argument("--from-reflection", required=True)
    actions_plan.add_argument("--write", action="store_true")
    actions_plan.set_defaults(func=cmd_actions_plan)
    actions_apply = actions_sub.add_parser("apply", help="Create Things tasks from an action plan.")
    actions_apply.add_argument("--plan", required=True)
    actions_apply.set_defaults(func=cmd_actions_apply)
    actions_rollback = actions_sub.add_parser("rollback", help="Cancel Things tasks created by a Personal OS run.")
    actions_rollback.add_argument("--run-id", required=True)
    actions_rollback.set_defaults(func=cmd_actions_rollback)

    automation = sub.add_parser("automation", help="Install, enable, disable, or uninstall daily automation.")
    automation_sub = automation.add_subparsers(dest="automation_command", required=True)
    automation_install = automation_sub.add_parser("install", help="Install disabled LaunchAgent plist.")
    automation_install.set_defaults(func=cmd_automation_install)
    automation_enable = automation_sub.add_parser("enable", help="Enable and load the LaunchAgent.")
    automation_enable.set_defaults(func=cmd_automation_enable)
    automation_disable = automation_sub.add_parser("disable", help="Disable and unload the LaunchAgent.")
    automation_disable.set_defaults(func=cmd_automation_disable)
    automation_uninstall = automation_sub.add_parser("uninstall", help="Unload and remove the LaunchAgent plist.")
    automation_uninstall.set_defaults(func=cmd_automation_uninstall)

    scan = sub.add_parser("scan", help="Inspect Personal OS.")
    scan_sub = scan.add_subparsers(dest="scan_command", required=True)
    recent = scan_sub.add_parser("recent", help="List recent notes.")
    recent.add_argument("--limit", type=int, default=30)
    recent.set_defaults(func=cmd_scan_recent)

    index = sub.add_parser("index", help="Print or write the Personal OS index.")
    index.add_argument("--write", action="store_true")
    index.set_defaults(func=cmd_index)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    args.func(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
