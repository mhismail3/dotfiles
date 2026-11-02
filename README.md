# dotfiles — test-host

Setup for **test-host**: a headless M4 Mac mini whose only job is running builds
and tests offloaded from the main Mac (Xcode, iOS simulators, Node suites, Tart VMs).
Branched from `mac-mini` and stripped of everything a build box doesn't need
(no editors, browsers, AI CLIs, sync clients, VPNs, Docker, Ollama, language managers).

Accessed over Tailscale SSH. No display, no iCloud.

## Quick start (after a factory reset)

```bash
xcode-select --install          # git for the clone
git clone -b test-host https://github.com/mhismail3/dotfiles.git ~/.dotfiles
HOST_NAME=tron-test-mini ~/.dotfiles/setup.sh
```

Re-run any time (idempotent); `--reset` re-applies everything.

## Steps

1. Command Line Tools
2. Homebrew
3. Dotfiles clone/update (`test-host` branch)
4. `brew bundle` — git, git-lfs, gh, jq, tmux, uv, coreutils, xcodes, aria2, tart, tailscale
5. Symlinks — zsh, git, tmux
6. `gh auth login` + Git LFS
7. Xcode `$XCODE_VERSION` (default 26.6) via `xcodes`, license, first launch,
   iOS `$IOS_RUNTIME` (default 26.5) simulator runtime. Keep in sync with
   `tron/config/ci-toolchain.env`.
8. Tailscale as a boot-time system daemon with Tailscale SSH (`tailscale up --ssh`)
9. `macos/.macos` — hostname, SSH + Screen Sharing, never sleep, auto-restart,
   auto-login, updates check-only (no Xcode/macOS auto-install), then `macos/lean.sh`

Project toolchains (Node, xcodegen) are pinned and installed by each repo, e.g.
`scripts/install-ci-tools.sh` in tron.

## Lean defaults (`macos/lean.sh`)

Mirrors what was turned off by hand on the main Mac server to save memory/CPU:

| Setting | State | Undo |
|---|---|---|
| Spotlight indexing | off on all volumes | `sudo mdutil -a -i on` |
| Siri, assistantd | disabled | `launchctl enable gui/$UID/com.apple.Siri.agent` |
| Folder Actions, Script Menu, seed usage, MDM enroll agent | disabled | `launchctl enable gui/$UID/<label>` |
| CSCSupportd, mdmclient runatboot, ftpd | disabled | `sudo launchctl enable system/<label>` |
| Time Machine | off | `sudo tmutil enable` |
| Transparency / motion / window animations | reduced | toggle in Accessibility |
| Crash & feedback dialogs | suppressed | `defaults delete com.apple.CrashReporter DialogType` |

## Manual, once

FileVault off → Automatic login → no OS-level iCloud → wired Ethernet with a
DHCP reservation → restart.
