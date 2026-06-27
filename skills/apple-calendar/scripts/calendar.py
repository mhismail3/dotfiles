#!/usr/bin/env python3
"""Apple Calendar CLI wrapper for the Codex skill.

Builds and runs a small Swift/EventKit helper from source. The helper uses
Apple's public EventKit API for reads and writes instead of Calendar's private
database or slow Calendar.app AppleScript queries.
"""

from __future__ import annotations

import os
import pathlib
import subprocess
import sys
import tempfile

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
SWIFT_SOURCE = SCRIPT_DIR / "calendar_helper.swift"
INFO_PLIST = SCRIPT_DIR / "calendar_helper_Info.plist"
CACHE_DIR = pathlib.Path.home() / ".local/share/codex/apple-calendar"
HELPER_APP = CACHE_DIR / "Codex Apple Calendar Helper.app"
HELPER_APP_CONTENTS = HELPER_APP / "Contents"
HELPER_APP_MACOS = HELPER_APP_CONTENTS / "MacOS"
HELPER = HELPER_APP_MACOS / "codex-apple-calendar-helper"
HELPER_INFO = HELPER_APP_CONTENTS / "Info.plist"
RUN_TIMEOUT_SECONDS = int(os.environ.get("CODEX_APPLE_CALENDAR_TIMEOUT", "120"))
PERMISSION_MESSAGE = (
    "Timed out waiting for Codex Apple Calendar Helper. If macOS is showing a "
    "Calendar permission prompt, approve it. Otherwise enable it in System "
    "Settings > Privacy & Security > Calendars, then rerun this command."
)


def source_mtime() -> float:
    return max(SWIFT_SOURCE.stat().st_mtime, INFO_PLIST.stat().st_mtime)


def build_helper() -> None:
    HELPER_APP_MACOS.mkdir(parents=True, exist_ok=True)
    if (
        HELPER.exists()
        and HELPER_INFO.exists()
        and min(HELPER.stat().st_mtime, HELPER_INFO.stat().st_mtime) >= source_mtime()
    ):
        return

    tmp = HELPER.with_suffix(".tmp")
    HELPER_INFO.write_text(INFO_PLIST.read_text(), encoding="utf-8")
    cmd = [
        "swiftc",
        str(SWIFT_SOURCE),
        "-o",
        str(tmp),
        "-framework",
        "EventKit",
    ]
    proc = subprocess.run(cmd, text=True, capture_output=True, check=False)
    if proc.returncode != 0:
        tmp.unlink(missing_ok=True)
        raise SystemExit(proc.stderr.strip() or f"swiftc failed: {proc.returncode}")

    os.chmod(tmp, 0o755)
    tmp.replace(HELPER)
    codesign = subprocess.run(
        ["codesign", "--force", "--deep", "--sign", "-", str(HELPER_APP)],
        text=True,
        capture_output=True,
        check=False,
    )
    if codesign.returncode != 0:
        HELPER.unlink(missing_ok=True)
        raise SystemExit(codesign.stderr.strip() or f"codesign failed: {codesign.returncode}")


def main() -> int:
    if not SWIFT_SOURCE.exists() or not INFO_PLIST.exists():
        raise SystemExit("Missing apple-calendar Swift helper source or Info.plist")
    build_helper()
    with tempfile.TemporaryDirectory(prefix="codex-apple-calendar-") as tmpdir:
        output_path = pathlib.Path(tmpdir) / "stdout.json"
        error_path = pathlib.Path(tmpdir) / "stderr.txt"
        cmd = [
            "open",
            "-W",
            "-n",
            str(HELPER_APP),
            "--args",
            *sys.argv[1:],
            "--codex-output",
            str(output_path),
            "--codex-error",
            str(error_path),
        ]
        try:
            proc = subprocess.run(cmd, check=False, timeout=RUN_TIMEOUT_SECONDS)
        except subprocess.TimeoutExpired:
            subprocess.run(
                ["osascript", "-e", 'tell application id "com.mhismail3.codex.apple-calendar-helper" to quit'],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            raise SystemExit(PERMISSION_MESSAGE)
        stdout = output_path.read_text(encoding="utf-8") if output_path.exists() else ""
        stderr = error_path.read_text(encoding="utf-8") if error_path.exists() else ""
        if stdout:
            sys.stdout.write(stdout)
        if stderr:
            sys.stderr.write(stderr)
        if proc.returncode != 0:
            return proc.returncode
        return 1 if stderr and not stdout else 0


if __name__ == "__main__":
    sys.exit(main())
