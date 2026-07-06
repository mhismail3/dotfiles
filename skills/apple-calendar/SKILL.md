---
name: apple-calendar
description: Read and write Apple Calendar events on this Mac. Use when Codex needs to list calendars, inspect agenda/free time, search events, create events, reschedule/edit events, or delete events through local Apple Calendar data.
---

# Apple Calendar

Use `scripts/calendar.py`, which builds and runs a small Swift/EventKit helper.
It returns JSON and uses Apple's public Calendar API instead of the private
Calendar database or slow Calendar.app AppleScript event queries.

## Quick Start

```bash
~/.codex/skills/apple-calendar/scripts/calendar.py calendars
~/.codex/skills/apple-calendar/scripts/calendar.py today
~/.codex/skills/apple-calendar/scripts/calendar.py agenda --from today --to tomorrow
~/.codex/skills/apple-calendar/scripts/calendar.py search "dentist" --from today --to 2026-07-31
~/.codex/skills/apple-calendar/scripts/calendar.py create "Focus block" --start "2026-07-01 09:00" --duration-minutes 90 --calendar Default
~/.codex/skills/apple-calendar/scripts/calendar.py create "Building window cleaning" --start "2026-07-14" --duration-days 4 --all-day --calendar Default --notes "Service window: 9:00 AM-4:00 PM each day."
~/.codex/skills/apple-calendar/scripts/calendar.py create "Class" --start "2026-08-04 15:00" --end "2026-08-04 17:00" --time-zone America/Los_Angeles --repeat weekly --repeat-days tue,thu --repeat-until 2026-08-31 --calendar Default
~/.codex/skills/apple-calendar/scripts/calendar.py validate-write --calendar Default
```

## Operating Rules

- Use the EventKit-backed wrapper for reads and writes.
- Never read or write Calendar's private local databases directly.
- Before editing or deleting an existing event, search/list first and identify
  the target `id` or `calendarItemId`.
- Prefer `update` for rescheduling/editing.
- For consecutive multi-day maintenance or service windows that list daily
  working hours, create one all-day multi-day event per workstream and put the
  daily hours in notes. Do not create daily recurring timed events unless the
  user asks for separate occurrences or the notice describes separate
  appointments.
- Use `delete` only when the user explicitly asks or the script is deleting a
  temporary event it created for validation.
- For recurring events, use `delete <id> --yes --span all` to remove the whole
  recurring series from the selected occurrence forward.
- For create/update operations that could invite attendees, send messages, or
  affect shared calendars, confirm the calendar target first. This wrapper does
  not create or modify attendees.
- After writes, run `agenda` or `search` to verify the result.
- Do not commit calendar data, account identifiers, Calendar caches, or local
  Calendar databases.
- If Calendar access is denied, grant access to `Codex Apple Calendar Helper` in
  System Settings > Privacy & Security > Calendars.
- If the Swift helper was edited and rebuilt, macOS may ask for Calendar access
  again because the local helper app was re-signed.

## Common Tasks

### Understand The Calendar

Run `calendars` to identify writable calendars, then `today`, `tomorrow`, or
`agenda --from YYYY-MM-DD --to YYYY-MM-DD` for schedule review.

### Create Events

Use `create` with `--start` and either `--end` or `--duration-minutes`.
Use `--all-day` for all-day events.
Use `--time-zone IANA_ID` when the user's requested time zone differs from this
Mac's local time zone. Do not pass `--time-zone` with `--all-day`; all-day
events should use local calendar dates.
For multi-day all-day events, prefer `--duration-days N` or set `--end` to the
exclusive next date. Put any daily service window, such as "9:00 AM-4:00 PM",
in `--notes` instead of making repeated timed blocks.
Use `--repeat weekly --repeat-days tue,thu --repeat-until YYYY-MM-DD` for
bounded weekly recurrence.

### Update Events

Use `search` or `agenda` to find the event `id`, then call:

- `update <id> --title ...`
- `update <id> --start ... --end ...`
- `update <id> --location ...`
- `update <id> --notes ...`

### Delete Events

Use `delete <id> --yes` for a single event or occurrence.
Use `delete <id> --yes --span all` for a recurring series.

### User-Facing Reviews

When summarizing events, include calendar name, title, concrete dates/times,
location, and conflicts. Avoid dumping raw JSON unless the user asks for it.
