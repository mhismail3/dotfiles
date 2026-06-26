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
