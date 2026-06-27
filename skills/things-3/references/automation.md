# Things 3 Automation Reference

## Supported Surfaces

- App bundle: `/Applications/Things3.app`
- Bundle identifier: `com.culturedcode.ThingsMac`
- AppleScript dictionary: `sdef /Applications/Things3.app`
- Local database:
  `~/Library/Group Containers/JLMPQHK86H.com.culturedcode.ThingsMac/ThingsData-*/Things Database.thingsdatabase/main.sqlite`

Use AppleScript for writes. The SQLite database is useful for emergency
inspection only and must be treated as read-only/private.

## AppleScript Capabilities

Things exposes:

- Application properties: `current list url`, `current list name`
- Elements: `lists`, `to dos`, `projects`, `areas`, `contacts`, `tags`,
  `selected to dos`
- To-do properties: `id`, `name`, `creation date`, `modification date`,
  `due date`, `activation date`, `completion date`, `cancellation date`,
  `status`, `tag names`, `notes`, `project`, `area`, `contact`
- Status values: `open`, `completed`, `canceled`
- Commands: `show`, `edit`, `move`, `schedule`, `log completed now`,
  `empty trash`, `add contact named`, `parse quicksilver input`,
  `show quick entry panel`

The skill script uses the hidden read-only `_private_experimental_ json`
property to make snapshots parseable. Do not rely on hidden write commands.

## Data Safety

Never commit or back up raw Things task databases in dotfiles. They contain live
task data and may include personal details. If backup is required, use Things
Cloud or Things' native backup/export behavior.

Avoid destructive writes:

- Prefer `completed` or `canceled` status over deleting tasks.
- Do not empty Trash unless explicitly requested.
- Do not enable Reminders import without user confirmation; imported reminders
  are deleted from Reminders.
- Do not enable Calendar integration without user confirmation; it requires
  calendar privacy access.

## Script Notes

`scripts/things.py` shells out to `osascript` and expects Things 3 to be
installed. It can launch Things implicitly through AppleScript. Output is JSON.

Date arguments accept `YYYY-MM-DD`, `today`, or `tomorrow`.
