# Codex Portable Setup

Use `codex_portable.py` to export, import, and sync this Codex setup across Macs.

## What It Ports

Core setup:

- `~/.codex/config.toml`
- `~/.codex/AGENTS.md`
- `~/.codex/hooks.json`
- `~/.codex/audit/session_audit.py`
- `~/.codex/audit/README.md`
- personal skills under `~/.codex/skills/`, excluding `.system`
- `~/.codex/things/` local skill support state, excluding auth files
- `~/LEDGER.jsonl`
- this portable tool and README

With `--full` or `--include-ui`:

- `~/.codex/.codex-global-state.json`
- `~/.codex/.codex-global-state.json.bak`
- `~/.codex/.personality_migration`
- `~/Library/Application Support/Codex/Preferences`
- `~/Library/Application Support/Codex/Local State`
- `~/Library/Application Support/Codex/browser-sidebar-local-servers.json`

With `--full` or `--include-sessions`:

- `~/.codex/sessions/` and `~/.codex/archived_sessions/` are exported from
  the source machine
- on import, those transcript files are stored under
  `~/.codex/audit/session_sources/<source-host>/`
- the transcript files are not imported into `~/.codex/sessions`,
  `~/.codex/archived_sessions`, or the app sidebar state

Optional clone-only state:

- `--include-runtime-dbs` snapshots `state_5.sqlite` and `logs_2.sqlite`.
- Import those only with `--replace-runtime-dbs` and only while Codex is quit.

Excluded by default:

- `auth.json`
- `installation_id`
- plugin caches
- shell snapshots
- worktrees
- temp folders
- browser cookies, trust tokens, shared storage, and other login/session web state

## One-Time Full Migration

On the source machine, quit Codex and run:

```bash
~/.codex/portable/codex_portable.py export \
  --out ~/Desktop/codex-portable-full \
  --full \
  --archive \
  --force
```

Copy `~/Desktop/codex-portable-full.tar.gz` to the new machine.

On the target machine, you do not need the script preinstalled. The export
bundle contains its own copy at
`payload/codex/portable/codex_portable.py`.

Install and launch Codex once, quit Codex, then run:

```bash
tar -xzf ~/Desktop/codex-portable-full.tar.gz -C ~/Desktop
python3 ~/Desktop/codex-portable-full/payload/codex/portable/codex_portable.py import \
  --bundle ~/Desktop/codex-portable-full \
  --yes
```

The import creates a backup under `~/.codex/portable/backups/import-<timestamp>`.

If the username or home path differs, the importer rewrites the source home path
to the target home path in config, instruction, skill, hook, portable, and UI
preference files. It does not rewrite session transcripts.

After import:

```bash
~/.codex/audit/session_audit.py index --force
~/.codex/audit/session_audit.py sessions --limit 5
```

Log in to Codex normally on the new machine. Do not copy `auth.json` unless you
explicitly accept the security risk.

## Ongoing Sync

Use a shared folder from iCloud Drive, Dropbox, Syncthing, or another file sync
tool. Do not run Codex concurrently on both machines while syncing UI
preferences.

This machine is configured to use iCloud Drive by default:

```bash
~/.codex/portable/codex_portable.py configure --icloud --create
```

The default remote is:

```text
~/Documents/CodexPortable
```

On this Mac, `~/Library/Mobile Documents/com~apple~CloudDocs/Documents` points
at `~/Documents`, so this remains under iCloud Drive Documents.

Because the default profile is full sync, these shorter commands are enough.
Full sync includes UI preferences and audit-only transcript history; it does not
populate the app sidebar with sessions from another machine.

```bash
~/.codex/portable/codex_portable.py sync-push
~/.codex/portable/codex_portable.py sync-pull --yes
```

For the first pull on a fresh machine, run the script from the shared bundle
itself:

```bash
python3 "$HOME/Documents/CodexPortable/current/payload/codex/portable/codex_portable.py" sync-pull \
  --remote "$HOME/Documents/CodexPortable" \
  --yes
```

After that first pull, the script is installed at
`~/.codex/portable/codex_portable.py`, so future pulls can use the shorter form.

After working on machine A:

```bash
~/.codex/portable/codex_portable.py sync-push
```

Before working on machine B:

```bash
~/.codex/portable/codex_portable.py sync-pull --yes
~/.codex/audit/session_audit.py index --force
```

For a smaller core-only push that excludes UI preferences and audit transcript
history:

```bash
~/.codex/portable/codex_portable.py sync-push --core-only --no-archive
```

The pull/import flow is merge-oriented for the files that can be merged safely:

- `~/.codex/config.toml` starts from the incoming synced config, then preserves
  local-only top-level keys, local-only keys inside existing tables, and
  local-only tables such as machine-specific trusted project entries
- incoming `config.toml` values win when the same scalar setting exists on both
  machines
- source-home paths in incoming config are rewritten to the target home before
  merging, which avoids duplicate trusted-project tables after pulling onto a
  machine with a different home path
- JSON UI/app settings are recursively merged; incoming scalar values win,
  local-only keys survive, and arrays are deduplicated
- non-JSON UI/app files are replaced from the incoming bundle after backup
- `~/LEDGER.jsonl` merges by `_meta.id`, keeping the newest timestamp when the
  same record exists on both machines
- audit transcript files are copied into
  `~/.codex/audit/session_sources/<source-host>/`, not into the Codex app
  sidebar directories
- missing audit transcript files are copied in
- identical audit transcript files are skipped
- conflicting audit transcript files are preserved as `.incoming-<timestamp>`
  instead of overwriting local history

This gives reliable audit/history continuity and prevents local machine-specific
settings from disappearing during normal pulls. It does not propagate deletions
for merged local-only settings; remove those deliberately on each machine if you
want an exact cleanup.

### Repair A Prior Sidebar Session Sync

Older versions of this portable workflow imported transcript files into
`~/.codex/sessions`, which can make another machine's sessions appear in the
Codex app sidebar. After pushing the updated workflow, run this on the affected
machine to move matching synced sidebar transcripts into audit-only storage:

```bash
python3 "$HOME/Documents/CodexPortable/current/payload/codex/portable/codex_portable.py" sync-pull \
  --remote "$HOME/Documents/CodexPortable" \
  --yes \
  --repair-sidebar-sessions
```

If those sessions still appear after restarting Codex, quit Codex and run the
state database repair too:

```bash
~/.codex/portable/codex_portable.py repair-sidebar-sessions --yes --repair-state-db
```

The repair command matches exact transcript fingerprints from the shared bundle,
moves matching active sidebar files under
`~/.codex/audit/session_sources/sidebar-repair-<timestamp>/`, prunes matching
`session_index.jsonl` entries, and creates backups under
`~/.codex/portable/backups/sidebar-repair-<timestamp>/`.

## Hardening Checks

Preview an import:

```bash
~/.codex/portable/codex_portable.py import --bundle /path/to/bundle
```

Show expected local files and configured remote:

```bash
~/.codex/portable/codex_portable.py status
~/.codex/portable/codex_portable.py doctor
```

Verify a bundle or configured remote:

```bash
~/.codex/portable/codex_portable.py verify --bundle /path/to/bundle
~/.codex/portable/codex_portable.py doctor --verify-remote
```

Sync commands use a lock file at the remote root to avoid overlapping local
runs. If a previous sync died and left a stale lock, inspect it first, then use
`--force-lock` only when you are sure no other sync is running.

## Auth And Secrets

Backups and bundles are sensitive. They can include local paths, project names,
prompt history, app UI state, Things audit data, and session transcripts.

`auth.json` is excluded by default. To include it, pass `--include-auth`, but the
recommended flow is to log in again on each machine.
