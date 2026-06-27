# App Setup

This repo treats app setup as part of the machine bootstrap, not as an
afterthought. `Brewfile` installs apps, `.macos` applies stable macOS defaults,
and `apps.yaml` tracks the remaining app-specific setup that needs either
automation, verification, or deliberate manual action.

## Operating Model

Use this loop when setting up a fresh Mac or adding a new app:

1. Install with `./setup.sh` or `brew bundle --file=Brewfile`.
2. Run `./app-status.sh summary` to see install and manual-step status.
3. Run `./app-status.sh next` to walk the current setup queue.
4. Complete manual auth, permission, and onboarding steps with the user present.
5. Run app-specific verification checks from `apps.yaml`.
6. Update `apps.yaml` with anything learned, especially boundaries that should
   not be re-debugged later.

Do not store credentials, account identifiers, generated app databases, app
caches, or private sync contents in this repo.

## Setup Order

The default order optimizes for unlocking later steps:

| Phase | Apps | Why |
|---|---|---|
| identity | 1Password | Secrets and browser extension setup unblock the rest |
| browser | Google Chrome | Standard browser and extension surface |
| launcher | Raycast | Daily command hub and Cmd+Space behavior |
| agent | Codex, Claude Code, Claude | Agent tools and auth |
| network | Tailscale, Private Internet Access | Remote access and VPN |
| storage | Google Drive, Synology Drive | File availability |
| development | Docker, VS Code, Xcode, DB Browser | Local development |
| input | Superwhisper | Dictation and permissions |
| knowledge/productivity | Obsidian, Things | Personal systems |
| hardware/utility/media | Logi Options+, Hand Mirror, Folder Peek, VLC, Stremio, qBittorrent | Device and secondary tools |

## What To Automate

Automate stable, repeatable state:

- Homebrew and Mac App Store installs.
- Dock layout and login items.
- macOS defaults and app defaults with documented keys.
- CLI config files that are safe to merge.
- Verification commands that do not mutate user data.

Keep these manual unless a stable vendor-supported interface is found:

- Account login and OAuth flows.
- macOS Privacy and Security grants.
- App onboarding flows that change often.
- Sync folder choices and account-specific paths.
- Hardware-specific mappings without export/import support.

## Synology Drive

Synology Drive stores local task metadata in
`~/Library/Application Support/SynologyDrive/data/db/sys.sqlite`, with companion
config and session state under `~/Library/Application Support/SynologyDrive`.
That state is useful for verification, not for dotfile restore. It includes
server, account, session, private-key, and macOS File Provider state, so the
bootstrap should install the app and verify the task rather than copying the
database.

Standard setup:

1. Sign in to the Synology server.
2. Create a sync task named `SynologyDrive`.
3. Select `/Users/moose` as the local parent folder.
4. Uncheck `Create an empty "SynologyDrive" folder`.
5. Use the Synology `home` share at remote path `/`.
6. Confirm `~/SynologyDrive` points to
   `~/Library/CloudStorage/SynologyDrive-SynologyDrive`.

`./app-status.sh verify synology-drive` checks the installed app, local symlink,
non-sensitive task columns, and preferred UI toggles in the Synology SQLite
database.

Safe automated preferences:

- `enable_desktop_notification = 0`: disable desktop notifications for file
  events.
- `use_black_white_icon = 1`: enable the minimalist menu bar icon.

`setup.sh` applies only those non-secret `system_table` keys after Synology Drive
has created the database. If the database does not exist yet, setup skips this
step and prints the re-run command.

## Docker Desktop

Use Docker's recommended first-run settings. The baseline keeps Docker Desktop
out of Login Items so it does not consume memory or battery unless containers are
needed.

Expected verified state:

1. Docker Desktop is installed and the `docker` CLI is available.
2. Docker daemon responds to `docker info`.
3. Current context is `desktop-linux`.
4. `/var/run/docker.sock` exists as Docker Desktop's compatibility symlink.
5. `AutoStart` is `false`.
6. `UseContainerdSnapshotter` is `true`.

Do not track `~/.docker/config.json` wholesale because it can include Docker Hub
auth and credential helper state.

## Commands

```bash
./app-status.sh summary
./app-status.sh next
./app-status.sh manual raycast
./app-status.sh verify codex
./app-status.sh open google-chrome
```

## Maintenance Rules

- When adding an app to `Brewfile`, add it to `apps.yaml` in the same change.
- When removing an app from `Brewfile`, remove or move its setup entry.
- If a manual setup issue is encountered twice, encode the fix or boundary in
  `apps.yaml` and, when appropriate, `README.md`.
- If an app exposes a stable config export, prefer tracking a sanitized baseline
  over relying on UI memory.
- If an app stores secrets or high-churn state in its config export, do not track
  that export directly.

## Network Remote-Control Invariant

Tailscale access to the always-on home MacBook server is a setup invariant. The
expected peer is `mooses-macbook-server`; verify it with:

```bash
tailscale status
tailscale ping --c 1 --timeout=3s mooses-macbook-server
```

PIA should remain an explicit-use VPN unless there is a concrete reason to make
it always-on. Do not enable PIA Advanced Kill Switch, connect-on-launch,
connection automation, or broad split-tunnel rules unless Tailscale reachability
to `mooses-macbook-server` is tested afterward.
