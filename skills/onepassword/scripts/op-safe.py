#!/usr/bin/env python3
"""
Small safe wrapper around 1Password CLI for Codex credential handoff.

This script intentionally never prints field values. Secret operations copy or
paste through the clipboard and only emit structured status.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import shutil
import subprocess
from typing import Any


APP_PATH = pathlib.Path("/Applications/1Password.app")
SENSITIVE_LABEL_RE = re.compile(
    r"(backup|recovery|secret\s*key|security\s*code|cvv|cvc|card\s*number|pin)",
    re.IGNORECASE,
)
OTP_RE = re.compile(r"(otp|totp|one[-\s]*time)", re.IGNORECASE)


def print_json(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, indent=2, sort_keys=True))


def op_path() -> str | None:
    return shutil.which("op")


def run_command(
    argv: list[str],
    *,
    input_bytes: bytes | None = None,
    capture: bool = True,
    check: bool = False,
) -> subprocess.CompletedProcess[bytes]:
    kwargs: dict[str, Any] = {
        "input": input_bytes,
        "check": check,
    }
    if capture:
        kwargs["stdout"] = subprocess.PIPE
        kwargs["stderr"] = subprocess.PIPE
    return subprocess.run(argv, **kwargs)


def run_op(args: list[str], *, check: bool = False) -> subprocess.CompletedProcess[bytes]:
    path = op_path()
    if not path:
        raise SystemExit("1Password CLI is not installed. Install Homebrew cask '1password-cli'.")
    return run_command([path, *args], check=check)


def decode(data: bytes) -> str:
    return data.decode("utf-8", errors="replace").strip()


def load_json_stdout(proc: subprocess.CompletedProcess[bytes]) -> Any:
    text = decode(proc.stdout)
    if not text:
        return None
    return json.loads(text)


def status(args: argparse.Namespace) -> int:
    path = op_path()
    payload: dict[str, Any] = {
        "app_installed": APP_PATH.exists(),
        "op_installed": bool(path),
        "op_path": path,
        "op_version": None,
        "accounts_configured": False,
        "account_count": 0,
        "signin_ready": False,
        "next_step": None,
    }

    if not path:
        payload["next_step"] = "Install 1Password CLI with: brew install --cask 1password-cli"
        print_json(payload)
        return 1

    version = run_op(["--version"])
    if version.returncode == 0:
        payload["op_version"] = decode(version.stdout)

    accounts = run_op(["account", "list", "--format", "json"])
    if accounts.returncode == 0:
        data = load_json_stdout(accounts) or []
        payload["accounts_configured"] = bool(data)
        payload["account_count"] = len(data) if isinstance(data, list) else 0
        payload["signin_ready"] = bool(data)
        if not data:
            payload["next_step"] = "Enable 1Password app integration, then run: op signin"
    else:
        payload["next_step"] = "Enable 1Password app integration in 1Password > Settings > Developer, then run: op signin"
        payload["op_account_list_error"] = first_line(accounts.stderr)

    print_json(payload)
    if args.require_account and not payload["signin_ready"]:
        return 1
    return 0 if payload["op_installed"] and payload["app_installed"] else 1


def first_line(data: bytes) -> str:
    text = decode(data)
    return text.splitlines()[0] if text else ""


def signin(_: argparse.Namespace) -> int:
    path = op_path()
    if not path:
        raise SystemExit("1Password CLI is not installed.")
    return subprocess.run([path, "signin"]).returncode


def normalize(value: Any) -> str:
    return str(value or "").casefold()


def item_vault_name(item: dict[str, Any]) -> str | None:
    vault = item.get("vault")
    if isinstance(vault, dict):
        return vault.get("name") or vault.get("id")
    if isinstance(vault, str):
        return vault
    return None


def item_search_blob(item: dict[str, Any]) -> str:
    parts: list[str] = [
        str(item.get("title") or ""),
        str(item.get("id") or ""),
        str(item.get("category") or ""),
        str(item_vault_name(item) or ""),
    ]
    for url in item.get("urls") or []:
        if isinstance(url, dict):
            parts.append(str(url.get("href") or ""))
            parts.append(str(url.get("label") or ""))
        else:
            parts.append(str(url))
    return " ".join(parts).casefold()


def safe_item_summary(item: dict[str, Any]) -> dict[str, Any]:
    urls = []
    for url in item.get("urls") or []:
        if isinstance(url, dict):
            urls.append({"label": url.get("label"), "href": url.get("href")})
        else:
            urls.append(url)
    return {
        "id": item.get("id"),
        "title": item.get("title"),
        "vault": item_vault_name(item),
        "category": item.get("category"),
        "urls": urls,
    }


def search(args: argparse.Namespace) -> int:
    cmd = ["item", "list", "--format", "json", "--long"]
    if args.vault:
        cmd.extend(["--vault", args.vault])
    if args.category:
        cmd.extend(["--categories", args.category])
    if args.tags:
        cmd.extend(["--tags", args.tags])

    proc = run_op(cmd)
    if proc.returncode != 0:
        print_json({"ok": False, "error": first_line(proc.stderr)})
        return proc.returncode

    data = load_json_stdout(proc) or []
    query = normalize(args.query)
    matches = []
    for item in data:
        if not isinstance(item, dict):
            continue
        if query in item_search_blob(item):
            matches.append(safe_item_summary(item))
        if len(matches) >= args.limit:
            break

    print_json({"ok": True, "query": args.query, "count": len(matches), "items": matches})
    return 0


def get_item(item: str, vault: str | None = None) -> dict[str, Any]:
    cmd = ["item", "get", item, "--format", "json"]
    if vault:
        cmd.extend(["--vault", vault])
    proc = run_op(cmd)
    if proc.returncode != 0:
        raise RuntimeError(first_line(proc.stderr))
    data = load_json_stdout(proc)
    if not isinstance(data, dict):
        raise RuntimeError("1Password returned an unexpected item payload")
    return data


def iter_fields(item: dict[str, Any]) -> list[dict[str, Any]]:
    fields: list[dict[str, Any]] = []
    for field in item.get("fields") or []:
        if isinstance(field, dict):
            copied = dict(field)
            copied.setdefault("section", None)
            fields.append(copied)
    for section in item.get("sections") or []:
        if not isinstance(section, dict):
            continue
        section_label = section.get("label") or section.get("id")
        for field in section.get("fields") or []:
            if isinstance(field, dict):
                copied = dict(field)
                copied.setdefault("section", section_label)
                fields.append(copied)
    return fields


def safe_field_summary(field: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": field.get("id"),
        "label": field.get("label"),
        "type": field.get("type"),
        "purpose": field.get("purpose"),
        "section": field.get("section"),
        "reference_available": bool(field.get("reference")),
    }


def show_item(args: argparse.Namespace) -> int:
    try:
        item = get_item(args.item, args.vault)
    except RuntimeError as exc:
        print_json({"ok": False, "error": str(exc)})
        return 1

    payload = safe_item_summary(item)
    payload["ok"] = True
    payload["fields"] = [safe_field_summary(field) for field in iter_fields(item)]
    print_json(payload)
    return 0


def field_matches(field: dict[str, Any], needle: str) -> bool:
    wanted = normalize(needle)
    for key in ("label", "id", "purpose"):
        if normalize(field.get(key)) == wanted:
            return True
    return False


def field_reference(item_name: str, field_name: str, vault: str | None = None) -> tuple[str, dict[str, Any], dict[str, Any]]:
    item = get_item(item_name, vault)
    matches = [field for field in iter_fields(item) if field_matches(field, field_name)]
    if not matches:
        labels = [field.get("label") or field.get("id") for field in iter_fields(item)]
        raise RuntimeError(f"Field not found. Available fields: {', '.join(str(label) for label in labels if label)}")
    if len(matches) > 1:
        labels = [f"{field.get('section') or 'root'}:{field.get('label') or field.get('id')}" for field in matches]
        raise RuntimeError(f"Field is ambiguous. Matches: {', '.join(labels)}")
    field = matches[0]
    ref = field.get("reference")
    if not ref:
        raise RuntimeError("Field has no 1Password secret reference")
    return str(ref), item, field


def sensitive_kind(ref: str, item: dict[str, Any] | None, field: dict[str, Any] | None) -> str | None:
    text = " ".join(
        str(part or "")
        for part in (
            ref,
            item.get("category") if item else None,
            field.get("label") if field else None,
            field.get("id") if field else None,
            field.get("type") if field else None,
            field.get("purpose") if field else None,
        )
    )
    if OTP_RE.search(text):
        return "otp"
    if SENSITIVE_LABEL_RE.search(text):
        return "high_sensitive"
    return None


def read_secret(ref: str) -> bytes:
    proc = run_op(["read", "--no-newline", ref])
    if proc.returncode != 0:
        raise RuntimeError(first_line(proc.stderr))
    return proc.stdout


def pbcopy(data: bytes) -> None:
    proc = run_command(["pbcopy"], input_bytes=data)
    if proc.returncode != 0:
        raise RuntimeError(first_line(proc.stderr))


def clear_clipboard() -> None:
    pbcopy(b"")


def maybe_clear_after(seconds: float) -> None:
    if seconds <= 0:
        return
    subprocess.Popen(
        [
            "/bin/sh",
            "-c",
            'sleep "$1"; printf "" | /usr/bin/pbcopy',
            "op-safe-clear",
            str(seconds),
        ],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def assert_allowed(kind: str | None, args: argparse.Namespace) -> None:
    if kind == "otp" and not args.allow_otp:
        raise RuntimeError("Refusing OTP/TOTP access unless --allow-otp is passed.")
    if kind == "high_sensitive" and not args.allow_sensitive:
        raise RuntimeError("Refusing recovery/payment/security-code style field unless --allow-sensitive is passed.")


def copy_ref(args: argparse.Namespace, ref: str, item: dict[str, Any] | None = None, field: dict[str, Any] | None = None) -> int:
    try:
        kind = sensitive_kind(ref, item, field)
        assert_allowed(kind, args)
        secret = read_secret(ref)
        pbcopy(secret)
        maybe_clear_after(args.clear_after)
    except RuntimeError as exc:
        print_json({"ok": False, "error": str(exc)})
        return 1

    print_json({"ok": True, "action": "copied", "clipboard_cleared": args.clear_after > 0})
    return 0


def command_copy_ref(args: argparse.Namespace) -> int:
    return copy_ref(args, args.ref)


def command_copy_field(args: argparse.Namespace) -> int:
    try:
        ref, item, field = field_reference(args.item, args.field, args.vault)
    except RuntimeError as exc:
        print_json({"ok": False, "error": str(exc)})
        return 1
    return copy_ref(args, ref, item, field)


def paste_from_clipboard() -> None:
    script = 'tell application "System Events" to keystroke "v" using command down'
    proc = run_command(["osascript", "-e", script])
    if proc.returncode != 0:
        raise RuntimeError(first_line(proc.stderr))


def paste_ref(args: argparse.Namespace, ref: str, item: dict[str, Any] | None = None, field: dict[str, Any] | None = None) -> int:
    try:
        kind = sensitive_kind(ref, item, field)
        assert_allowed(kind, args)
        secret = read_secret(ref)
        pbcopy(secret)
        paste_from_clipboard()
        maybe_clear_after(args.clear_after)
    except RuntimeError as exc:
        try:
            clear_clipboard()
        except Exception:
            pass
        print_json({"ok": False, "error": str(exc)})
        return 1

    print_json({"ok": True, "action": "pasted", "clipboard_cleared": args.clear_after > 0})
    return 0


def command_paste_ref(args: argparse.Namespace) -> int:
    return paste_ref(args, args.ref)


def command_paste_field(args: argparse.Namespace) -> int:
    try:
        ref, item, field = field_reference(args.item, args.field, args.vault)
    except RuntimeError as exc:
        print_json({"ok": False, "error": str(exc)})
        return 1
    return paste_ref(args, ref, item, field)


def command_clear_clipboard(_: argparse.Namespace) -> int:
    try:
        clear_clipboard()
    except RuntimeError as exc:
        print_json({"ok": False, "error": str(exc)})
        return 1
    print_json({"ok": True, "action": "cleared"})
    return 0


def add_secret_safety_flags(parser: argparse.ArgumentParser, *, default_clear_after: float) -> None:
    parser.add_argument("--clear-after", type=float, default=default_clear_after, help="Seconds before clearing the clipboard. Use 0 to leave it unchanged.")
    parser.add_argument("--allow-otp", action="store_true", help="Allow copying/pasting OTP fields when explicitly requested by the user.")
    parser.add_argument("--allow-sensitive", action="store_true", help="Allow recovery/payment/security-code style fields when explicitly requested by the user.")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Safe 1Password CLI helper for Codex")
    sub = parser.add_subparsers(dest="command", required=True)

    p_status = sub.add_parser("status", help="Show app/CLI/account readiness without secrets")
    p_status.add_argument("--require-account", action="store_true", help="Return non-zero unless a CLI account is configured")
    p_status.set_defaults(func=status)

    p_signin = sub.add_parser("signin", help="Run op signin through the desktop app integration")
    p_signin.set_defaults(func=signin)

    p_search = sub.add_parser("search", help="Search 1Password item metadata")
    p_search.add_argument("query")
    p_search.add_argument("--vault")
    p_search.add_argument("--category", default="Login")
    p_search.add_argument("--tags")
    p_search.add_argument("--limit", type=int, default=10)
    p_search.set_defaults(func=search)

    p_item = sub.add_parser("item", help="Show sanitized item metadata and available field labels")
    p_item.add_argument("item")
    p_item.add_argument("--vault")
    p_item.set_defaults(func=show_item)

    p_copy_ref = sub.add_parser("copy-ref", help="Copy an op:// secret reference to the clipboard without printing it")
    p_copy_ref.add_argument("ref")
    add_secret_safety_flags(p_copy_ref, default_clear_after=45)
    p_copy_ref.set_defaults(func=command_copy_ref)

    p_copy_field = sub.add_parser("copy-field", help="Copy an item field to the clipboard without printing it")
    p_copy_field.add_argument("item")
    p_copy_field.add_argument("field")
    p_copy_field.add_argument("--vault")
    add_secret_safety_flags(p_copy_field, default_clear_after=45)
    p_copy_field.set_defaults(func=command_copy_field)

    p_paste_ref = sub.add_parser("paste-ref", help="Paste an op:// secret reference into the focused field")
    p_paste_ref.add_argument("ref")
    add_secret_safety_flags(p_paste_ref, default_clear_after=2)
    p_paste_ref.set_defaults(func=command_paste_ref)

    p_paste_field = sub.add_parser("paste-field", help="Paste an item field into the focused field")
    p_paste_field.add_argument("item")
    p_paste_field.add_argument("field")
    p_paste_field.add_argument("--vault")
    add_secret_safety_flags(p_paste_field, default_clear_after=2)
    p_paste_field.set_defaults(func=command_paste_field)

    p_clear = sub.add_parser("clear-clipboard", help="Clear the macOS clipboard")
    p_clear.set_defaults(func=command_clear_clipboard)

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
