#!/usr/bin/env python3
"""Small Things 3 automation CLI for Codex skills.

Uses Things' AppleScript dictionary for supported reads/writes. Treat the local
Things SQLite database as private/read-only unless a separate task explicitly
requires inspection.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import sqlite3
import subprocess
import sys
from typing import Any

APP_NAME = "Things3"
REC_SEP = "\x1e"
FIELD_SEP = "\x1f"
DATABASE_ROOT = pathlib.Path.home() / "Library/Group Containers/JLMPQHK86H.com.culturedcode.ThingsMac"
DATABASE_GLOB = "ThingsData-*/Things Database.thingsdatabase/main.sqlite"


def run_applescript(script: str, args: list[str] | None = None) -> str:
    cmd = ["osascript", "-"]
    if args:
        cmd.extend(args)
    proc = subprocess.run(
        cmd,
        input=script,
        text=True,
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        raise SystemExit(proc.stderr.strip() or f"osascript failed: {proc.returncode}")
    return proc.stdout.rstrip("\n")


def parse_date(value: str | None) -> tuple[str, str, str]:
    if not value:
        return ("", "", "")
    aliases = {
        "today": dt.date.today(),
        "tomorrow": dt.date.today() + dt.timedelta(days=1),
    }
    date_value = aliases.get(value.lower())
    if date_value is None:
        try:
            date_value = dt.date.fromisoformat(value)
        except ValueError as exc:
            raise SystemExit(f"Use YYYY-MM-DD, today, or tomorrow for dates: {value}") from exc
    return (str(date_value.year), str(date_value.month), str(date_value.day))


def split_records(text: str) -> list[list[str]]:
    if not text:
        return []
    records = []
    for row in text.split(REC_SEP):
        if row:
            records.append(row.split(FIELD_SEP))
    return records


def things_db_path() -> pathlib.Path:
    candidates = sorted(DATABASE_ROOT.glob(DATABASE_GLOB))
    candidates = [path for path in candidates if path.exists()]
    if not candidates:
        raise SystemExit(f"Things database not found: {DATABASE_ROOT / DATABASE_GLOB}")
    return max(candidates, key=lambda path: path.stat().st_mtime)


def cf_datetime(value: Any) -> str:
    if value in (None, ""):
        return ""
    try:
        seconds = float(value) + 978307200
    except (TypeError, ValueError):
        return ""
    return dt.datetime.fromtimestamp(seconds, dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def compact_date(value: Any) -> str:
    if value in (None, ""):
        return ""
    try:
        raw = int(value)
    except (TypeError, ValueError):
        return ""
    if raw <= 0:
        return ""
    year = raw >> 16
    month = (raw >> 12) & 0x0F
    day = (raw >> 7) & 0x1F
    try:
        return dt.date(year, month, day).isoformat() + "T07:00:00Z"
    except ValueError:
        return ""


def db_status(code: Any) -> str:
    try:
        value = int(code)
    except (TypeError, ValueError):
        return "unknown"
    if value == 0:
        return "open"
    if value == 2:
        return "canceled"
    if value == 3:
        return "completed"
    return f"unknown:{value}"


def comma_join(values: list[str]) -> str:
    return ", ".join(value for value in values if value)


def snapshot_db_data() -> dict[str, Any]:
    path = things_db_path()
    conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    try:
        areas = [
            {
                "id": row["uuid"],
                "name": row["title"] or "",
                "tagNames": "",
                "collapsed": False,
            }
            for row in conn.execute("SELECT uuid, title FROM TMArea ORDER BY \"index\"")
        ]
        area_by_id = {area["id"]: area for area in areas}

        tags = [
            {
                "id": row["uuid"],
                "name": row["title"] or "",
                "keyboardShortcut": row["shortcut"] or "",
                "parentId": row["parent"] or "",
                "parentName": "",
            }
            for row in conn.execute("SELECT uuid, title, shortcut, parent FROM TMTag ORDER BY \"index\"")
        ]
        tag_by_id = {tag["id"]: tag for tag in tags}
        for tag in tags:
            if tag["parentId"] in tag_by_id:
                tag["parentName"] = tag_by_id[tag["parentId"]]["name"]

        task_tags: dict[str, list[str]] = {}
        for row in conn.execute("SELECT tasks, tags FROM TMTaskTag"):
            name = tag_by_id.get(row["tags"], {}).get("name", "")
            if name:
                task_tags.setdefault(row["tasks"], []).append(name)

        rows = list(
            conn.execute(
                """
                SELECT uuid, creationDate, userModificationDate, type, status, stopDate, trashed,
                       title, notes, start, startDate, deadline, area, project, "index"
                FROM TMTask
                WHERE title IS NOT NULL
                ORDER BY "index"
                """
            )
        )
        project_by_id: dict[str, dict[str, Any]] = {}
        projects: list[dict[str, Any]] = []
        todos: list[dict[str, Any]] = []
        for row in rows:
            status = db_status(row["status"])
            item = {
                "id": row["uuid"],
                "name": row["title"] or "",
                "notes": row["notes"] or "",
                "status": status,
                "trashed": bool(row["trashed"]),
                "creationDate": cf_datetime(row["creationDate"]),
                "modificationDate": cf_datetime(row["userModificationDate"]),
                "tagNames": comma_join(task_tags.get(row["uuid"], [])),
                "areaId": row["area"] or "",
                "areaName": area_by_id.get(row["area"] or "", {}).get("name", ""),
            }
            if row["stopDate"]:
                if status == "completed":
                    item["completionDate"] = cf_datetime(row["stopDate"])
                elif status == "canceled":
                    item["cancellationDate"] = cf_datetime(row["stopDate"])
            if row["startDate"]:
                item["when"] = compact_date(row["startDate"])
            if row["deadline"]:
                item["deadline"] = compact_date(row["deadline"])
            if int(row["type"] or 0) == 1:
                item["childTasks"] = []
                project_by_id[row["uuid"]] = item
                projects.append(item)
            elif int(row["type"] or 0) == 0:
                item["projectId"] = row["project"] or ""
                item["projectName"] = ""
                todos.append(item)

        for todo in todos:
            project = project_by_id.get(todo.get("projectId", ""))
            if project:
                todo["projectName"] = project.get("name", "")
                if not todo.get("areaId"):
                    todo["areaId"] = project.get("areaId", "")
                    todo["areaName"] = project.get("areaName", "")
                project.setdefault("childTasks", []).append({"id": todo["id"], "name": todo["name"], "status": todo["status"]})
        return {"todos": todos, "areas": areas, "projects": projects, "tags": tags, "source": "sqlite-readonly", "database": str(path)}
    finally:
        conn.close()


def load_json_field(fields: list[str], index: int = 0) -> dict[str, Any]:
    try:
        return json.loads(fields[index])
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Could not parse Things JSON: {fields[index][:120]}") from exc


SNAPSHOT_SCRIPT = r'''
on joinList(theList, delimiter)
    set oldDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to delimiter
    set joined to theList as text
    set AppleScript's text item delimiters to oldDelimiters
    return joined
end joinList

tell application "Things3"
    set recordDelimiter to ASCII character 30
    set fieldDelimiter to ASCII character 31

    set todoRows to {}
    repeat with t in to dos
        set projectId to ""
        set projectName to ""
        set areaId to ""
        set areaName to ""
        try
            set p to project of t
            set projectId to id of p
            set projectName to name of p
        end try
        try
            set a to area of t
            set areaId to id of a
            set areaName to name of a
        end try
        set end of todoRows to (_private_experimental_ json of t) & fieldDelimiter & projectId & fieldDelimiter & projectName & fieldDelimiter & areaId & fieldDelimiter & areaName
    end repeat

    set areaRows to {}
    repeat with a in areas
        set end of areaRows to (id of a) & fieldDelimiter & (name of a) & fieldDelimiter & (tag names of a) & fieldDelimiter & ((collapsed of a) as text)
    end repeat

    set projectRows to {}
    repeat with p in projects
        set areaId to ""
        set areaName to ""
        try
            set a to area of p
            set areaId to id of a
            set areaName to name of a
        end try
        set end of projectRows to (_private_experimental_ json of p) & fieldDelimiter & areaId & fieldDelimiter & areaName
    end repeat

    set tagRows to {}
    repeat with tg in tags
        set parentId to ""
        set parentName to ""
        try
            set pt to parent tag of tg
            set parentId to id of pt
            set parentName to name of pt
        end try
        set end of tagRows to (id of tg) & fieldDelimiter & (name of tg) & fieldDelimiter & (keyboard shortcut of tg) & fieldDelimiter & parentId & fieldDelimiter & parentName
    end repeat

    return (my joinList(todoRows, recordDelimiter)) & (ASCII character 29) & (my joinList(areaRows, recordDelimiter)) & (ASCII character 29) & (my joinList(projectRows, recordDelimiter)) & (ASCII character 29) & (my joinList(tagRows, recordDelimiter))
end tell
'''


LISTS_SCRIPT = r'''
on joinList(theList, delimiter)
    set oldDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to delimiter
    set joined to theList as text
    set AppleScript's text item delimiters to oldDelimiters
    return joined
end joinList

tell application "Things3"
    set recordDelimiter to ASCII character 30
    set fieldDelimiter to ASCII character 31

    set areaRows to {}
    repeat with a in areas
        set end of areaRows to (id of a) & fieldDelimiter & (name of a) & fieldDelimiter & (tag names of a) & fieldDelimiter & ((collapsed of a) as text)
    end repeat

    set projectRows to {}
    repeat with p in projects
        set areaId to ""
        set areaName to ""
        try
            set a to area of p
            set areaId to id of a
            set areaName to name of a
        end try
        set end of projectRows to (id of p) & fieldDelimiter & (name of p) & fieldDelimiter & ((status of p) as text) & fieldDelimiter & areaId & fieldDelimiter & areaName
    end repeat

    set tagRows to {}
    repeat with tg in tags
        set parentId to ""
        set parentName to ""
        try
            set pt to parent tag of tg
            set parentId to id of pt
            set parentName to name of pt
        end try
        set end of tagRows to (id of tg) & fieldDelimiter & (name of tg) & fieldDelimiter & (keyboard shortcut of tg) & fieldDelimiter & parentId & fieldDelimiter & parentName
    end repeat

    return (my joinList(areaRows, recordDelimiter)) & (ASCII character 29) & (my joinList(projectRows, recordDelimiter)) & (ASCII character 29) & (my joinList(tagRows, recordDelimiter))
end tell
'''


def field(fields: list[str], index: int) -> str:
    return fields[index] if len(fields) > index else ""


def normalized_status(value: str) -> str:
    text = value.strip().casefold()
    if text in {"open", "completed", "canceled", "cancelled"}:
        return "canceled" if text == "cancelled" else text
    return value.strip() or "unknown"


def lists_data() -> dict[str, Any]:
    raw = run_applescript(LISTS_SCRIPT)
    sections = raw.split("\x1d")
    while len(sections) < 3:
        sections.append("")
    areas = [
        {
            "id": field(fields, 0),
            "name": field(fields, 1),
            "tagNames": field(fields, 2),
            "collapsed": field(fields, 3).casefold() == "true",
        }
        for fields in split_records(sections[0])
    ]
    projects = [
        {
            "id": field(fields, 0),
            "name": field(fields, 1),
            "status": normalized_status(field(fields, 2)),
            "areaId": field(fields, 3),
            "areaName": field(fields, 4),
        }
        for fields in split_records(sections[1])
    ]
    tags = [
        {
            "id": field(fields, 0),
            "name": field(fields, 1),
            "keyboardShortcut": field(fields, 2),
            "parentId": field(fields, 3),
            "parentName": field(fields, 4),
        }
        for fields in split_records(sections[2])
    ]
    return {"areas": areas, "projects": projects, "tags": tags, "source": "applescript-lists-fast"}


def snapshot_data() -> dict[str, Any]:
    raw = run_applescript(SNAPSHOT_SCRIPT)
    sections = raw.split("\x1d")
    while len(sections) < 4:
        sections.append("")

    todos = []
    for fields in split_records(sections[0]):
        item = load_json_field(fields)
        if item.get("cancellationDate"):
            item["status"] = "canceled"
        elif item.get("completionDate"):
            item["status"] = "completed"
        item["projectId"] = fields[1] if len(fields) > 1 else ""
        item["projectName"] = fields[2] if len(fields) > 2 else ""
        item["areaId"] = fields[3] if len(fields) > 3 else ""
        item["areaName"] = fields[4] if len(fields) > 4 else ""
        todos.append(item)

    areas = []
    for fields in split_records(sections[1]):
        areas.append(
            {
                "id": fields[0],
                "name": fields[1] if len(fields) > 1 else "",
                "tagNames": fields[2] if len(fields) > 2 else "",
                "collapsed": (fields[3].lower() == "true") if len(fields) > 3 else False,
            }
        )

    projects = []
    for fields in split_records(sections[2]):
        item = load_json_field(fields)
        if item.get("cancellationDate"):
            item["status"] = "canceled"
        elif item.get("completionDate"):
            item["status"] = "completed"
        item["areaId"] = fields[1] if len(fields) > 1 else ""
        item["areaName"] = fields[2] if len(fields) > 2 else ""
        projects.append(item)

    tags = []
    for fields in split_records(sections[3]):
        tags.append(
            {
                "id": fields[0],
                "name": fields[1] if len(fields) > 1 else "",
                "keyboardShortcut": fields[2] if len(fields) > 2 else "",
                "parentId": fields[3] if len(fields) > 3 else "",
                "parentName": fields[4] if len(fields) > 4 else "",
            }
        )

    return {"todos": todos, "areas": areas, "projects": projects, "tags": tags}


def print_json(data: Any) -> None:
    print(json.dumps(data, indent=2, ensure_ascii=False, sort_keys=True))


def cmd_snapshot(args: argparse.Namespace) -> None:
    data = snapshot_data() if args.applescript else snapshot_db_data()
    if args.open_only:
        data["todos"] = [t for t in data["todos"] if t.get("status") == "open" and not t.get("trashed")]
        data["projects"] = [p for p in data["projects"] if p.get("status") == "open" and not p.get("trashed")]
    print_json(data)


def cmd_snapshot_db(args: argparse.Namespace) -> None:
    data = snapshot_db_data()
    if args.open_only:
        data["todos"] = [t for t in data["todos"] if t.get("status") == "open" and not t.get("trashed")]
        data["projects"] = [p for p in data["projects"] if p.get("status") == "open" and not p.get("trashed")]
    print_json(data)


def cmd_search(args: argparse.Namespace) -> None:
    needle = args.query.casefold()
    data = snapshot_db_data()
    results = []
    for item in data["todos"]:
        if args.open_only and (item.get("status") != "open" or item.get("trashed")):
            continue
        haystack = "\n".join(
            str(item.get(key, ""))
            for key in ("name", "notes", "tagNames", "projectName", "areaName", "status")
        ).casefold()
        if needle in haystack:
            results.append(item)
    print_json(results)


def cmd_lists(_: argparse.Namespace) -> None:
    data = lists_data()
    print_json({"areas": data["areas"], "projects": data["projects"], "tags": data["tags"]})


ADD_SCRIPT = r'''
on makeDate(yearText, monthText, dayText)
    set d to current date
    set year of d to (yearText as integer)
    set month of d to (monthText as integer)
    set day of d to (dayText as integer)
    set time of d to 0
    return d
end makeDate

on run argv
    set titleText to item 1 of argv
    set notesText to item 2 of argv
    set tagsText to item 3 of argv
    set listName to item 4 of argv
    set dueYear to item 5 of argv
    set dueMonth to item 6 of argv
    set dueDay to item 7 of argv
    set whenYear to item 8 of argv
    set whenMonth to item 9 of argv
    set whenDay to item 10 of argv

    tell application "Things3"
        set targetContainer to missing value
        set targetKind to ""
        if listName is not "" then
            try
                set targetContainer to first list whose name is listName
                set targetKind to "list"
            end try
            if targetContainer is missing value then
                try
                    set targetContainer to first project whose name is listName
                    set targetKind to "project"
                end try
            end if
            if targetContainer is missing value then
                try
                    set targetContainer to first area whose name is listName
                    set targetKind to "area"
                end try
            end if
            if targetContainer is missing value then
                error "No Things list, project, or area found with name " & listName
            end if
        end if

        if targetKind is "project" then
            if dueYear is "" then
                set newToDo to make new to do at end of to dos of targetContainer with properties {name:titleText, notes:notesText, tag names:tagsText}
            else
                set dueDate to my makeDate(dueYear, dueMonth, dueDay)
                set newToDo to make new to do at end of to dos of targetContainer with properties {name:titleText, notes:notesText, tag names:tagsText, due date:dueDate}
            end if
        else
            if dueYear is "" then
                set newToDo to make new to do with properties {name:titleText, notes:notesText, tag names:tagsText}
            else
                set dueDate to my makeDate(dueYear, dueMonth, dueDay)
                set newToDo to make new to do with properties {name:titleText, notes:notesText, tag names:tagsText, due date:dueDate}
            end if

            if listName is not "" then
                move newToDo to targetContainer
            end if
        end if

        if whenYear is not "" then
            set whenDate to my makeDate(whenYear, whenMonth, whenDay)
            schedule newToDo for whenDate
        end if

        return _private_experimental_ json of newToDo
    end tell
end run
'''


def cmd_add(args: argparse.Namespace) -> None:
    due = parse_date(args.deadline)
    when = parse_date(args.when)
    tags = ", ".join(args.tag) if args.tag else ""
    output = run_applescript(
        ADD_SCRIPT,
        [args.title, args.notes or "", tags, args.list or "", *due, *when],
    )
    print_json(json.loads(output))


FIND_AND_MUTATE_SCRIPT = r'''
on makeDate(yearText, monthText, dayText)
    set d to current date
    set year of d to (yearText as integer)
    set month of d to (monthText as integer)
    set day of d to (dayText as integer)
    set time of d to 0
    return d
end makeDate

on run argv
    set targetId to item 1 of argv
    set actionName to item 2 of argv
    set valueOne to item 3 of argv
    set valueTwo to item 4 of argv
    set valueThree to item 5 of argv

    tell application "Things3"
        set targetToDo to missing value
        repeat with t in to dos
            if id of t is targetId then
                set targetToDo to contents of t
                exit repeat
            end if
        end repeat

        if targetToDo is missing value then
            error "No Things to-do found with id " & targetId
        end if

        if actionName is "complete" then
            set status of targetToDo to completed
            return _private_experimental_ json of targetToDo
        else if actionName is "cancel" then
            set status of targetToDo to canceled
            return _private_experimental_ json of targetToDo
        else if actionName is "schedule" then
            set whenDate to my makeDate(valueOne, valueTwo, valueThree)
            schedule targetToDo for whenDate
            return _private_experimental_ json of targetToDo
        else if actionName is "deadline" then
            set dueDate to my makeDate(valueOne, valueTwo, valueThree)
            set due date of targetToDo to dueDate
            return _private_experimental_ json of targetToDo
        else if actionName is "move" then
            set targetContainer to missing value
            set targetKind to ""
            try
                set targetContainer to first list whose name is valueOne
                set targetKind to "list"
            end try
            if targetContainer is missing value then
                try
                    set targetContainer to first project whose name is valueOne
                    set targetKind to "project"
                end try
            end if
            if targetContainer is missing value then
                try
                    set targetContainer to first area whose name is valueOne
                    set targetKind to "area"
                end try
            end if
            if targetContainer is missing value then
                error "No Things list, project, or area found with name " & valueOne
            end if
            if targetKind is "project" then
                set project of targetToDo to targetContainer
            else if targetKind is "area" then
                set area of targetToDo to targetContainer
            else
                move targetToDo to targetContainer
            end if
            return _private_experimental_ json of targetToDo
        else if actionName is "show" then
            show targetToDo
            return _private_experimental_ json of targetToDo
        else if actionName is "edit" then
            edit targetToDo
            return _private_experimental_ json of targetToDo
        else if actionName is "delete" then
            set deletedId to id of targetToDo
            delete targetToDo
            return "{\"deleted\":\"" & deletedId & "\"}"
        end if
    end tell
end run
'''


def mutate_by_id(item_id: str, action: str, values: list[str] | None = None) -> None:
    values = values or []
    padded = (values + ["", "", ""])[:3]
    output = run_applescript(FIND_AND_MUTATE_SCRIPT, [item_id, action, *padded])
    print_json(json.loads(output))


def cmd_complete(args: argparse.Namespace) -> None:
    mutate_by_id(args.id, "complete")


def cmd_cancel(args: argparse.Namespace) -> None:
    mutate_by_id(args.id, "cancel")


def cmd_schedule(args: argparse.Namespace) -> None:
    mutate_by_id(args.id, "schedule", list(parse_date(args.when)))


def cmd_deadline(args: argparse.Namespace) -> None:
    mutate_by_id(args.id, "deadline", list(parse_date(args.deadline)))


def cmd_move(args: argparse.Namespace) -> None:
    mutate_by_id(args.id, "move", [args.list])


def cmd_show(args: argparse.Namespace) -> None:
    mutate_by_id(args.id, "show")


def cmd_edit(args: argparse.Namespace) -> None:
    mutate_by_id(args.id, "edit")


def cmd_delete(args: argparse.Namespace) -> None:
    if not args.yes:
        raise SystemExit("Refusing to delete without --yes. Prefer complete or cancel.")
    mutate_by_id(args.id, "delete")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Automate Things 3 through AppleScript.")
    sub = parser.add_subparsers(dest="command", required=True)

    snapshot = sub.add_parser("snapshot", help="Export Things areas/projects/tags/to-dos as JSON.")
    snapshot.add_argument("--open-only", action="store_true", help="Include only open to-dos/projects.")
    snapshot.add_argument("--applescript", action="store_true", help="Use the slower AppleScript export instead of the read-only database.")
    snapshot.set_defaults(func=cmd_snapshot)

    snapshot_db = sub.add_parser("snapshot-db", help="Export Things data from the local database in read-only mode.")
    snapshot_db.add_argument("--open-only", action="store_true", help="Include only open to-dos/projects.")
    snapshot_db.set_defaults(func=cmd_snapshot_db)

    search = sub.add_parser("search", help="Search to-dos by title, notes, tags, area, or project.")
    search.add_argument("query")
    search.add_argument("--all", dest="open_only", action="store_false", help="Include completed/canceled items.")
    search.set_defaults(open_only=True, func=cmd_search)

    lists = sub.add_parser("lists", help="List Things areas, projects, and tags.")
    lists.set_defaults(func=cmd_lists)

    add = sub.add_parser("add", help="Create a to-do.")
    add.add_argument("title")
    add.add_argument("--notes", default="")
    add.add_argument("--tag", action="append", default=[], help="Tag name. Repeatable.")
    add.add_argument("--list", help="Target list/project/area name, e.g. Inbox or Home.")
    add.add_argument("--when", help="Schedule date: YYYY-MM-DD, today, or tomorrow.")
    add.add_argument("--deadline", help="Deadline date: YYYY-MM-DD, today, or tomorrow.")
    add.set_defaults(func=cmd_add)

    complete = sub.add_parser("complete", help="Mark a to-do completed by id.")
    complete.add_argument("id")
    complete.set_defaults(func=cmd_complete)

    cancel = sub.add_parser("cancel", help="Mark a to-do canceled by id.")
    cancel.add_argument("id")
    cancel.set_defaults(func=cmd_cancel)

    schedule = sub.add_parser("schedule", help="Schedule a to-do by id.")
    schedule.add_argument("id")
    schedule.add_argument("when", help="YYYY-MM-DD, today, or tomorrow.")
    schedule.set_defaults(func=cmd_schedule)

    deadline = sub.add_parser("deadline", help="Set a deadline by id.")
    deadline.add_argument("id")
    deadline.add_argument("deadline", help="YYYY-MM-DD, today, or tomorrow.")
    deadline.set_defaults(func=cmd_deadline)

    move = sub.add_parser("move", help="Move a to-do to a Things list/project/area by name.")
    move.add_argument("id")
    move.add_argument("list")
    move.set_defaults(func=cmd_move)

    show = sub.add_parser("show", help="Reveal a to-do in Things by id.")
    show.add_argument("id")
    show.set_defaults(func=cmd_show)

    edit = sub.add_parser("edit", help="Open Things edit UI for a to-do by id.")
    edit.add_argument("id")
    edit.set_defaults(func=cmd_edit)

    delete = sub.add_parser("delete", help="Delete a to-do by id. Prefer complete/cancel.")
    delete.add_argument("id")
    delete.add_argument("--yes", action="store_true")
    delete.set_defaults(func=cmd_delete)

    return parser


def main() -> int:
    args = build_parser().parse_args()
    args.func(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
