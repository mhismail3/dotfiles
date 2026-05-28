#!/usr/bin/env python3
"""Export, import, and sync this Codex setup between machines.

The script intentionally separates portable configuration from sensitive or
machine-specific runtime state. It can include UI preferences and session
transcripts when explicitly requested.
"""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import json
import os
import platform
import re
import shutil
import sqlite3
import sys
import tarfile
import tempfile
import tomllib
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable


DEFAULT_RESEARCH_MAP = Path.home() / ".codex" / "portable" / "codex-config-research-map.md"

CODEX_TOP_FILES = [
    "config.toml",
    "AGENTS.md",
    "hooks.json",
]

UI_CODEX_HOME_FILES = [
    ".codex-global-state.json",
    ".codex-global-state.json.bak",
    ".personality_migration",
]

APP_SUPPORT_FILES = [
    "Preferences",
    "Local State",
    "browser-sidebar-local-servers.json",
]

SESSION_TOP_FILES = [
    "session_index.jsonl",
]

ACTIVE_SESSION_DIRS = [
    "sessions",
    "archived_sessions",
]

RUNTIME_DBS = [
    "state_5.sqlite",
    "logs_2.sqlite",
]

PORTABLE_CONFIG_NAME = "config.json"
LOCK_NAME = ".codex-portable.lock"

TOML_TABLE_RE = re.compile(r"^\s*(\[\[?)\s*([^\]]+?)\s*(\]\]?)\s*(?:#.*)?$")
TOML_KEY_RE = re.compile(r"^\s*([A-Za-z0-9_-]+)\s*=")

EXCLUDED_NAMES = {
    ".DS_Store",
    "__pycache__",
    "backups",
}

EXCLUDED_SUFFIXES = (
    ".pyc",
    ".sqlite-shm",
    ".sqlite-wal",
)

SECRET_NAMES = {
    "auth.json",
    "installation_id",
}

TEXT_SUFFIXES = {
    ".json",
    ".jsonl",
    ".md",
    ".mjs",
    ".py",
    ".toml",
    ".txt",
    ".yaml",
    ".yml",
}


def stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")


def iso_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def home_path() -> Path:
    return Path.home()


def codex_home() -> Path:
    return Path(os.environ.get("CODEX_HOME", str(home_path() / ".codex"))).expanduser()


def app_support_dir(home: Path | None = None) -> Path:
    h = home or home_path()
    return h / "Library" / "Application Support" / "Codex"


def portable_dir() -> Path:
    return codex_home() / "portable"


def portable_config_path() -> Path:
    return portable_dir() / PORTABLE_CONFIG_NAME


def default_icloud_remote(home: Path | None = None) -> Path:
    h = home or home_path()
    icloud_documents = h / "Library" / "Mobile Documents" / "com~apple~CloudDocs" / "Documents"
    if icloud_documents.exists():
        return icloud_documents / "CodexPortable"
    return h / "Documents" / "CodexPortable"


def host_key() -> str:
    raw = platform.node() or "unknown-host"
    return re.sub(r"[^A-Za-z0-9_.-]+", "-", raw).strip("-") or "unknown-host"


def audit_session_sources_dir(codex: Path) -> Path:
    return codex / "audit" / "session_sources"


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(2)


def ensure_empty_dir(path: Path, force: bool = False) -> None:
    if path.exists():
        if not force and any(path.iterdir()):
            fail(f"{path} already exists and is not empty; pass --force or choose another path")
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def should_skip(path: Path, include_auth: bool = False) -> bool:
    if path.name in EXCLUDED_NAMES:
        return True
    if path.suffix in EXCLUDED_SUFFIXES:
        return True
    if not include_auth and path.name in SECRET_NAMES:
        return True
    return False


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def derive_session_id(path: Path) -> str:
    stem = path.stem
    match = re.search(r"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$", stem, re.I)
    return match.group(1).lower() if match else stem


def discover_session_id(path: Path) -> str:
    try:
        with path.open("rb") as fh:
            for _, raw in zip(range(50), fh):
                try:
                    obj = json.loads(raw.decode("utf-8"))
                except Exception:
                    continue
                if obj.get("type") == "session_meta" and isinstance(obj.get("payload"), dict):
                    session_id = obj["payload"].get("id")
                    if isinstance(session_id, str) and session_id:
                        return session_id.lower()
    except OSError:
        pass
    return derive_session_id(path)


def copy_file(src: Path, dst: Path) -> bool:
    if not src.is_file():
        return False
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    return True


def copy_tree(src: Path, dst: Path, include_auth: bool = False) -> bool:
    if not src.is_dir():
        return False
    if dst.exists():
        shutil.rmtree(dst)
    dst.parent.mkdir(parents=True, exist_ok=True)

    def ignore(directory: str, names: list[str]) -> set[str]:
        skipped: set[str] = set()
        base = Path(directory)
        for name in names:
            if should_skip(base / name, include_auth=include_auth):
                skipped.add(name)
        return skipped

    shutil.copytree(src, dst, ignore=ignore, symlinks=True)
    return True


def copy_sqlite_snapshot(src: Path, dst: Path) -> bool:
    if not src.is_file():
        return False
    dst.parent.mkdir(parents=True, exist_ok=True)
    try:
        source = sqlite3.connect(f"file:{src}?mode=ro", uri=True)
        target = sqlite3.connect(dst)
        with target:
            source.backup(target)
        source.close()
        target.close()
    except sqlite3.Error:
        copy_file(src, dst)
    return True


def collect_files(root: Path) -> list[dict[str, str | int]]:
    result: list[dict[str, str | int]] = []
    if not root.exists():
        return result
    for path in sorted(p for p in root.rglob("*") if p.is_file()):
        rel = path.relative_to(root).as_posix()
        result.append({"path": rel, "size": path.stat().st_size, "sha256": sha256(path)})
    return result


def write_json(path: Path, data: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")


def read_json_file(path: Path) -> object | None:
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def load_portable_config() -> dict[str, object]:
    path = portable_config_path()
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        fail(f"invalid portable config {path}: {exc}")
    if not isinstance(data, dict):
        fail(f"invalid portable config {path}: top-level JSON value must be an object")
    return data


def save_portable_config(data: dict[str, object]) -> None:
    write_json(portable_config_path(), data)


def resolve_remote(value: str | None = None, *, create: bool = False) -> Path:
    if value:
        remote = Path(value).expanduser().resolve()
    else:
        config = load_portable_config()
        configured = config.get("remote")
        if not isinstance(configured, str) or not configured:
            fail("missing remote; pass --remote or run `codex_portable.py configure --icloud --create`")
        remote = Path(configured).expanduser().resolve()
    if create:
        remote.mkdir(parents=True, exist_ok=True)
    elif not remote.exists():
        fail(f"remote does not exist: {remote}")
    return remote


def configured_bool(name: str, fallback: bool = False) -> bool:
    value = load_portable_config().get(name, fallback)
    return bool(value)


@contextlib.contextmanager
def remote_lock(remote: Path, *, force: bool = False):
    lock = remote / LOCK_NAME
    payload = {
        "created_at": iso_now(),
        "host": platform.node(),
        "pid": os.getpid(),
        "remote": str(remote),
    }
    encoded = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    try:
        fd = os.open(lock, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        existing = ""
        try:
            existing = lock.read_text()
        except OSError:
            existing = "<unreadable lock file>"
        if not force:
            fail(f"remote is locked at {lock}; remove stale lock or pass --force-lock\n{existing}")
        lock.unlink(missing_ok=True)
        fd = os.open(lock, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(encoded)
    try:
        yield
    finally:
        lock.unlink(missing_ok=True)


def safe_extract(tar: tarfile.TarFile, destination: Path) -> None:
    root = destination.resolve()
    for member in tar.getmembers():
        target = (root / member.name).resolve()
        if target != root and root not in target.parents:
            fail(f"unsafe archive member path: {member.name}")
    tar.extractall(root)


def verify_bundle_contents(bundle: Path) -> None:
    manifest_files = bundle / "manifest-files.json"
    if not manifest_files.is_file():
        fail(f"missing manifest-files.json in {bundle}")
    entries = json.loads(manifest_files.read_text())
    if not isinstance(entries, list):
        fail(f"invalid manifest-files.json in {bundle}: expected a list")
    checked = 0
    for entry in entries:
        if not isinstance(entry, dict):
            fail("invalid manifest-files.json entry")
        rel = entry.get("path")
        expected_hash = entry.get("sha256")
        expected_size = entry.get("size")
        if not isinstance(rel, str) or not isinstance(expected_hash, str):
            fail("invalid manifest-files.json entry shape")
        path = bundle / rel
        if not path.is_file():
            fail(f"bundle file missing: {rel}")
        if isinstance(expected_size, int) and path.stat().st_size != expected_size:
            fail(f"bundle file size mismatch: {rel}")
        actual_hash = sha256(path)
        if actual_hash != expected_hash:
            fail(f"bundle file hash mismatch: {rel}")
        checked += 1
    print(f"verify ok: {checked} files")


def write_install_notes(bundle_dir: Path) -> None:
    text = """# Codex Portable Bundle

This bundle was generated by `~/.codex/portable/codex_portable.py`.

## Import On A New Machine

1. Install and launch Codex once, then quit Codex.
2. Copy this bundle to the new machine.
3. Run:

```bash
python3 payload/codex/portable/codex_portable.py import --bundle . --yes
```

The importer creates a timestamped backup under `~/.codex/portable/backups`
before replacing durable config files.

## Session Sync

For ongoing sync through a cloud folder or Syncthing-style directory, use:

```bash
~/.codex/portable/codex_portable.py configure --icloud --create
~/.codex/portable/codex_portable.py sync-push
~/.codex/portable/codex_portable.py sync-pull --yes
```

Do not run Codex on two machines at the same time while syncing UI preferences.
Transcript history is imported into the audit-only source folder, not into the
Codex app sidebar.
"""
    (bundle_dir / "README-INSTALL.md").write_text(text)


def export_bundle(args: argparse.Namespace) -> Path:
    source_home = home_path()
    source_codex = codex_home()
    bundle = Path(args.out).expanduser().resolve()
    ensure_empty_dir(bundle, force=args.force)

    payload = bundle / "payload"
    payload_codex = payload / "codex"

    included: list[str] = []

    for name in CODEX_TOP_FILES:
        if copy_file(source_codex / name, payload_codex / name):
            included.append(f"codex/{name}")

    if args.include_auth:
        if copy_file(source_codex / "auth.json", payload_codex / "auth.json"):
            included.append("codex/auth.json")

    copy_tree(source_codex / "audit", payload_codex / "audit", include_auth=args.include_auth)
    for derived in ["session_audit.sqlite", "session_audit.sqlite-shm", "session_audit.sqlite-wal", "session_sources"]:
        derived_path = payload_codex / "audit" / derived
        if derived_path.exists():
            if derived_path.is_dir():
                shutil.rmtree(derived_path)
            else:
                derived_path.unlink()
    if (payload_codex / "audit").exists():
        included.append("codex/audit")

    copy_tree(source_codex / "portable", payload_codex / "portable", include_auth=args.include_auth)
    if (payload_codex / "portable").exists():
        included.append("codex/portable")

    skills_src = source_codex / "skills"
    skills_dst = payload_codex / "skills"
    if skills_src.is_dir():
        for skill in sorted(skills_src.iterdir()):
            if skill.is_dir() and not skill.name.startswith("."):
                copy_tree(skill, skills_dst / skill.name, include_auth=args.include_auth)
                included.append(f"codex/skills/{skill.name}")

    things_src = source_codex / "things"
    if things_src.is_dir():
        copy_tree(things_src, payload_codex / "things", include_auth=args.include_auth)
        included.append("codex/things")

    ledger = source_home / "LEDGER.jsonl"
    if copy_file(ledger, payload / "home" / "LEDGER.jsonl"):
        included.append("home/LEDGER.jsonl")

    research = Path(args.research_map).expanduser() if args.research_map else DEFAULT_RESEARCH_MAP
    if copy_file(research, payload / "docs" / "codex-config-research-map.md"):
        included.append("docs/codex-config-research-map.md")

    if args.include_ui or args.full:
        ui_root = payload / "app-ui"
        for name in UI_CODEX_HOME_FILES:
            if copy_file(source_codex / name, ui_root / "codex-home" / name):
                included.append(f"app-ui/codex-home/{name}")
        source_app = app_support_dir(source_home)
        for name in APP_SUPPORT_FILES:
            if copy_file(source_app / name, ui_root / "application-support-codex" / name):
                included.append(f"app-ui/application-support-codex/{name}")

    if args.include_sessions or args.full:
        source_name = host_key()
        sessions_root = payload / "audit-sessions" / source_name
        for dirname in ACTIVE_SESSION_DIRS:
            if copy_tree(source_codex / dirname, sessions_root / dirname, include_auth=args.include_auth):
                included.append(f"audit-sessions/{source_name}/{dirname}")
        for name in SESSION_TOP_FILES:
            if copy_file(source_codex / name, sessions_root / name):
                included.append(f"audit-sessions/{source_name}/{name}")

    if args.include_runtime_dbs:
        runtime_root = payload / "runtime-dbs"
        for name in RUNTIME_DBS:
            if copy_sqlite_snapshot(source_codex / name, runtime_root / name):
                included.append(f"runtime-dbs/{name}")

    manifest = {
        "created_at": iso_now(),
        "source_home": str(source_home),
        "source_codex_home": str(source_codex),
        "source_app_support": str(app_support_dir(source_home)),
        "source_host": host_key(),
        "profile": "full" if args.full else "custom",
        "include_auth": bool(args.include_auth),
        "include_runtime_dbs": bool(args.include_runtime_dbs),
        "session_sync_mode": "audit-only" if (args.include_sessions or args.full) else "none",
        "included": sorted(included),
    }
    write_install_notes(bundle)
    write_json(bundle / "manifest.json", manifest)
    write_json(bundle / "manifest-files.json", collect_files(bundle))

    if args.archive:
        archive = bundle.with_suffix("").with_name(bundle.name + ".tar.gz")
        with tarfile.open(archive, "w:gz") as tar:
            tar.add(bundle, arcname=bundle.name)
        print(f"archive={archive}")

    print(f"bundle={bundle}")
    return bundle


def bundle_root(path: Path) -> tuple[Path, tempfile.TemporaryDirectory[str] | None]:
    path = path.expanduser().resolve()
    if path.is_dir():
        return path, None
    if path.is_file() and path.name.endswith((".tar.gz", ".tgz")):
        tmp = tempfile.TemporaryDirectory(prefix="codex-portable-")
        tmp_path = Path(tmp.name)
        with tarfile.open(path, "r:gz") as tar:
            safe_extract(tar, tmp_path)
        roots = [p for p in tmp_path.iterdir() if p.is_dir()]
        if len(roots) != 1:
            fail(f"archive {path} did not contain exactly one root directory")
        return roots[0], tmp
    fail(f"bundle not found: {path}")


def load_manifest(bundle: Path) -> dict[str, object]:
    manifest = bundle / "manifest.json"
    if not manifest.is_file():
        fail(f"missing manifest.json in {bundle}")
    return json.loads(manifest.read_text())


def backup_existing(paths: Iterable[Path], backup_dir: Path, dry_run: bool) -> None:
    seen: set[Path] = set()
    for path in paths:
        if path in seen or not path.exists():
            continue
        seen.add(path)
        dest = backup_dir / path.relative_to(path.anchor)
        print(f"backup {path} -> {dest}")
        if dry_run:
            continue
        if path.is_dir():
            copy_tree(path, dest, include_auth=True)
        else:
            copy_file(path, dest)


def maybe_rewrite_home(path: Path, old_home: str, new_home: str, dry_run: bool) -> None:
    if old_home == new_home or not path.is_file():
        return
    if path.suffix not in TEXT_SUFFIXES and path.name not in {"config.toml", "AGENTS.md", "hooks.json"}:
        return
    try:
        text = path.read_text()
    except UnicodeDecodeError:
        return
    if old_home not in text:
        return
    print(f"rewrite home paths in {path}: {old_home} -> {new_home}")
    if not dry_run:
        path.write_text(text.replace(old_home, new_home))


def copy_with_conflict(src: Path, dst: Path, dry_run: bool, conflict_stamp: str) -> str:
    if not src.is_file():
        return "missing"
    if dst.exists():
        if sha256(src) == sha256(dst):
            return "same"
        conflict = dst.with_name(dst.name + f".incoming-{conflict_stamp}")
        print(f"conflict {dst}; writing incoming copy to {conflict}")
        if not dry_run:
            copy_file(src, conflict)
        return "conflict"
    print(f"copy {src} -> {dst}")
    if not dry_run:
        copy_file(src, dst)
    return "copied"


def merge_json_value(local: object, incoming: object) -> object:
    if isinstance(local, dict) and isinstance(incoming, dict):
        merged = dict(local)
        for key, value in incoming.items():
            merged[key] = merge_json_value(local[key], value) if key in local else value
        return merged

    if isinstance(local, list) and isinstance(incoming, list):
        merged_list: list[object] = []
        seen: set[str] = set()
        for item in [*local, *incoming]:
            marker = json.dumps(item, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
            if marker in seen:
                continue
            seen.add(marker)
            merged_list.append(item)
        return merged_list

    return incoming


def merge_json_file(src: Path, dst: Path, dry_run: bool) -> None:
    if not src.is_file():
        return
    if not dst.exists():
        print(f"copy {src} -> {dst}")
        if not dry_run:
            copy_file(src, dst)
        return
    if sha256(src) == sha256(dst):
        print(f"same {dst}")
        return

    local = read_json_file(dst)
    incoming = read_json_file(src)
    if local is None or incoming is None:
        print(f"replace {dst} from {src} (json merge unavailable)")
        if not dry_run:
            copy_file(src, dst)
        return

    merged = merge_json_value(local, incoming)
    print(f"merge json {src} -> {dst}")
    if not dry_run:
        write_json(dst, merged)


def toml_blocks(text: str) -> tuple[list[str], list[dict[str, object]]]:
    lines = text.splitlines()
    starts: list[tuple[int, str, bool]] = []
    for idx, line in enumerate(lines):
        match = TOML_TABLE_RE.match(line)
        if match:
            starts.append((idx, match.group(2).strip(), match.group(1) == "[["))

    first = starts[0][0] if starts else len(lines)
    blocks: list[dict[str, object]] = []
    for pos, (start, header, is_array) in enumerate(starts):
        end = starts[pos + 1][0] if pos + 1 < len(starts) else len(lines)
        blocks.append({"header": header, "is_array": is_array, "lines": lines[start:end]})
    return lines[:first], blocks


def toml_key_lines(lines: list[str]) -> dict[str, str]:
    keys: dict[str, str] = {}
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        match = TOML_KEY_RE.match(line)
        if match:
            keys.setdefault(match.group(1), line)
    return keys


def merge_config_text(local_text: str, incoming_text: str) -> str:
    incoming_top, incoming_blocks = toml_blocks(incoming_text)
    local_top, local_blocks = toml_blocks(local_text)

    incoming_top_keys = toml_key_lines(incoming_top)
    local_top_keys = toml_key_lines(local_top)
    missing_top = [line for key, line in local_top_keys.items() if key not in incoming_top_keys]

    local_by_header: dict[str, list[dict[str, object]]] = {}
    for block in local_blocks:
        local_by_header.setdefault(str(block["header"]), []).append(block)

    incoming_header_counts: dict[str, int] = {}
    for block in incoming_blocks:
        incoming_header_counts[str(block["header"])] = incoming_header_counts.get(str(block["header"]), 0) + 1

    output: list[str] = list(incoming_top)
    if missing_top:
        if output and output[-1].strip():
            output.append("")
        output.append("# Preserved local-only settings during portable sync.")
        output.extend(missing_top)

    for block in incoming_blocks:
        header = str(block["header"])
        block_lines = list(block["lines"])  # type: ignore[arg-type]
        matching_local = local_by_header.get(header, [])
        if not block["is_array"] and len(matching_local) == 1 and incoming_header_counts.get(header) == 1:
            incoming_keys = toml_key_lines(block_lines[1:])
            local_keys = toml_key_lines(list(matching_local[0]["lines"])[1:])  # type: ignore[arg-type]
            missing = [line for key, line in local_keys.items() if key not in incoming_keys]
            if missing:
                while block_lines and not block_lines[-1].strip():
                    block_lines.pop()
                block_lines.append("")
                block_lines.append("# Preserved local-only settings during portable sync.")
                block_lines.extend(missing)
                block_lines.append("")
        output.extend(block_lines)

    incoming_headers = {str(block["header"]) for block in incoming_blocks}
    missing_blocks = [
        block
        for block in local_blocks
        if not block["is_array"] and str(block["header"]) not in incoming_headers
    ]
    if missing_blocks:
        if output and output[-1].strip():
            output.append("")
        output.append("# Preserved local-only tables during portable sync.")
        for block in missing_blocks:
            block_lines = list(block["lines"])  # type: ignore[arg-type]
            output.extend(block_lines)
            if output and output[-1].strip():
                output.append("")

    return "\n".join(output).rstrip() + "\n"


def merge_config_toml(
    src: Path,
    dst: Path,
    dry_run: bool,
    *,
    source_home: str = "",
    target_home: str = "",
    rewrite_home: bool = True,
) -> None:
    if not src.is_file():
        return

    incoming_text = src.read_text()
    if rewrite_home and source_home and target_home and source_home != target_home:
        incoming_text = incoming_text.replace(source_home, target_home)

    if not dst.exists():
        print(f"copy {src} -> {dst}")
        if not dry_run:
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_text(incoming_text)
        return

    local_text = dst.read_text(errors="replace")
    if local_text == incoming_text:
        print(f"same {dst}")
        return

    try:
        tomllib.loads(local_text)
        tomllib.loads(incoming_text)
    except tomllib.TOMLDecodeError as exc:
        print(f"replace {dst} from {src} (toml merge unavailable: {exc})")
        if not dry_run:
            dst.write_text(incoming_text)
        return

    merged = merge_config_text(local_text, incoming_text)
    try:
        tomllib.loads(merged)
    except tomllib.TOMLDecodeError as exc:
        fail(f"merged config.toml would be invalid: {exc}")

    print(f"merge config {src} -> {dst}")
    if not dry_run:
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_text(merged)


def merge_jsonl(src: Path, dst: Path, id_getter, ts_getter, dry_run: bool) -> None:
    records: dict[str, tuple[str, str]] = {}
    raw_counter = 0

    def ingest(path: Path, incoming: bool) -> None:
        nonlocal raw_counter
        if not path.is_file():
            return
        for line in path.read_text(errors="replace").splitlines():
            if not line.strip():
                continue
            try:
                obj = json.loads(line)
                record_id = id_getter(obj)
                ts = ts_getter(obj) or ""
            except Exception:
                raw_counter += 1
                record_id = f"__raw_{raw_counter}"
                ts = ""
            if not record_id:
                raw_counter += 1
                record_id = f"__raw_{raw_counter}"
            existing = records.get(record_id)
            if existing is None or (incoming and ts >= existing[0]):
                records[record_id] = (ts, line)

    ingest(dst, incoming=False)
    ingest(src, incoming=True)
    merged = [line for _, line in sorted(records.values(), key=lambda item: item[0])]
    print(f"merge {src} -> {dst} ({len(merged)} records)")
    if not dry_run:
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_text("\n".join(merged) + ("\n" if merged else ""))


def merge_tree(src: Path, dst: Path, dry_run: bool, conflict_stamp: str) -> None:
    if not src.is_dir():
        return
    for file in sorted(p for p in src.rglob("*") if p.is_file()):
        rel = file.relative_to(src)
        copy_with_conflict(file, dst / rel, dry_run=dry_run, conflict_stamp=conflict_stamp)


def import_audit_sessions(bundle: Path, target_codex: Path, dry_run: bool, conflict_stamp: str) -> None:
    audit_root = bundle / "payload" / "audit-sessions"
    target_root = audit_session_sources_dir(target_codex)
    if audit_root.is_dir():
        merge_tree(audit_root, target_root, dry_run=dry_run, conflict_stamp=conflict_stamp)

    legacy_root = bundle / "payload" / "session-data"
    if legacy_root.is_dir():
        manifest = load_manifest(bundle)
        source_name = re.sub(r"[^A-Za-z0-9_.-]+", "-", str(manifest.get("source_host") or "legacy-session-data")).strip("-")
        source_name = source_name or "legacy-session-data"
        legacy_target = target_root / source_name
        for dirname in ACTIVE_SESSION_DIRS:
            merge_tree(legacy_root / dirname, legacy_target / dirname, dry_run=dry_run, conflict_stamp=conflict_stamp)
        copy_with_conflict(legacy_root / "session_index.jsonl", legacy_target / "session_index.jsonl", dry_run=dry_run, conflict_stamp=conflict_stamp)


def iter_bundle_session_files(bundle: Path) -> list[Path]:
    roots = [
        bundle / "payload" / "audit-sessions",
        bundle / "payload" / "session-data",
    ]
    files: list[Path] = []
    for root in roots:
        if root.is_dir():
            files.extend(sorted(root.rglob("*.jsonl")))
    return [path for path in files if path.name != "session_index.jsonl"]


def remote_or_bundle(value: str | None, remote_value: str | None) -> Path:
    if value:
        bundle, tmp = bundle_root(Path(value))
        if tmp is not None:
            fail("repair-sidebar-sessions requires an extracted bundle or sync remote, not a tar archive")
        return bundle
    remote = resolve_remote(remote_value)
    current = remote / "current"
    if not current.is_dir():
        fail(f"remote current bundle not found: {current}")
    return current


def prune_session_index(path: Path, moved_ids: set[str], dry_run: bool) -> None:
    if not path.is_file() or not moved_ids:
        return
    kept: list[str] = []
    removed = 0
    for line in path.read_text(errors="replace").splitlines():
        if not line.strip():
            continue
        try:
            obj = json.loads(line)
            session_id = obj.get("id")
        except json.JSONDecodeError:
            session_id = None
        if isinstance(session_id, str) and session_id.lower() in moved_ids:
            removed += 1
            continue
        kept.append(line)
    if removed:
        print(f"prune {removed} entries from {path}")
        if not dry_run:
            path.write_text("\n".join(kept) + ("\n" if kept else ""))


def prune_state_db(db_path: Path, moved_ids: set[str], moved_paths: set[str], backup_dir: Path, dry_run: bool) -> None:
    if not db_path.is_file() or not moved_ids:
        return
    placeholders = ",".join("?" for _ in moved_ids)
    params = tuple(sorted(moved_ids))
    with sqlite3.connect(f"file:{db_path}?mode=ro", uri=True) as conn:
        matches = conn.execute(f"SELECT id, rollout_path FROM threads WHERE lower(id) IN ({placeholders})", params).fetchall()
    if moved_paths:
        with sqlite3.connect(f"file:{db_path}?mode=ro", uri=True) as conn:
            path_placeholders = ",".join("?" for _ in moved_paths)
            path_matches = conn.execute(
                f"SELECT id, rollout_path FROM threads WHERE rollout_path IN ({path_placeholders})",
                tuple(sorted(moved_paths)),
            ).fetchall()
        by_id = {row[0]: row for row in matches}
        by_id.update({row[0]: row for row in path_matches})
        matches = list(by_id.values())

    if not matches:
        return

    print(f"prune {len(matches)} rows from {db_path}:threads")
    if dry_run:
        return

    copy_file(db_path, backup_dir / "state_5.sqlite")
    with sqlite3.connect(db_path) as conn:
        conn.execute("PRAGMA foreign_keys = ON")
        conn.executemany("DELETE FROM threads WHERE id = ?", [(row[0],) for row in matches])
        conn.commit()


def repair_sidebar_sessions(args: argparse.Namespace) -> None:
    bundle = remote_or_bundle(args.bundle, args.remote)
    manifest = load_manifest(bundle)
    source_host = str(manifest.get("source_host") or "")
    if source_host and source_host == host_key() and not args.allow_current_host:
        fail(
            "the selected bundle was produced by this host; refusing to remove this host's own sidebar sessions. "
            "Pass --allow-current-host only if this machine is the duplicate target."
        )

    target_home = Path(args.home).expanduser().resolve() if args.home else home_path()
    target_codex = Path(args.codex_home).expanduser().resolve() if args.codex_home else target_home / ".codex"
    dry_run = args.dry_run or not args.yes
    if dry_run:
        print("dry-run: no files will be changed; pass --yes to apply")

    fingerprints: set[tuple[int, str]] = set()
    for file in iter_bundle_session_files(bundle):
        fingerprints.add((file.stat().st_size, sha256(file)))
    if not fingerprints:
        print("no bundled session transcript fingerprints found")
        return

    moved_ids: set[str] = set()
    moved_paths: set[str] = set()
    repair_stamp = stamp()
    backup_dir = target_codex / "portable" / "backups" / f"sidebar-repair-{repair_stamp}"
    audit_target = audit_session_sources_dir(target_codex) / f"sidebar-repair-{repair_stamp}"

    for dirname in ACTIVE_SESSION_DIRS:
        root = target_codex / dirname
        if not root.is_dir():
            continue
        for file in sorted(root.rglob("*.jsonl")):
            fingerprint = (file.stat().st_size, sha256(file))
            if fingerprint not in fingerprints:
                continue
            rel = file.relative_to(root)
            moved_ids.add(discover_session_id(file))
            moved_paths.add(str(file))
            dest = audit_target / dirname / rel
            print(f"move sidebar session {file} -> {dest}")
            if not dry_run:
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(file), str(dest))

    if not moved_ids:
        print("no matching active sidebar session files found")
        return

    backup_existing([target_codex / "session_index.jsonl"], backup_dir, dry_run=dry_run)
    prune_session_index(target_codex / "session_index.jsonl", moved_ids, dry_run=dry_run)

    if args.repair_state_db:
        backup_existing([target_codex / "state_5.sqlite"], backup_dir, dry_run=dry_run)
        prune_state_db(target_codex / "state_5.sqlite", moved_ids, moved_paths, backup_dir, dry_run=dry_run)

    print(f"sidebar session repair complete: matched={len(moved_ids)}")
    if not dry_run:
        print(f"audit_copy={audit_target}")
        print(f"backup_dir={backup_dir}")


def install_file_or_tree(src: Path, dst: Path, dry_run: bool) -> None:
    if not src.exists():
        return
    print(f"install {src} -> {dst}")
    if dry_run:
        return
    if src.is_dir():
        copy_tree(src, dst, include_auth=True)
    else:
        copy_file(src, dst)


def import_bundle(args: argparse.Namespace) -> None:
    bundle, tmp = bundle_root(Path(args.bundle))
    try:
        if not args.skip_verify:
            verify_bundle_contents(bundle)
        manifest = load_manifest(bundle)
        source_home = str(manifest.get("source_home", ""))
        target_home = Path(args.home).expanduser().resolve() if args.home else home_path()
        target_codex = Path(args.codex_home).expanduser().resolve() if args.codex_home else target_home / ".codex"
        target_app = app_support_dir(target_home)
        dry_run = args.dry_run or not args.yes

        if dry_run:
            print("dry-run: no files will be changed; pass --yes to apply")

        payload = bundle / "payload"
        backup_dir = target_codex / "portable" / "backups" / f"import-{stamp()}"
        existing_portable_config = read_json_file(target_codex / "portable" / PORTABLE_CONFIG_NAME)

        targets_for_backup = [
            target_codex / "config.toml",
            target_codex / "AGENTS.md",
            target_codex / "hooks.json",
            target_codex / "audit" / "session_audit.py",
            target_codex / "audit" / "README.md",
            target_codex / "portable",
            target_codex / "skills" / "notion",
            target_codex / "skills" / "things",
            target_codex / "things",
            audit_session_sources_dir(target_codex),
            target_home / "LEDGER.jsonl",
        ]
        if not args.skip_ui:
            targets_for_backup += [
                *(target_codex / name for name in UI_CODEX_HOME_FILES),
                *(target_app / name for name in APP_SUPPORT_FILES),
            ]
        if args.replace_runtime_dbs:
            targets_for_backup += [target_codex / name for name in RUNTIME_DBS]

        backup_existing(targets_for_backup, backup_dir, dry_run=dry_run)

        codex_payload = payload / "codex"
        for name in CODEX_TOP_FILES:
            if name == "config.toml":
                merge_config_toml(
                    codex_payload / name,
                    target_codex / name,
                    dry_run=dry_run,
                    source_home=source_home,
                    target_home=str(target_home),
                    rewrite_home=not args.no_rewrite_home,
                )
            else:
                install_file_or_tree(codex_payload / name, target_codex / name, dry_run=dry_run)
        install_file_or_tree(codex_payload / "audit" / "session_audit.py", target_codex / "audit" / "session_audit.py", dry_run=dry_run)
        install_file_or_tree(codex_payload / "audit" / "README.md", target_codex / "audit" / "README.md", dry_run=dry_run)
        install_file_or_tree(codex_payload / "portable", target_codex / "portable", dry_run=dry_run)
        incoming_portable_config = read_json_file(codex_payload / "portable" / PORTABLE_CONFIG_NAME)
        if existing_portable_config is not None and incoming_portable_config is not None:
            print(f"merge json {codex_payload / 'portable' / PORTABLE_CONFIG_NAME} -> {target_codex / 'portable' / PORTABLE_CONFIG_NAME}")
            if not dry_run:
                write_json(
                    target_codex / "portable" / PORTABLE_CONFIG_NAME,
                    merge_json_value(existing_portable_config, incoming_portable_config),
                )

        skills_payload = codex_payload / "skills"
        if skills_payload.is_dir():
            for skill in sorted(skills_payload.iterdir()):
                if skill.is_dir():
                    install_file_or_tree(skill, target_codex / "skills" / skill.name, dry_run=dry_run)
        install_file_or_tree(codex_payload / "things", target_codex / "things", dry_run=dry_run)

        docs_payload = payload / "docs" / "codex-config-research-map.md"
        install_file_or_tree(docs_payload, target_codex / "portable" / "codex-config-research-map.md", dry_run=dry_run)

        ledger_src = payload / "home" / "LEDGER.jsonl"
        ledger_dst = target_home / "LEDGER.jsonl"
        if ledger_src.exists():
            merge_jsonl(
                ledger_src,
                ledger_dst,
                id_getter=lambda obj: obj.get("_meta", {}).get("id"),
                ts_getter=lambda obj: obj.get("_meta", {}).get("ts"),
                dry_run=dry_run,
            )

        if not args.skip_ui:
            ui_root = payload / "app-ui"
            for name in UI_CODEX_HOME_FILES:
                merge_json_file(ui_root / "codex-home" / name, target_codex / name, dry_run=dry_run)
            for name in APP_SUPPORT_FILES:
                merge_json_file(ui_root / "application-support-codex" / name, target_app / name, dry_run=dry_run)

        conflict_stamp = stamp()
        if not args.skip_sessions:
            import_audit_sessions(bundle, target_codex, dry_run=dry_run, conflict_stamp=conflict_stamp)

        if getattr(args, "repair_sidebar_sessions", False):
            repair_sidebar_sessions(
                argparse.Namespace(
                    bundle=str(bundle),
                    remote=None,
                    yes=args.yes,
                    dry_run=args.dry_run,
                    home=str(target_home),
                    codex_home=str(target_codex),
                    repair_state_db=getattr(args, "repair_state_db", False),
                    allow_current_host=getattr(args, "allow_current_host", False),
                )
            )

        if args.replace_runtime_dbs:
            runtime_root = payload / "runtime-dbs"
            for name in RUNTIME_DBS:
                install_file_or_tree(runtime_root / name, target_codex / name, dry_run=dry_run)

        if not args.no_rewrite_home and source_home:
            rewrite_roots = [
                target_codex / "AGENTS.md",
                target_codex / "hooks.json",
                target_codex / "audit",
                target_codex / "portable",
                target_codex / "skills",
            ]
            if not args.skip_ui:
                rewrite_roots += [target_codex / name for name in UI_CODEX_HOME_FILES]
            for root in rewrite_roots:
                if root.is_file():
                    maybe_rewrite_home(root, source_home, str(target_home), dry_run=dry_run)
                elif root.is_dir():
                    for file in root.rglob("*"):
                        maybe_rewrite_home(file, source_home, str(target_home), dry_run=dry_run)

        if not dry_run:
            audit = target_codex / "audit" / "session_audit.py"
            if audit.exists():
                os.chmod(audit, audit.stat().st_mode | 0o111)
            portable = target_codex / "portable" / "codex_portable.py"
            if portable.exists():
                os.chmod(portable, portable.stat().st_mode | 0o111)
            print(f"backup_dir={backup_dir}")

        print("import complete" if not dry_run else "dry-run complete")
    finally:
        if tmp is not None:
            tmp.cleanup()


def sync_push(args: argparse.Namespace) -> None:
    remote = resolve_remote(args.remote, create=True)
    use_config_profile = not any([args.full, args.include_ui, args.include_sessions, args.include_runtime_dbs])
    full = False if args.core_only else args.full or (use_config_profile and configured_bool("default_full", fallback=False))
    archive_requested = False if args.no_archive else args.archive or configured_bool("archive_on_push", fallback=False)
    with remote_lock(remote, force=args.force_lock):
        staging = remote / f".staging-{stamp()}"
        current = remote / "current"
        export_args = argparse.Namespace(
            out=str(staging),
            force=True,
            archive=False,
            full=full,
            include_ui=args.include_ui,
            include_sessions=args.include_sessions,
            include_runtime_dbs=args.include_runtime_dbs,
            include_auth=args.include_auth,
            research_map=args.research_map,
        )
        export_bundle(export_args)
        verify_bundle_contents(staging)
        if current.exists():
            previous = remote / f"previous-{stamp()}"
            current.rename(previous)
            print(f"previous={previous}")
        staging.rename(current)
        write_json(
            remote / "remote-state.json",
            {
                "updated_at": iso_now(),
                "updated_by_host": platform.node(),
                "current": "current",
                "profile": "full" if full else "custom",
            },
        )
        print(f"current={current}")
        if archive_requested:
            archives = remote / "archives"
            archives.mkdir(exist_ok=True)
            archive = archives / f"codex-portable-{stamp()}.tar.gz"
            with tarfile.open(archive, "w:gz") as tar:
                tar.add(current, arcname="current")
            print(f"archive={archive}")


def sync_pull(args: argparse.Namespace) -> None:
    remote = resolve_remote(args.remote)
    with remote_lock(remote, force=args.force_lock):
        bundle = remote / "current"
        import_args = argparse.Namespace(
            bundle=str(bundle),
            yes=args.yes,
            dry_run=args.dry_run,
            home=args.home,
            codex_home=args.codex_home,
            skip_ui=args.skip_ui,
            skip_sessions=args.skip_sessions,
            replace_runtime_dbs=args.replace_runtime_dbs,
            no_rewrite_home=args.no_rewrite_home,
            skip_verify=args.skip_verify,
            repair_sidebar_sessions=args.repair_sidebar_sessions,
            repair_state_db=args.repair_state_db,
            allow_current_host=args.allow_current_host,
        )
        import_bundle(import_args)


def configure(args: argparse.Namespace) -> None:
    config = load_portable_config()
    if args.icloud:
        icloud_root = default_icloud_remote().parent
        if not icloud_root.is_dir():
            fail(f"iCloud Drive folder not found: {icloud_root}")
        remote = default_icloud_remote()
    elif args.remote:
        remote = Path(args.remote).expanduser().resolve()
    else:
        remote_value = config.get("remote")
        remote = Path(str(remote_value)).expanduser().resolve() if remote_value else default_icloud_remote()

    if args.create:
        remote.mkdir(parents=True, exist_ok=True)

    config["remote"] = str(remote)
    if args.full_by_default is not None:
        config["default_full"] = bool(args.full_by_default)
    elif "default_full" not in config:
        config["default_full"] = True
    if args.archive_on_push is not None:
        config["archive_on_push"] = bool(args.archive_on_push)
    elif "archive_on_push" not in config:
        config["archive_on_push"] = True
    config["updated_at"] = iso_now()
    save_portable_config(config)
    print(f"config={portable_config_path()}")
    print(f"remote={remote}")
    print(f"default_full={config['default_full']}")
    print(f"archive_on_push={config['archive_on_push']}")


def verify_command(args: argparse.Namespace) -> None:
    bundle, tmp = bundle_root(Path(args.bundle))
    try:
        verify_bundle_contents(bundle)
    finally:
        if tmp is not None:
            tmp.cleanup()


def doctor(args: argparse.Namespace) -> None:
    status(args)
    print()
    config_path = codex_home() / "config.toml"
    if config_path.is_file():
        with config_path.open("rb") as f:
            tomllib.load(f)
        print(f"config parse ok: {config_path}")
    else:
        print(f"config missing: {config_path}")

    portable_config = load_portable_config()
    print(f"portable config: {portable_config_path() if portable_config else '<not configured>'}")
    remote_value = portable_config.get("remote")
    if isinstance(remote_value, str) and remote_value:
        remote = Path(remote_value).expanduser()
        print(f"remote: {remote}")
        print(f"remote exists: {remote.exists()}")
        print(f"remote current exists: {(remote / 'current').exists()}")
        if args.verify_remote and (remote / "current").exists():
            verify_bundle_contents(remote / "current")
    else:
        print("remote: <not configured>")


def status(_: argparse.Namespace) -> None:
    h = home_path()
    ch = codex_home()
    items = [
        ch / "config.toml",
        ch / "AGENTS.md",
        ch / "hooks.json",
        ch / "audit" / "session_audit.py",
        ch / "skills" / "notion" / "SKILL.md",
        ch / "skills" / "things" / "SKILL.md",
        ch / "portable" / "codex_portable.py",
        ch / "portable" / PORTABLE_CONFIG_NAME,
        h / "LEDGER.jsonl",
        ch / ".codex-global-state.json",
        app_support_dir(h) / "Preferences",
        ch / "sessions",
        ch / "archived_sessions",
    ]
    for item in items:
        kind = "dir" if item.is_dir() else "file" if item.is_file() else "missing"
        print(f"{kind:7} {item}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Port and sync a Codex setup between machines.")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("export", help="Create a portable bundle.")
    p.add_argument("--out", required=True, help="Output bundle directory.")
    p.add_argument("--force", action="store_true", help="Replace an existing output directory.")
    p.add_argument("--archive", action="store_true", help="Also create a .tar.gz next to the bundle.")
    p.add_argument("--full", action="store_true", help="Include UI preferences and audit-only session transcript data.")
    p.add_argument("--include-ui", action="store_true", help="Include Codex app UI preferences.")
    p.add_argument("--include-sessions", action="store_true", help="Include session transcript data for the audit index only; does not populate the Codex app sidebar.")
    p.add_argument("--include-runtime-dbs", action="store_true", help="Include SQLite runtime DB snapshots for clone-style migration.")
    p.add_argument("--include-auth", action="store_true", help="Include auth.json. Sensitive; prefer logging in again.")
    p.add_argument("--research-map", help="Optional research map file to include.")
    p.set_defaults(func=export_bundle)

    p = sub.add_parser("import", help="Import a portable bundle.")
    p.add_argument("--bundle", required=True, help="Bundle directory or .tar.gz archive.")
    p.add_argument("--yes", action="store_true", help="Apply changes. Without this, import is a dry run.")
    p.add_argument("--dry-run", action="store_true", help="Preview changes without writing.")
    p.add_argument("--home", help="Target home directory. Defaults to current user's home.")
    p.add_argument("--codex-home", help="Target Codex home. Defaults to HOME/.codex.")
    p.add_argument("--skip-ui", action="store_true", help="Do not import app UI preferences.")
    p.add_argument("--skip-sessions", action="store_true", help="Do not import audit-only session transcript data.")
    p.add_argument("--repair-sidebar-sessions", action="store_true", help="Move previously synced app-sidebar sessions into the audit-only source folder.")
    p.add_argument("--repair-state-db", action="store_true", help="With --repair-sidebar-sessions, also prune matching thread rows from state_5.sqlite. Quit Codex first.")
    p.add_argument("--allow-current-host", action="store_true", help="Allow sidebar repair even when the bundle was produced by this host.")
    p.add_argument("--replace-runtime-dbs", action="store_true", help="Replace state/log SQLite DBs if included. Use only with Codex quit.")
    p.add_argument("--no-rewrite-home", action="store_true", help="Do not rewrite source home paths to target home in config files.")
    p.add_argument("--skip-verify", action="store_true", help="Skip bundle checksum verification before import.")
    p.set_defaults(func=import_bundle)

    p = sub.add_parser("sync-push", help="Export into a shared sync directory as current/.")
    p.add_argument("--remote", help="Shared folder path. Defaults to configured remote.")
    p.add_argument("--full", action="store_true", help="Include UI preferences and audit-only session transcript data.")
    p.add_argument("--core-only", action="store_true", help="Override configured defaults and push only core portable setup.")
    p.add_argument("--include-ui", action="store_true", help="Include Codex app UI preferences.")
    p.add_argument("--include-sessions", action="store_true", help="Include session transcript data for the audit index only; does not populate the Codex app sidebar.")
    p.add_argument("--include-runtime-dbs", action="store_true", help="Include SQLite runtime DB snapshots.")
    p.add_argument("--include-auth", action="store_true", help="Include auth.json. Sensitive; prefer logging in again.")
    p.add_argument("--archive", action="store_true", help="Also keep timestamped archive under remote/archives.")
    p.add_argument("--no-archive", action="store_true", help="Do not create an archive even if configured by default.")
    p.add_argument("--force-lock", action="store_true", help="Break an existing remote lock. Use only if the prior sync is known dead.")
    p.add_argument("--research-map", help="Optional research map file to include.")
    p.set_defaults(func=sync_push)

    p = sub.add_parser("sync-pull", help="Import from a shared sync directory current/.")
    p.add_argument("--remote", help="Shared folder path. Defaults to configured remote.")
    p.add_argument("--yes", action="store_true", help="Apply changes. Without this, pull is a dry run.")
    p.add_argument("--dry-run", action="store_true", help="Preview changes without writing.")
    p.add_argument("--home", help="Target home directory. Defaults to current user's home.")
    p.add_argument("--codex-home", help="Target Codex home. Defaults to HOME/.codex.")
    p.add_argument("--skip-ui", action="store_true", help="Do not import app UI preferences.")
    p.add_argument("--skip-sessions", action="store_true", help="Do not import audit-only session transcript data.")
    p.add_argument("--repair-sidebar-sessions", action="store_true", help="Move previously synced app-sidebar sessions into the audit-only source folder.")
    p.add_argument("--repair-state-db", action="store_true", help="With --repair-sidebar-sessions, also prune matching thread rows from state_5.sqlite. Quit Codex first.")
    p.add_argument("--allow-current-host", action="store_true", help="Allow sidebar repair even when the bundle was produced by this host.")
    p.add_argument("--replace-runtime-dbs", action="store_true", help="Replace state/log SQLite DBs if included. Use only with Codex quit.")
    p.add_argument("--no-rewrite-home", action="store_true", help="Do not rewrite source home paths to target home in config files.")
    p.add_argument("--skip-verify", action="store_true", help="Skip bundle checksum verification before pull.")
    p.add_argument("--force-lock", action="store_true", help="Break an existing remote lock. Use only if the prior sync is known dead.")
    p.set_defaults(func=sync_pull)

    p = sub.add_parser("repair-sidebar-sessions", help="Move previously synced app-sidebar sessions into audit-only storage.")
    p.add_argument("--remote", help="Shared folder path. Defaults to configured remote.")
    p.add_argument("--bundle", help="Bundle directory to compare against. Defaults to remote/current.")
    p.add_argument("--yes", action="store_true", help="Apply changes. Without this, repair is a dry run.")
    p.add_argument("--dry-run", action="store_true", help="Preview changes without writing.")
    p.add_argument("--home", help="Target home directory. Defaults to current user's home.")
    p.add_argument("--codex-home", help="Target Codex home. Defaults to HOME/.codex.")
    p.add_argument("--repair-state-db", action="store_true", help="Also prune matching thread rows from state_5.sqlite. Quit Codex first.")
    p.add_argument("--allow-current-host", action="store_true", help="Allow repair even when the bundle was produced by this host.")
    p.set_defaults(func=repair_sidebar_sessions)

    p = sub.add_parser("configure", help="Configure default portable sync settings.")
    p.add_argument("--remote", help="Shared folder path to use by default.")
    p.add_argument("--icloud", action="store_true", help="Use the iCloud Drive Documents/CodexPortable folder.")
    p.add_argument("--create", action="store_true", help="Create the remote folder if needed.")
    p.add_argument("--full-by-default", dest="full_by_default", action="store_true", default=None, help="Make sync-push include UI and sessions by default.")
    p.add_argument("--no-full-by-default", dest="full_by_default", action="store_false", help="Make sync-push export core config only by default.")
    p.add_argument("--archive-on-push", dest="archive_on_push", action="store_true", default=None, help="Keep archives by default on sync-push.")
    p.add_argument("--no-archive-on-push", dest="archive_on_push", action="store_false", help="Do not keep archives by default on sync-push.")
    p.set_defaults(func=configure)

    p = sub.add_parser("verify", help="Verify a bundle against manifest-files.json.")
    p.add_argument("--bundle", required=True, help="Bundle directory or .tar.gz archive.")
    p.set_defaults(func=verify_command)

    p = sub.add_parser("doctor", help="Check local portable setup and configured remote.")
    p.add_argument("--verify-remote", action="store_true", help="Verify remote/current checksums if present.")
    p.set_defaults(func=doctor)

    p = sub.add_parser("status", help="Show local portable setup status.")
    p.set_defaults(func=status)

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
