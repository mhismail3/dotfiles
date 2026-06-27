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

## Credential Handoff

Use 1Password for credential handoff instead of asking the user to paste secrets
into chat or terminal output.

Preferred flow:

1. Open 1Password Quick Access with `Cmd+Shift+Space`.
2. Search for the target item.
3. Use Quick Access copy actions or keyboard shortcuts to copy username and
   password.
4. Paste into the target app or browser field with `Cmd+V`.
5. Clear the clipboard after successful login.

Rules:

- Never reveal a password field.
- Never run `pbpaste`, `op item get`, or another command that prints secrets.
- Prefer Quick Access over opening the full item detail view; full item details
  can expose OTPs, backup codes, notes, or other sensitive fields through
  accessibility.
- Copy and paste passwords only; do not type or log them.
- If a login requires OTP, backup code, payment confirmation, or a new
  permission grant, pause for explicit user confirmation at that step.

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

## Logi Options+

Use Logi Options+ locally unless Logitech cloud profile sync is deliberately
needed. During onboarding, grant macOS privacy permissions manually when
prompted, decline diagnostics/usage analytics, skip Logitech login, and disable
recommendations and star-rating prompts.

Stable verified state:

1. Logi Options+ is installed.
2. App support state exists under `~/Library/Application Support/LogiOptionsPlus`.
3. Onboarding and macOS permission prompts are complete.
4. Diagnostics/Sentry, recommendations, and star-rating prompts are off.
5. Functional device alerts such as low battery remain on.

Do not track LogiOptionsPlus databases wholesale. They include generated cache,
detected installed apps, device state, and hardware-specific mappings. Button
mappings should be configured after the target Logitech device is connected, and
export/import should be researched only if a stable vendor-supported surface is
found.

## Folder Peek

Folder Peek owns its own launch-at-login state. Enable `Launch at login` inside
Folder Peek during onboarding, then verify that state rather than adding a second
login item from `.macos`.

Standard setup:

1. Enable `Launch at login` in Folder Peek.
2. Add `~/Library/CloudStorage/SynologyDrive-SynologyDrive/[Photos]/Screenshots`.
3. Grant folder access if macOS prompts.
4. Confirm the Folder Peek menu bar item opens the Screenshots folder menu.

Do not track the security-scoped bookmark directly. It is generated local app
state. `./app-status.sh verify folder-peek` checks for the expected folder,
login item, and non-secret bookmark path components.

## qBittorrent

qBittorrent is installed by Homebrew cask, but first launch can still require a
manual macOS Gatekeeper approval. Do that manually; do not bypass Gatekeeper from
the agent. The legal notice is also a manual first-launch boundary.

The deterministic baseline is applied by `setup.sh` after qBittorrent has been
quit:

1. Downloads: `~/Downloads/qBittorrent`.
2. Incomplete downloads: `~/Downloads/qBittorrent/incomplete`.
3. Add new torrents stopped by default.
4. Enable qBittorrent anonymous mode.
5. Disable local peer discovery.
6. Disable UPnP/NAT-PMP router port forwarding.
7. Disable WebUI.
8. Keep qBittorrent out of Login Items.

This baseline reduces accidental exposure, but it does not make torrent traffic
anonymous. For privacy-sensitive use, connect PIA before starting transfers. DHT
and PeX stay enabled for normal torrent functionality.

Do not track qBittorrent logs, resume data, `.torrent` files, downloaded content,
or generated state directories. `./app-status.sh verify qbittorrent` checks the
small non-secret INI baseline.

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
nc -vz -G 3 mooses-macbook-server 5900
```

`setup.sh` writes the native Screen Sharing connection to:

```text
~/Library/Containers/com.apple.ScreenSharing/Data/Library/Preferences/com.apple.ScreenSharing.plist
```

Inside that preference file, `connectionsStore` is a binary plist blob and is
the source of truth for the Screen Sharing Connections window. The generated
entry targets `vnc://mooses-macbook-server` on port `5900`.

`setup.sh` also creates a derived Screen Sharing location and CLI launcher:

```text
~/Library/Containers/com.apple.ScreenSharing/Data/Library/Application Support/Screen Sharing/Moose's MacBook Server.vncloc
```

```bash
screen-share-macbook-server
```

Use `screen-share-macbook-server` or `open vnc://mooses-macbook-server` for
programmatic connection handoff. The first connection can still require macOS
account credentials on the server, and Screen Sharing host trust files under
`Application Support/Screen Sharing Hosts` are runtime state, not dotfiles
state.

Taildrive should be enabled for this Mac with the full user folder shared as
`moose -> ~/`. The tailnet policy must grant `drive:share` and `drive:access`;
`./app-status.sh verify tailscale` checks those capabilities. The macOS GUI app
does not support the public `tailscale drive` folder commands, so `setup.sh`
uses Tailscale LocalAPI to upsert the share with a generated security-scoped
bookmark. The bookmark matters: a bare `name` and `path` share can exist in
LocalAPI while the Tailscale File Sharing UI still shows "No shared folders".
The same setup also writes:

```bash
defaults write io.tailscale.ipn.macsys FileSharingConfiguration -string show
defaults write io.tailscale.ipn.macsys TailscaleStartOnLogin -bool true
defaults write io.tailscale.ipn.macsys HideDockIcon -bool true
```

Use this read-only check when debugging:

```bash
tailscale debug localapi GET /localapi/v0/drive/shares
```

The `moose` share should include non-empty `bookmarkData`. If it does not,
rerun `setup.sh` on a Mac with Swift available or add the folder once through
Tailscale Settings > File Sharing so macOS grants the security-scoped bookmark.

PIA should remain an explicit-use VPN unless there is a concrete reason to make
it always-on. Do not enable PIA Advanced Kill Switch, connect-on-launch,
connection automation, or broad split-tunnel rules unless Tailscale reachability
to `mooses-macbook-server` is tested afterward.
